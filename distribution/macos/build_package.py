#!/usr/bin/env python3
"""Build a methods package from committed app source and verified model ZIPs."""
import argparse
from datetime import datetime, timezone
import hashlib
import tempfile
import json
import re
from pathlib import Path
import shutil
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
# The cluster toolkit is distributed separately from the desktop application.
EXCLUDED_PREFIXES = ('cluster/', 'distribution/models/development/')
REQUIRED_APP_FILES = (
    'visualize_light.mlapp', '+Program/GUIHandling.m',
    '+Program/+GUI/ManualIDController.m', '+Program/+GUI/ManualIDService.m',
    '+Annotations/Catalog.m', '+Annotations/catalog_v1.json',
    '+Annotations/Store.m', '+Annotations/Exchange.m',
    '+Runtime/Configuration.m', '+Runtime/Resolver.m', '+Runtime/Settings.m',
    '+Runtime/Distribution.m', 'distribution/models/catalog.json',
    'distribution/models/model_manager.py', 'distribution/macos/lock-macos-arm64-bridge.txt',
    '+Wrapper/runtime_probe.py',
)
KIT_FILES = (
    'Setup-Mac.command', 'Setup-with-Auto-ID.command', 'Start_NeuroPAL.m',
    'setup_models.py', 'runtime_registry.py', 'check_models.py', 'START_HERE.md',
    'lock-macos-arm64-moe.txt', 'lock-macos-arm64-gat.txt',
    'lock-macos-arm64-tracking.txt', 'zephir-1.0.4-py3-none-any.whl',
    'zephir-wheel-provenance.json', 'METHODS.json',
)


def excluded(name):
    return any(name == prefix.rstrip('/') or name.startswith(prefix)
               for prefix in EXCLUDED_PREFIXES)


