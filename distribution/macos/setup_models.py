#!/usr/bin/env python3
"""Install the methods package and write its MATLAB launcher after validation."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

from runtime_registry import profiles, register

HERE = Path(__file__).resolve().parent


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def inside(root, name):
    path = (root / name).resolve()
    if not name or '\\' in name or ':' in name or not path.is_relative_to(root.resolve()):
        raise ValueError(f'Unsafe package path: {name}')
    return path


def verify(root):
    lines = (root / 'SHA256SUMS').read_text().splitlines()
    if not lines:
        raise ValueError('The package checksum list is empty.')
    for line in lines:
        checksum, name = line.split(None, 1)
        path = inside(root, name)
        if not path.is_file() or digest(path) != checksum:
            raise ValueError(f'Checksum failed: {name}. Re-extract the original package before retrying.')


def extract(archive_path, stage):
    with zipfile.ZipFile(archive_path) as archive:
        names = set()
        for member in archive.infolist():
            path = inside(stage, member.filename)
            if path in names or (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f'Duplicate path or symlink in archive: {member.filename}')
            names.add(path)
        archive.extractall(stage)


def unpack(info, target, checksum_root='.'):
    archive_path = inside(HERE, info['file'])
    if archive_path.stat().st_size != info['bytes'] or digest(archive_path) != info['sha256']:
        raise ValueError(f'Archive checksum failed: {archive_path.name}')
    if target.exists():
        verify(target / checksum_root)
        return target / checksum_root
    target.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.install-', dir=target.parent))
    try:
        extract(archive_path, stage)
        verify(stage / checksum_root)
        stage.rename(target)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return target / checksum_root


def run(command, **kwargs):
    print('Running: ' + ' '.join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), check=True, **kwargs)


@contextmanager
def install_lock(root):
    lock = root / '.setup-lock'
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        # An interrupted installer may leave its PID behind.
        try:
            pid = int(lock.read_text())
            os.kill(pid, 0)
        except ProcessLookupError:
            lock.unlink()
            with install_lock(root):
                yield
            return
        raise RuntimeError('Another setup may be running. Close it before retrying.')
    try:
        with os.fdopen(fd, 'w') as handle:
            handle.write(str(os.getpid()))
        yield
    finally:
        lock.unlink(missing_ok=True)


def environment(name, root):
    uv = shutil.which('uv')
    if not uv:
        raise RuntimeError('Run Setup-Mac.command to prepare the package installer.')
    spec = HERE / ('lock-macos-arm64-' + name + '.txt')
    revision = digest(spec)
    wheel = HERE / 'zephir-1.0.4-py3-none-any.whl'
    if name == 'tracking':
        revision = hashlib.sha256((revision + digest(wheel)).encode()).hexdigest()
    folder = root / 'runtimes' / (name + '-' + revision[:12])
    python = folder / 'bin/python'
    marker = folder / 'neuropal-runtime.json'
    if not marker.is_file():
        # Only unfinished environments owned by this installer are replaced.
        if folder.exists():
            shutil.rmtree(folder)
        run([uv, 'venv', '--managed-python', '--python', '3.11', folder])
        run([uv, 'pip', 'install', '--python', python, '-r', spec])
        if name == 'tracking':
            run([uv, 'pip', 'install', '--python', python, '--no-deps', wheel])
        marker.write_text(json.dumps({'requirements_sha256': revision}) + '\n')
    elif json.loads(marker.read_text())['requirements_sha256'] != revision:
        raise ValueError('The installed runtime does not match this package.')
    run([uv, 'pip', 'check', '--python', python])
    return python


def quote_matlab(value):
    return "'" + str(value).replace("'", "''") + "'"


def atomic_text(path, text):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(text)
    temporary.replace(path)


def launcher_text(app, root, config):
    text = '% Start the packaged app with the verified CPU model environments.\n'
    text += 'addpath(' + quote_matlab(app) + ", '-begin');\ncd(" + quote_matlab(app) + ');\n'
    text += "assert(strcmp(which('visualize_light'), fullfile(pwd, 'visualize_light.mlapp')), "
    text += "'Start this package in a fresh MATLAB session.');\n"
    text += '% Models and runtimes are discovered from the per-user installation registry.\n'
    text += 'app = visualize_light;\n'
    return text


def package_version(catalog):
    version = catalog.get('package_version', 'commit-' + catalog['app_commit'][:12])
    if not isinstance(version, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', version):
        raise ValueError('Invalid package version in catalog.json.')
    marker = HERE / 'PACKAGE_VERSION'
    if marker.exists() and marker.read_text().strip() != version:
        raise ValueError('PACKAGE_VERSION does not match catalog.json. Re-extract the original package.')
    return version


def default_root():
    catalog = json.loads((HERE / 'catalog.json').read_text())
    return Path.home() / 'Library/Application Support/NeuroPAL_ID' / ('Methods-' + package_version(catalog))


def install(args):
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise RuntimeError('This package requires an Apple silicon Mac.')
    if int(platform.mac_ver()[0].split('.')[0]) < 14:
        raise RuntimeError('This package requires macOS 14 or later.')
    verify(HERE)
    catalog = json.loads((HERE / 'catalog.json').read_text())
    version = package_version(catalog)
    root = (args.root or default_root()).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    with install_lock(root):
        # A terminated setup can leave only unpublished extraction stages.
        for parent in (root / 'app', root / 'models'):
            for stage in parent.glob('.install-*'):
                if stage.is_dir() and not stage.is_symlink():
                    shutil.rmtree(stage)
        if shutil.disk_usage(root).free < 2 * 1024**3:
            raise RuntimeError('Less than 2 GiB is free. Allow at least 8 GB for a new installation.')
        app = unpack(catalog['app_archive'], root / 'app' / catalog['app_commit'][:12], 'NeuroPAL_ID')
        moe_info = catalog['packs']['moe']
        moe = unpack(moe_info, root / 'models' / ('moe-' + moe_info['version']))
        moe_python = environment('moe', root)
        run([moe_python, HERE / 'check_models.py', 'moe', '--bundle', moe, '--app', app])
        run([moe_python, HERE / 'check_models.py', 'yolo', '--app', app])
        previous = root / 'installation.json'
        with_gat = args.with_gat or (previous.is_file() and json.loads(previous.read_text()).get('with_gat', False))
        config = {'NEUROPAL_DETECTION_MOE_BUNDLE': str(moe), 'NEUROPAL_MOE_PYTHON': str(moe_python),
                  'NEUROPAL_YOLO_PYTHON': str(moe_python), 'CUDA_VISIBLE_DEVICES': '-1', 'NEUROPAL_TRANSFORMER_PYTHON': '',
                  'NEUROPAL_GAT_REPO': str(root / 'models/gat-not-installed'),
                  'NEUROPAL_GAT_CHECKPOINT': str(root / 'models/gat-not-installed')}
        if with_gat:
            gat_info = catalog['packs']['gat']
            gat = unpack(gat_info, root / 'models' / ('gat-' + gat_info['version']))
            gat_python = environment('gat', root)
            run([gat_python, HERE / 'check_models.py', 'gat', '--bundle', gat, '--app', app])
            config.update(NEUROPAL_TRANSFORMER_PYTHON=str(gat_python),
                          NEUROPAL_GAT_REPO=str(gat / 'source/GAT-NeuroPAL'),
                          NEUROPAL_GAT_CHECKPOINT=str(gat / 'models/gat'))

        tracking_python = environment('tracking', root)
        run([tracking_python, HERE / 'check_models.py', 'tracking', '--app', app])
        config['NEUROPAL_VIDEO_PYTHON'] = str(tracking_python)

        # Register model paths only after the selected components pass their checks.
        run([moe_python, app / 'scripts/install_moe_bundle.py', moe, '--python', moe_python])
        installation = dict(app=str(app), app_commit=catalog['app_commit'], version='methods-' + version,
                            platform=platform.platform(), profiles=profiles(config), with_gat=with_gat,
                            scope='CPU model loading and preprocessing checks; not scientific accuracy validation.')
        atomic_text(previous, json.dumps(installation, indent=2) + '\n')
        registry = Path.home() / 'Library/Application Support/NeuroPAL_ID/dependencies.json'
        register(root, registry)
        text = launcher_text(app, root, config)
        atomic_text(root / 'start_neuropal.m', text)
        atomic_text(HERE / 'installed_launcher.m', 'run(' + quote_matlab(root / 'start_neuropal.m') + ');\n')
        print('\nSETUP COMPLETE\nRun Start_NeuroPAL.m from this folder in a fresh MATLAB session.\n'
              'Installed files: ' + str(root), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, help='Installation folder; defaults to this package version under Application Support')
    parser.add_argument('--with-gat', action='store_true', default=True, help='Install GAT Auto-ID (included by default)')
    install(parser.parse_args())


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print('\nSETUP FAILED: ' + str(error) + '\nKeep setup.log when reporting the failure.', file=sys.stderr)
        sys.exit(1)
