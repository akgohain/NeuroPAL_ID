#!/usr/bin/env python3
"""Build a shareable Ev kit from committed app source and verified model ZIPs."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


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
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
        for p in [*files, folder / 'SHA256SUMS']:
            compression = zipfile.ZIP_STORED if p.suffix == '.zip' else zipfile.ZIP_DEFLATED
            archive.write(p, folder.name + '/' + p.name, compress_type=compression)
    output.with_suffix('.zip.sha256').write_text(f'{digest(output)}  {output.name}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, required=True, help='Verified source pack folder with catalog.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seal-only', action='store_true', help='Update the completed kit after adding validation evidence')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    name = 'NeuroPAL-Ev-macOS-20260925'
    kit = args.output / name
    if not args.seal_only:
        if subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=REPO):
            raise ValueError('Commit the app and installer changes before packaging.')
        if kit.exists():
            raise FileExistsError('Choose an empty output folder; existing kits are not overwritten.')
        kit.mkdir()
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
        catalog = json.loads((args.models / 'catalog.json').read_text())
        catalog['app_commit'] = revision
        for info in catalog['packs'].values():
            source = args.models / info['file']
            if source.stat().st_size != info['bytes'] or digest(source) != info['sha256']:
                raise ValueError('Invalid source model pack: ' + str(source))
            shutil.copy2(source, kit / source.name)
        for filename in ['Setup-Mac.command', 'Setup-with-Auto-ID.command', 'Start_NeuroPAL.m',
                         'setup_models.py', 'check_models.py', 'START_HERE.md', 'VALIDATION.md',
                         'lock-macos-arm64-moe.txt', 'lock-macos-arm64-gat.txt']:
            shutil.copy2(HERE / filename, kit / filename)
        for path in kit.glob('*.command'):
            path.chmod(0o755)
        payload = subprocess.check_output(['git', 'archive', '--format=zip', '--prefix=NeuroPAL_ID/', revision], cwd=REPO)
        app_archive = kit / ('NeuroPAL_ID-' + revision[:12] + '.zip')
        with zipfile.ZipFile(io.BytesIO(payload)) as source, zipfile.ZipFile(
                app_archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
            sums = []
            for info in source.infolist():
                data = source.read(info.filename)
                archive.writestr(info, data)
                if not info.is_dir():
                    sums.append(hashlib.sha256(data).hexdigest() + '  ' + info.filename.removeprefix('NeuroPAL_ID/') + '\n')
            archive.writestr('NeuroPAL_ID/SHA256SUMS', ''.join(sums))
        catalog['app_archive'] = dict(file=app_archive.name, bytes=app_archive.stat().st_size, sha256=digest(app_archive))
        (kit / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
    seal(kit, args.output / (name + '.zip'))
    print(args.output / (name + '.zip'))


if __name__ == '__main__':
    main()