def assert_release_source():
    changed = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', 'HEAD'], cwd=REPO)
    untracked = subprocess.check_output(
        ['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=REPO)
    missing = sorted({name for raw in (changed, untracked)
                      for name in raw.decode().split('\0') if name and not excluded(name)})
    if missing:
        raise ValueError('Commit the app and installer changes before packaging, including '
                         'untracked source files:\n' + '\n'.join(missing))
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    tracked = set(subprocess.check_output(
        ['git', 'ls-tree', '-r', '--name-only', revision], cwd=REPO, text=True).splitlines())
    absent = (set(REQUIRED_APP_FILES) | {'distribution/macos/' + name for name in KIT_FILES}) - tracked
    if absent:
        raise ValueError('Required application files are absent from the commit: ' + ', '.join(sorted(absent)))
    return revision


def package_version(value, revision):
    value = value or datetime.now(timezone.utc).strftime('%Y%m%d') + '-' + revision[:12]
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', value):
        raise ValueError('Package version must be a short filename-safe identifier.')
    return value


def source_packs(folder):
    catalog = json.loads((folder / 'catalog.json').read_text())
    if not {'moe', 'gat'} <= catalog.get('packs', {}).keys():
        raise ValueError('The full methods package requires both MoE and GAT model packs.')
    for info in catalog['packs'].values():
        filename = info['file']
        if not filename or filename != Path(filename).name or ':' in filename or '\\' in filename:
            raise ValueError('Unsafe source model pack filename: ' + filename)
        source = folder / filename
        if source.stat().st_size != info['bytes'] or digest(source) != info['sha256']:
            raise ValueError('Invalid source model pack: ' + str(source))
    return catalog


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def seal(folder, output):
    files = sorted(p for p in folder.iterdir() if p.is_file() and p.name not in
                   {'SHA256SUMS', 'setup.log', 'installed_launcher.m'})
    (folder / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in files))
    with tempfile.NamedTemporaryFile(prefix='.seal-', suffix='.zip', dir=output.parent, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
            for p in [*files, folder / 'SHA256SUMS']:
                compression = zipfile.ZIP_STORED if p.suffix == '.zip' else zipfile.ZIP_DEFLATED
                archive.write(p, folder.name + '/' + p.name, compress_type=compression)
        checksum = digest(temporary)
        temporary.replace(output)
        output.with_suffix('.zip.sha256').write_text(f'{checksum}  {output.name}\n')
    finally:
        temporary.unlink(missing_ok=True)


def build(models, output, version=None):
    revision = assert_release_source()
    version = package_version(version, revision)
    catalog = source_packs(models)
    output.mkdir(parents=True, exist_ok=True)
    kit = output / ('NeuroPAL-Methods-macOS-' + version)
    if any(path.exists() for path in (kit, output / (kit.name + '.zip'), output / (kit.name + '.zip.sha256'))):
        raise FileExistsError('Choose an empty output folder; existing kits are not overwritten.')
    kit.mkdir()
    try:
        catalog['app_commit'] = revision
        catalog['package_version'] = version
        catalog['excluded_source_paths'] = list(EXCLUDED_PREFIXES)
        for info in catalog['packs'].values():
            source = models / info['file']
            shutil.copy2(source, kit / source.name)
        for filename in KIT_FILES:
            content = subprocess.check_output(
                ['git', 'show', revision + ':distribution/macos/' + filename], cwd=REPO)
            (kit / filename).write_bytes(content)
        (kit / 'PACKAGE_VERSION').write_text(version + '\n')
        for path in kit.glob('*.command'):
            path.chmod(0o755)
        app_archive = kit / ('NeuroPAL_ID-' + revision[:12] + '.zip')
        with tempfile.TemporaryFile() as payload:
            subprocess.run(['git', 'archive', '--format=zip', '--prefix=NeuroPAL_ID/', revision],
                           cwd=REPO, stdout=payload, check=True)
            payload.seek(0)
            with zipfile.ZipFile(payload) as source, zipfile.ZipFile(
                    app_archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
                sums = []
                for info in source.infolist():
                    name = info.filename.removeprefix('NeuroPAL_ID/')
                    if excluded(name):
                        continue
                    if info.is_dir():
                        archive.writestr(info, b'')
                        continue
                    checksum = hashlib.sha256()
                    with source.open(info) as reader, archive.open(info, 'w') as writer:
                        for block in iter(lambda: reader.read(8 * 1024 * 1024), b''):
                            checksum.update(block)
                            writer.write(block)
                    sums.append(checksum.hexdigest() + '  ' + name + '\n')
                archive.writestr('NeuroPAL_ID/SHA256SUMS', ''.join(sums))
        catalog['methods'] = json.loads((kit / 'METHODS.json').read_text())
        catalog['app_archive'] = dict(file=app_archive.name, bytes=app_archive.stat().st_size,
                                    sha256=digest(app_archive))
        (kit / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
        seal(kit, output / (kit.name + '.zip'))
    except BaseException:
        shutil.rmtree(kit)
        (output / (kit.name + '.zip')).unlink(missing_ok=True)
        (output / (kit.name + '.zip.sha256')).unlink(missing_ok=True)
        raise
    return output / (kit.name + '.zip')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, help='Verified source pack folder with catalog.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', help='Release identifier; defaults to UTC date and source commit')
    parser.add_argument('--seal-only', action='store_true', help='Reseal an existing --version after adding acceptance evidence')
    args = parser.parse_args()
    if args.seal_only:
        if not args.version:
            parser.error('--seal-only requires the original --version')
        version = package_version(args.version, '')
        kit = args.output / ('NeuroPAL-Methods-macOS-' + version)
        if not kit.is_dir():
            raise FileNotFoundError('No completed package folder: ' + str(kit))
        if (kit / 'PACKAGE_VERSION').read_text().strip() != version:
            raise ValueError('Package version does not match the requested kit.')
        path = args.output / (kit.name + '.zip')
        seal(kit, path)
    else:
        if args.models is None:
            parser.error('--models is required when building a package')
        path = build(args.models, args.output, args.version)
    print(path)


if __name__ == '__main__':
    main()
