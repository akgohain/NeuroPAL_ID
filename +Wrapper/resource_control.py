#!/usr/bin/env python3
"""Serialize heavy jobs and record their process-tree memory use."""
from __future__ import annotations

import argparse
import json
import math
import os
import re
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid

_active_lease = None


class CancellationError(RuntimeError):
    """The caller requested cancellation of the supervised job."""


def available_memory_bytes():
    if sys.platform == 'darwin':
        try:
            physical = int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True))
            pressure = subprocess.check_output(['memory_pressure', '-Q'], text=True)
            match = re.search(r'System-wide memory free percentage:\s*(\d+)%', pressure)
            return physical*int(match.group(1))//100 if match else None
        except (OSError, ValueError, subprocess.CalledProcessError):
            return None
    if sys.platform.startswith('linux'):
        try:
            match = re.search(r'^MemAvailable:\s*(\d+) kB', Path('/proc/meminfo').read_text(), re.MULTILINE)
            return int(match.group(1))*1024 if match else None
        except OSError:
            return None
    try:
        import psutil
        return psutil.virtual_memory().available
    except ImportError:
        return None


def lock_path():
    return Path(os.environ.get('NEUROPAL_JOB_LOCK', str(Path(tempfile.gettempdir()) / 'neuropal-heavy-job.lock')))


def owner_path(path):
    return Path(str(path) + '.owner.json')


class JobLease:
    """Hold an OS-released file lock; authorized children share the token."""

    def __init__(self, name):
        self.name = name
        self.file = None
        self.token = None
        self.owner_file = None

    def __enter__(self):
        global _active_lease
        path = lock_path()
        self.owner_file = owner_path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        inherited = os.environ.get('NEUROPAL_JOB_TOKEN')
        if _active_lease is not None and _active_lease[0] == os.getpid():
            if inherited == _active_lease[1]:
                self.token = inherited
                return self
            raise RuntimeError('Another NeuroPAL heavy job is running in this process')
        if inherited:
            try:
                owner = json.loads(owner_path(path).read_text())
                current = process_snapshot().get(int(owner['pid']))
                if owner['token'] == inherited and current is not None and \
                        owner.get('start', current[2]) == current[2]:
                    self.token = inherited
                    return self
            except (OSError, ValueError, KeyError, TypeError):
                pass
        self.file = path.open('a+b')
        try:
            if os.name == 'nt':
                import msvcrt
                self.file.seek(0)
                if not self.file.read(1):
                    self.file.write(b' ')
                    self.file.flush()
                self.file.seek(0)
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.lockf(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB, 1)
        except OSError as exc:
            self.file.close()
            self.file = None
            raise RuntimeError('Another NeuroPAL heavy job is running. Wait for it to finish or cancel it.') from exc
        self.token = uuid.uuid4().hex
        pending = Path(str(owner_path(path)) + '.' + self.token + '.tmp')
        try:
            start = process_snapshot().get(os.getpid(), (0, 0, None))[2]
            pending.write_text(json.dumps(dict(pid=os.getpid(), start=start, token=self.token, name=self.name)))
            pending.replace(owner_path(path))
        except BaseException:
            self.file.close()
            self.file = None
            pending.unlink(missing_ok=True)
            raise
        _active_lease = (os.getpid(), self.token)
        return self

    def __exit__(self, *_):
        global _active_lease
        if self.file is not None:
            try:
                try:
                    owner = json.loads(self.owner_file.read_text())
                except (OSError, ValueError):
                    owner = {}
                if isinstance(owner, dict) and owner.get('token') == self.token:
                    self.owner_file.unlink(missing_ok=True)
            finally:
                self.file.close()
                self.file = None
                _active_lease = None

    def environment(self):
        environment = os.environ.copy()
        environment['NEUROPAL_JOB_TOKEN'] = self.token
        return environment


def process_snapshot():
    if os.name == 'nt':
        # Installed ML environments supply psutil on Windows.
        import psutil
        result = {}
        for process in psutil.process_iter(['pid', 'ppid', 'memory_info', 'create_time']):
            try:
                item = process.info
                if item['ppid'] is None or item['create_time'] is None:
                    continue
                memory = item['memory_info']
                result[item['pid']] = (item['ppid'], memory.rss // 1024 if memory is not None else 0,
                                       str(item['create_time']))
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        return result
    output = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss=,stat=,lstart='], text=True)
    result = {}
    for line in output.splitlines():
        fields = line.split(maxsplit=4)
        if len(fields) == 5 and not fields[3].startswith('Z'):
            result[int(fields[0])] = (int(fields[1]), int(fields[2]), fields[4])
    return result


def owned_processes(snapshot, root, known):
    owned = {pid for pid, start in known.items() if pid in snapshot and snapshot[pid][2] == start}
    if root in snapshot and (root not in known or snapshot[root][2] == known[root]):
        owned.add(root)
    while True:
        children = {pid for pid, item in snapshot.items() if item[0] in owned}
        updated = owned | children
        if updated == owned:
            break
        owned = updated
    known.update({pid: snapshot[pid][2] for pid in owned})
    return owned


