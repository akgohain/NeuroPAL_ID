#!/usr/bin/env python3
"""Install compatible model releases independently of the MATLAB application."""
from pathlib import Path
import argparse
import json
import os
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import uuid

import catalog
from download import atomic_json, extract, fetch, local_asset, progress

APP = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(APP / 'distribution/macos'))
import setup_models as kit
from runtime_registry import locked, register


def user_root():
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support/NeuroPAL_ID'
    if os.name == 'nt':
        return Path.home() / 'AppData/Local/NeuroPAL_ID'
    return Path.home() / '.local/share/NeuroPAL_ID'


def worker_environment(root):
    environment = os.environ.copy()
    for key in ('PYTHONHOME', 'PYTHONPATH', 'VIRTUAL_ENV', 'CONDA_PREFIX'):
        environment.pop(key, None)
    environment.update(PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1', MPLBACKEND='Agg', CUDA_VISIBLE_DEVICES='-1')
    for key in ('MPLCONFIGDIR', 'YOLO_CONFIG_DIR', 'XDG_CONFIG_HOME'):
        folder = root / 'cache' / key.lower()
        folder.mkdir(parents=True, exist_ok=True)
        environment[key] = str(folder)
    return environment


def execute(command, root, timeout=3600):
    process = subprocess.Popen(list(map(str, command)), env=worker_environment(root), start_new_session=True)
    try:
        status = process.wait(timeout=timeout)
        if status:
            raise RuntimeError('Component validation/setup failed. See the installation log; existing selections were kept.')
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


def existing_runtime(name, definition, root, registry):
    signature = definition['requirements_sha256']
    candidates = [root]
    try:
        saved = json.loads(registry.read_text(encoding='utf-8'))
        candidates.extend(Path(p) for p in saved.get('installations', [])[:100])
        for profile in saved.get('profiles', {}).values():
            if isinstance(profile, dict) and profile.get('python'):
                folder = Path(profile['python']).parent.parent
                try:
                    marker = json.loads((folder / 'neuropal-runtime.json').read_text())
                    if marker['requirements_sha256'] == signature and (folder / 'bin/python').is_file():
                        return folder / 'bin/python'
                except (OSError, ValueError, KeyError):
                    pass
    except FileNotFoundError:
        pass
    candidates.extend(sorted(root.glob('Methods-*'), reverse=True)[:100])
    for candidate in candidates:
        folder = candidate / 'runtimes' / f'{name}-{signature[:12]}'
        try:
            marker = json.loads((folder / 'neuropal-runtime.json').read_text())
            if marker['requirements_sha256'] == signature and (folder / 'bin/python').is_file():
                return folder / 'bin/python'
        except (OSError, ValueError, KeyError):
            continue
    return None


def runtime(name, definition, root, registry, rebuild=False):
    found = None if rebuild else existing_runtime(name, definition, root, registry)
    if found:
        progress(f'Checking existing {name} Python environment')
        try:
            execute([shutil.which('uv') or 'uv', 'pip', 'check', '--python', found], root)
        except RuntimeError as error:
            raise RuntimeError('The existing runtime needs repair. Enable Rebuild runtime and retry; its current files will be retained.') from error
        return found
    progress(f'Installing isolated {name} Python environment')
    # Reuse the same locked requirements and wheel as the offline package.
    destination = root / 'repairs' / uuid.uuid4().hex if rebuild else root
    return kit.environment(name, destination, process_env=worker_environment(root))


def model_folder(asset, archive, root, app):
    target = root / 'models' / f'{asset["id"]}-{asset["version"]}-{asset["sha256"][:12]}'
    if target.exists():
        try:
            kit.verify(target)
            marker = json.loads((target / 'installed-model.json').read_text())
            manifest_ok = asset['id'] != 'moe' or marker.get('adapter_sha256') == catalog.digest(target / 'method_bundle.json')
            if marker['sha256'] == asset['sha256'] and manifest_ok:
                return target
        except (OSError, ValueError, KeyError):
            pass
        # A repair gets a new path; running jobs may still hold the old one.
        target = target.with_name(target.name + '-repair-' + uuid.uuid4().hex[:8])
    target.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.model-stage-', dir=target.parent))
    try:
        progress(f'Extracting and checking {asset["id"]} {asset["version"]}')
        extract(archive, stage, asset['unpacked_bytes'])
        kit.verify(stage)
        if asset['id'] == 'moe':
            # The adapter manifest contains bundle-relative paths, never Python paths.
            execute([sys.executable, app / 'scripts/install_moe_bundle.py', stage], root)
        marker = dict(asset)
        if asset['id'] == 'moe':
            marker['adapter_sha256'] = catalog.digest(stage / 'method_bundle.json')
        atomic_json(stage / 'installed-model.json', marker)
        stage.rename(target)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return target


def make_profiles(capability, python, model, app):
    value = dict(python=str(python), bundle='', source='', checkpoint='', weights='', origin='model release')
    if capability in ('recording_io', 'recommendation', 'alignment', 'activity', 'zephir'):
        keys = ['recording_io', 'recommendation', 'alignment', 'activity']
        if capability == 'zephir':
            keys.append('zephir')
        return {key: dict(value) for key in keys}
    if capability in ('detection_moe', 'ensemble'):
        value['bundle'] = str(model)
        result = {key: dict(value) for key in ('detection_moe', 'ensemble')}
        result['yolo'] = dict(value, bundle='', weights=str(app / 'External_Dependencies/yolo_inf2/best.pt'))
        return result
    elif capability == 'anshita_gat':
        value.update(source=str(model / 'source/GAT-NeuroPAL'), checkpoint=str(model / 'models/gat'))
    elif capability == 'yolo':
        value['weights'] = str(app / 'External_Dependencies/yolo_inf2/best.pt')
    return {capability: value}


def activate(registry, root, profiles, before):
    """Only the explicitly selected capability changes; concurrent edits win."""
    with locked(registry.with_suffix(registry.suffix + '.lock')):
        data = json.loads(registry.read_text(encoding='utf-8'))
        if data.get('schema_version') != 1 or not isinstance(data.get('profiles'), dict):
            raise ValueError('Repair dependency settings before selecting the new installation.')
        if any(data['profiles'].get(key) != before.get(key) for key in profiles):
            return False
        data['profiles'].update(profiles)
        atomic_json(registry, data)
    return True


def install(args):
    if sys.platform != 'darwin' or platform.machine() != 'arm64' or int(platform.mac_ver()[0].split('.')[0]) < 14:
        raise RuntimeError('Managed runtime downloads currently support Apple silicon Macs with macOS 14+. Select existing installations on other platforms.')
    app = Path(args.app).resolve()
    value = catalog.load(args.catalog, app)
    selection = catalog.plan(value, args.capability)
    root = Path(args.root).expanduser().resolve()
    registry = Path(args.registry or root / 'dependencies.json').resolve()
    root.mkdir(parents=True, exist_ok=True)
    registry.parent.mkdir(parents=True, exist_ok=True)
    before = {}
    if registry.exists():
        saved = json.loads(registry.read_text(encoding='utf-8'))
        if saved.get('schema_version') != 1 or not isinstance(saved.get('profiles'), dict):
            raise ValueError('Repair dependency settings before installing models.')
        before = saved['profiles']
    # Serialize stale PID-lock recovery as well as the install itself.
    with locked(root / '.model-install.lock'), kit.install_lock(root):
        for stage in (root / 'models').glob('.model-stage-*'):
            if stage.is_dir() and not stage.is_symlink():
                shutil.rmtree(stage)
        # Leave headroom for package installers, and check again before extraction.
        has_runtime = existing_runtime(selection['runtime'], value['runtimes'][selection['runtime']], root, registry)
        reserve = 3 * 1024**3 if args.rebuild_runtime or not has_runtime else 512 * 1024**2
        needed = sum(p['bytes'] + p['unpacked_bytes'] for p in selection['models']) + reserve
        if shutil.disk_usage(root).free < needed:
            raise RuntimeError('Insufficient space for the model download and extraction. Free space and retry; current models were kept.')
        runtime_name = selection['runtime']
        python = runtime(runtime_name, value['runtimes'][runtime_name], root, registry, args.rebuild_runtime)
        model = None
        for asset in selection['models']:
            directory = Path(args.source_dir) if args.source_dir else app / 'distribution/models/development'
            try:
                archive = local_asset(asset, directory)
            except RuntimeError:
                if args.source_dir:
                    raise
                progress('Development LFS bytes are absent; using the published model release')
                archive = None
            if args.source_dir and archive is None:
                raise FileNotFoundError('The selected local folder does not contain ' + asset['file'])
            if archive is None:
                archive = fetch(asset, root / 'downloads')
            model = model_folder(asset, archive, root, app)
        progress('Validating the selected components on CPU')
        checker = [python, '-u', app / 'distribution/macos/check_models.py']
        component = runtime_name
        if args.capability == 'yolo':
            component = 'yolo'
        if model is None and runtime_name == 'moe' and args.capability != 'yolo':
            raise ValueError('This capability needs its complete model bundle.')
        command = checker + [component, '--app', app]
        if model:
            command += ['--bundle', model]
        supervisor = app / '+Wrapper/resource_control.py'
        report = root / 'logs' / ('models-' + uuid.uuid4().hex + '.resources.jsonl')
        report.parent.mkdir(parents=True, exist_ok=True)
        execute([python, supervisor, '--timeout', '240', '--report', report, '--'] + command, root, timeout=270)
        profiles = make_profiles(args.capability, python, model, app)
        checksum = catalog.digest(args.catalog)
        # Receipts are immutable, including runtime repairs of the same model version.
        receipt_root = root / f'Methods-online-{args.capability}-{checksum[:12]}-{uuid.uuid4().hex[:8]}'
        receipt_root.mkdir(exist_ok=True)
        receipt = dict(schema_version=1, app=str(app), adapter_api=catalog.API_VERSION, automatic_discovery=False,
                       release_tag=value['release_tag'], catalog_sha256=checksum,
                       profiles=profiles, models=selection['models'],
                       validation='Real CPU loads, adapter prerequisites and artifact checksums; not scientific accuracy.')
        atomic_json(receipt_root / 'installation.json', receipt)
        register(receipt_root, registry)
        chosen = {args.capability: profiles[args.capability]}
        selected = activate(registry, receipt_root, chosen, before) if args.activate else False
        progress('Installation validated and selected' if selected else 'Installation validated; existing selections were kept')
        return dict(ok=True, activated=selected, receipt=str(receipt_root), profiles=profiles, release_tag=value['release_tag'])


def interrupted(signum, frame):
    raise InterruptedError('Model setup canceled. Verified downloads and completed components can be reused on retry.')


def watch_parent():
    parent = int(os.environ.get('NEUROPAL_PARENT_PID', '0'))
    if not parent:
        return
    def watch():
        while True:
            try:
                os.kill(parent, 0)
            except ProcessLookupError:
                os.kill(os.getpid(), signal.SIGTERM)
                return
            threading.Event().wait(1)
    threading.Thread(target=watch, daemon=True).start()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'plan', 'check-updates'))
    parser.add_argument('--catalog', type=Path, default=Path(__file__).with_name('catalog.json'))
    parser.add_argument('--capability', default='detection_moe')
    parser.add_argument('--app', type=Path, default=APP)
    parser.add_argument('--root', type=Path, default=user_root())
    parser.add_argument('--registry', type=Path)
    parser.add_argument('--source-dir', type=Path, help='Explicit local model ZIPs; LFS pointers are rejected')
    parser.add_argument('--activate', action='store_true', help='Select the validated installation for the requested capability')
    parser.add_argument('--rebuild-runtime', action='store_true', help='Create a fresh environment without replacing the previous one')
    parser.add_argument('--response', type=Path)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    status = 0
    try:
        watch_parent()
        if args.action == 'install':
            result = install(args)
        elif args.action == 'plan':
            result = catalog.plan(catalog.load(args.catalog, args.app), args.capability)
        else:
            value, raw = catalog.latest(args.app)
            result = dict(ok=True, catalog=value)
    except Exception as error:
        result = dict(ok=False, message=str(error))
        print('SETUP FAILED: ' + str(error), file=sys.stderr, flush=True)
        status = 1
    if args.response:
        atomic_json(args.response, result)
    else:
        print(json.dumps(result), flush=True)
    return status


if __name__ == '__main__':
    raise SystemExit(main())
