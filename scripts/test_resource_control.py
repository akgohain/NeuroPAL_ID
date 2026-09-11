#!/usr/bin/env python3
"""Exercise job admission and descendant cleanup without model imports."""
import argparse
import ast
from contextlib import redirect_stderr
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

WRAPPER = Path(__file__).resolve().parents[1] / '+Wrapper'
sys.path.insert(0, str(WRAPPER))
import resource_control as resources


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.environment = patch.dict(os.environ, {'NEUROPAL_JOB_LOCK': str(self.root/'lock'), 'NEUROPAL_JOB_TOKEN': ''})
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.directory.cleanup()

    def child(self, env):
        code = f"import sys; sys.path.insert(0,{str(WRAPPER)!r}); from resource_control import JobLease; JobLease('child').__enter__()"
        return subprocess.run([sys.executable, '-c', code], env=env, capture_output=True)

    def test_exclusive_and_delegated_lease(self):
        with resources.JobLease('parent') as lease:
            owner = json.loads(resources.owner_path(resources.lock_path()).read_text())
            self.assertEqual(owner['token'], lease.token)
            self.assertEqual(owner['start'], resources.process_snapshot()[os.getpid()][2])
            lease.file.seek(0)
            self.assertNotIn(lease.token.encode(), lease.file.read())
            self.assertNotEqual(self.child(os.environ.copy()).returncode, 0)
            self.assertEqual(self.child(lease.environment()).returncode, 0)
            self.assertTrue(resources.owner_path(resources.lock_path()).exists())
            with self.assertRaises(RuntimeError):
                with resources.JobLease('duplicate'):
                    pass
        self.assertEqual(self.child(os.environ.copy()).returncode, 0)

    def test_released_lease_revokes_inherited_token(self):
        with resources.JobLease('first') as first:
            token = first.token
            environment = first.environment()
        self.assertFalse(resources.owner_path(resources.lock_path()).exists())
        with patch.dict(os.environ, environment):
            with resources.JobLease('next') as next_lease:
                self.assertNotEqual(next_lease.token, token)
                self.assertIsNotNone(next_lease.file)

    def test_direct_moe_subcommands_respect_job_admission(self):
        # Execute only CLI dispatch; do not import models or image libraries.
        source = ast.parse((WRAPPER/'moe_inference.py').read_text())
        main = next(node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == 'main')
        namespace = {'argparse': argparse, 'Path': Path, 'json': json,
                     'signal': SimpleNamespace(SIGTERM=15, signal=lambda *args: None),
                     'JobLease': resources.JobLease, 'prepare': Mock(), 'setup': Mock()}
        exec(compile(ast.Module(body=[main], type_ignores=[]), '<moe-cli>', 'exec'), namespace)
        request = self.root/'request.json'
        request.write_text('{}')
        commands = [['prepare', '--request', str(request)],
                    ['expert', '--bundle', str(self.root), '--volume', 'unused.npy',
                     '--output', str(self.root), '--animal', 'fixture', '--method', 'spotiflow']]
        with resources.JobLease('existing'):
            for command in commands:
                with patch.object(sys, 'argv', ['moe_inference.py', *command]):
                    with self.assertRaisesRegex(RuntimeError, 'Another NeuroPAL heavy job'):
                        namespace['main']()
        namespace['prepare'].assert_not_called()
        namespace['setup'].assert_not_called()
        with patch.object(sys, 'argv', ['moe_inference.py', *commands[0]]):
            namespace['main']()
        namespace['prepare'].assert_called_once_with({})

    def test_inherited_owner_uses_identity_without_signals(self):
        token = 'inherited-test-token'
        owner = {'pid': 12345, 'token': token}
        snapshot = {12345: (1, 64, 'owner-start'), os.getpid(): (1, 64, 'self-start')}
        with patch.dict(os.environ, {'NEUROPAL_JOB_TOKEN': token}), \
                patch.object(resources, 'process_snapshot', return_value=snapshot), \
                patch.object(resources.os, 'kill', side_effect=AssertionError('Liveness probe sent a signal')):
            for start in (None, 'owner-start'):
                if start is not None:
                    owner['start'] = start
                resources.owner_path(resources.lock_path()).write_text(json.dumps(owner))
                with resources.JobLease('inherited') as lease:
                    self.assertEqual(lease.token, token)
                    self.assertIsNone(lease.file)

    def test_stale_owner_cannot_delegate_to_reused_or_missing_pid(self):
        token = 'stale-test-token'
        for owner_entry in (None, (1, 64, 'replacement-start')):
            snapshot = {os.getpid(): (1, 64, 'self-start')}
            if owner_entry is not None:
                snapshot[12345] = owner_entry
            resources.owner_path(resources.lock_path()).write_text(json.dumps(
                {'pid': 12345, 'start': 'original-start', 'token': token}))
            with patch.dict(os.environ, {'NEUROPAL_JOB_TOKEN': token}), \
                    patch.object(resources, 'process_snapshot', return_value=snapshot), \
                    patch.object(resources.os, 'kill', side_effect=AssertionError('Liveness probe sent a signal')):
                with resources.JobLease('replacement') as lease:
                    self.assertNotEqual(lease.token, token)
                    self.assertIsNotNone(lease.file)

    def test_reused_root_is_not_owned(self):
        known = {123: 'original', 456: 'retained-child'}
        snapshot = {123: (1, 64, 'replacement'), 789: (123, 64, 'unrelated-child'),
                    456: (1, 64, 'retained-child'), 999: (456, 64, 'owned-grandchild')}
        self.assertEqual(resources.owned_processes(snapshot, 123, known), {456, 999})
        self.assertEqual(known[123], 'original')

    def test_windows_snapshot_handles_inaccessible_attributes(self):
        class PsutilError(Exception):
            pass
        rows = [dict(pid=1, ppid=None, memory_info=None, create_time=None),
                dict(pid=2, ppid=1, memory_info=None, create_time=20.0),
                dict(pid=3, ppid=2, memory_info=SimpleNamespace(rss=4096), create_time=30.0)]
        fake = SimpleNamespace(process_iter=lambda attrs: [SimpleNamespace(info=row) for row in rows],
                               NoSuchProcess=PsutilError, AccessDenied=PsutilError)
        with patch.dict(sys.modules, {'psutil': fake}), patch.object(resources.os, 'name', 'nt'):
            self.assertEqual(resources.process_snapshot(), {2: (1, 0, '20.0'), 3: (2, 4, '30.0')})

    def test_windows_signal_handles_exit_race_and_checks_identity(self):
        class PsutilError(Exception):
            pass
        child = Mock()
        child.create_time.return_value = 20.0
        fake = SimpleNamespace(Process=Mock(side_effect=[PsutilError(), child, child, child]),
                               NoSuchProcess=PsutilError, AccessDenied=PsutilError)
        with patch.dict(sys.modules, {'psutil': fake}), patch.object(resources.os, 'name', 'nt'):
            resources.signal_owned_process(1, '10.0', False)
            resources.signal_owned_process(2, 'old-identity', True)
            child.kill.assert_not_called()
            resources.signal_owned_process(2, '20.0', False)
            resources.signal_owned_process(2, '20.0', True)
        child.terminate.assert_called_once()
        child.kill.assert_called_once()

    def test_posix_snapshot_excludes_zombies(self):
        output = '123 1 0 Z Fri Sep 11 10:00:00 2026\n456 1 64 S Fri Sep 11 11:00:00 2026\n'
        with patch.object(resources.os, 'name', 'posix'), \
                patch.object(resources.subprocess, 'check_output', return_value=output):
            self.assertEqual(resources.process_snapshot(), {456: (1, 64, 'Fri Sep 11 11:00:00 2026')})

    def test_missing_parent_prevents_launch(self):
        with patch.dict(os.environ, {'NEUROPAL_PARENT_PID': '12345'}), \
                patch.object(resources, 'process_snapshot', return_value={}), \
                patch.object(resources, 'available_memory_bytes', return_value=2**30), \
                patch.object(resources.subprocess, 'Popen') as launch:
            with self.assertRaisesRegex(RuntimeError, 'before worker launch'):
                resources.supervise(['unused'], self.root/'missing-parent.jsonl')
            launch.assert_not_called()

    def test_cleanup_reports_surviving_descendant(self):
        process = Mock(pid=123)
        # Root has exited; its observed child remains after both signals.
        snapshot = {456: (1, 64, 'child-start')}
        with patch.object(resources, 'process_snapshot', return_value=snapshot), \
                patch.object(resources, 'signal_owned_process') as send_signal, \
                patch.object(resources.time, 'monotonic', side_effect=[0, 4, 5, 11]):
            with self.assertRaisesRegex(RuntimeError, r'Owned processes did not terminate: \[456\]'):
                resources.stop_processes(process, {123: 'root-start', 456: 'child-start'})
        self.assertEqual(send_signal.call_count, 2)
        process.wait.assert_not_called()

    def test_cancel_file_prevents_launch(self):
        cancel = self.root/'cancel'
        cancel.touch()
        with patch.object(resources.subprocess, 'Popen') as launch, \
                patch.object(resources, 'process_snapshot', return_value={os.getpid(): (1, 64, 'self-start')}), \
                patch.object(resources, 'available_memory_bytes', return_value=2**30):
            with self.assertRaisesRegex(RuntimeError, 'Job canceled'):
                resources.supervise(['unused'], self.root/'cancel-before.jsonl', cancel_file=cancel)
            launch.assert_not_called()
        self.assertEqual(self.child(os.environ.copy()).returncode, 0)

    def test_cancel_file_stops_running_worker(self):
        cancel = self.root/'cancel'
        code = f"from pathlib import Path; import time; Path({str(cancel)!r}).touch(); time.sleep(30)"
        report = self.root/'cancel-running.jsonl'
        with self.assertRaisesRegex(RuntimeError, 'Job canceled'):
            resources.supervise([sys.executable, '-c', code], report, cancel_file=cancel)
        records = [json.loads(line) for line in report.read_text().splitlines()]
        pids = {process['pid'] for record in records for process in record['processes']}
        self.assertTrue(pids)
        self.assertTrue(pids.isdisjoint(resources.process_snapshot()))
        self.assertEqual(self.child(os.environ.copy()).returncode, 0)

    def test_monitor_and_memory_limit(self):
        report = self.root/'resources.jsonl'
        result = resources.supervise([sys.executable, '-c', 'print("done")'], report)
        self.assertEqual(result, 0)
        self.assertTrue(json.loads(report.read_text().splitlines()[0])['processes'])
        with self.assertRaises(MemoryError):
            resources.supervise([sys.executable, '-c', 'import time; time.sleep(30)'], report, max_mib=0.001)
        self.assertEqual(self.child(os.environ.copy()).returncode, 0)

    @unittest.skipIf(os.name == 'nt', 'POSIX process identity check')
    def test_timeout_stops_grandchild(self):
        marker = self.root/'grandchild.json'
        grandchild = 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'
        code = f"import subprocess,sys,time,json; from pathlib import Path; p=subprocess.Popen([sys.executable,'-c',{grandchild!r}]); Path({str(marker)!r}).write_text(json.dumps(p.pid)); time.sleep(30)"
        before = signal.getsignal(signal.SIGTERM)
        with self.assertRaises(TimeoutError):
            resources.supervise([sys.executable,'-c',code], self.root/'timeout.jsonl', timeout=1.2)
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)
        pid = json.loads(marker.read_text())
        result = subprocess.run(['ps','-p',str(pid),'-o','stat='],capture_output=True,text=True)
        self.assertTrue(result.returncode or result.stdout.strip().startswith('Z'))

    def test_launch_failure_releases_lease(self):
        before = signal.getsignal(signal.SIGTERM)
        with self.assertRaises(FileNotFoundError):
            resources.supervise(['/definitely/missing/program'], self.root/'missing.jsonl')
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)
        self.assertEqual(self.child(os.environ.copy()).returncode, 0)

    def test_cli_maps_resource_exit_codes(self):
        arguments = ['resource_control.py', '--report', str(self.root/'cli.jsonl'), '--', 'unused']
        for exception, expected in ((TimeoutError('timed out'), 124),
                                    (MemoryError('memory limit'), 137),
                                    (KeyboardInterrupt(), 130),
                                    (resources.CancellationError('Job canceled'), 130)):
            with self.subTest(expected=expected), patch.object(sys, 'argv', arguments), \
                    patch.object(resources, 'supervise', side_effect=exception), \
                    redirect_stderr(io.StringIO()) as error_output:
                self.assertEqual(resources.main(), expected)
                self.assertTrue(error_output.getvalue().strip())

    def test_cli_timeout_exits_124(self):
        command = [sys.executable, str(WRAPPER/'resource_control.py'),
                   '--report', str(self.root/'cli-timeout.jsonl'), '--timeout', '0.05', '--',
                   sys.executable, '-c', 'import time; time.sleep(30)']
        result = subprocess.run(command, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn('Job exceeded', result.stderr)
        self.assertFalse(resources.owner_path(resources.lock_path()).exists())

    def test_cli_cancel_file_exits_130(self):
        for before_launch in (True, False):
            with self.subTest(before_launch=before_launch):
                cancel = self.root/f'cancel-{before_launch}'
                if before_launch:
                    cancel.touch()
                    worker = 'raise AssertionError("Canceled worker must not launch")'
                else:
                    worker = f'from pathlib import Path; import time; Path({str(cancel)!r}).touch(); time.sleep(30)'
                command = [sys.executable, str(WRAPPER/'resource_control.py'),
                           '--report', str(self.root/f'cli-cancel-{before_launch}.jsonl'),
                           '--cancel-file', str(cancel), '--', sys.executable, '-c', worker]
                result = subprocess.run(command, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 130, result.stderr)
                self.assertIn('Job canceled', result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertFalse(resources.owner_path(resources.lock_path()).exists())


if __name__ == '__main__':
    unittest.main()