def signal_owned_process(pid, start, force):
    if os.name == 'nt':
        import psutil
        try:
            child = psutil.Process(pid)
            if str(child.create_time()) == start:
                child.kill() if force else child.terminate()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    else:
        try:
            os.kill(pid, signal.SIGKILL if force else signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass


def stop_processes(process, known):
    for force in (False, True):
        snapshot = process_snapshot()
        owned = owned_processes(snapshot, process.pid, known)
        for pid in sorted(owned, reverse=True):
            signal_owned_process(pid, snapshot[pid][2], force)
        if not force:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                process.poll()
                if not owned_processes(process_snapshot(), process.pid, known):
                    break
                time.sleep(0.1)
    deadline = time.monotonic() + 5
    while True:
        process.poll()
        owned = owned_processes(process_snapshot(), process.pid, known)
        if not owned:
            process.wait(timeout=max(0.1, deadline-time.monotonic()))
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f'Owned processes did not terminate: {sorted(owned)}')
        time.sleep(0.1)


def supervise(command, report, timeout=10800, max_mib=6144, cancel_file=None):
    if not command or not math.isfinite(timeout) or not math.isfinite(max_mib) or timeout <= 0 or max_mib <= 0:
        raise ValueError('Supply a command and finite positive resource limits')
    report = Path(report)
    report.parent.mkdir(parents=True, exist_ok=True)
    known = {}
    started = time.monotonic()
    peak = 0
    available = available_memory_bytes()
    sampled_at = started
    previous_handlers = {}
    parent_pid = int(os.environ.get('NEUROPAL_PARENT_PID', '0'))
    parent_start = process_snapshot().get(parent_pid, (0,0,None))[2]
    if parent_pid and parent_start is None:
        raise RuntimeError('The owning MATLAB process exited before worker launch')
    cancel_file = Path(cancel_file) if cancel_file is not None else None
    def interrupted(signum, frame):
        raise KeyboardInterrupt('Job canceled')
    with JobLease(' '.join(command[:2])) as lease, report.open('w') as log:
        for sig in (signal.SIGTERM, signal.SIGINT):
            previous_handlers[sig] = signal.signal(sig, interrupted)
        process = None
        try:
            if cancel_file is not None and cancel_file.exists():
                raise CancellationError('Job canceled')
            process = subprocess.Popen(command, env=lease.environment(), start_new_session=os.name != 'nt')
            while True:
                snapshot = process_snapshot()
                owned = owned_processes(snapshot, process.pid, known)
                rss = sum(snapshot[pid][1] for pid in owned)
                peak = max(peak, rss)
                elapsed = time.monotonic()-started
                if time.monotonic()-sampled_at >= 2:
                    available = available_memory_bytes()
                    sampled_at = time.monotonic()
                log.write(json.dumps(dict(elapsed_seconds=elapsed, rss_kib=rss, peak_rss_kib=peak,
                                          system_available_bytes=available,
                                          processes=[dict(pid=pid, ppid=snapshot[pid][0], rss_kib=snapshot[pid][1]) for pid in sorted(owned)]))+'\n')
                log.flush()
                code = process.poll()
                if code is not None:
                    return code
                if cancel_file is not None and cancel_file.exists():
                    raise CancellationError('Job canceled')
                if parent_pid and snapshot.get(parent_pid, (0,0,None))[2] != parent_start:
                    raise RuntimeError('The owning MATLAB process exited')
                if elapsed > timeout:
                    raise TimeoutError(f'Job exceeded {timeout:g} seconds')
                if rss > max_mib*1024:
                    raise MemoryError(f'Job process tree exceeded {max_mib:g} MiB; see {report}')
                if available is not None and available < 512*2**20 and rss > 128*1024:
                    raise MemoryError(f'Machine memory headroom is below 512 MiB; stopping owned job. See {report}')
                time.sleep(0.5)
        finally:
            try:
                if process is not None:
                    stop_processes(process, known)
            finally:
                for sig, handler in previous_handlers.items():
                    signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=10800)
    parser.add_argument('--max-mib', type=float, default=float(os.environ.get('NEUROPAL_MAX_JOB_MIB', '6144')))
    parser.add_argument('--cancel-file', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.timeout <= 0 or args.max_mib <= 0:
        parser.error('Supply a command and positive timeout/memory limits')
    try:
        return supervise(command, args.report, args.timeout, args.max_mib, args.cancel_file)
    except TimeoutError as error:
        print(str(error), file=sys.stderr)
        return 124
    except MemoryError as error:
        print(str(error), file=sys.stderr)
        return 137
    except (KeyboardInterrupt, CancellationError):
        print('Job canceled', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.exit(main())
