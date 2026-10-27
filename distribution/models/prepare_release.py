#!/usr/bin/env python3
"""Prepare immutable model assets, or upload a reviewed candidate as a draft."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

import catalog
from download import archive_entries, atomic_json, local_asset

APP = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(APP / 'distribution/macos'))
import setup_models as kit


def build(source, output, tag, app=APP, base=None):
    catalog.identifier(tag)
    if not tag.startswith('models-'):
        raise ValueError('Use a models- release tag, independent of the app version.')
    if output.exists():
        raise FileExistsError('Choose a new output directory; model release candidates are never overwritten.')
    raw = json.loads((base or source / 'catalog.json').read_text(encoding='utf-8'))
    packs = raw.get('packs', raw.get('models'))
    if not isinstance(packs, dict) or set(packs) != {'moe', 'gat'}:
        raise ValueError('Supply coherent MoE and GAT source packs and their catalog.')
    output.mkdir(parents=True)
    try:
        models = {}
        for name, info in packs.items():
            filename = info['file']
            url = catalog.asset_url(catalog.REPOSITORY, tag, filename)
            asset = dict(info, url=url, id=name)
            path = local_asset(asset, source)
            if path is None:
                raise FileNotFoundError('Missing model archive: ' + filename)
            with zipfile.ZipFile(path) as package:
                asset['unpacked_bytes'] = sum(p.file_size for p in package.infolist())
                names = package.namelist()
                if 'SHA256SUMS' not in names or any(n.lower().endswith(('.nwb', '.czi', '.nd2', '.h5')) for n in names):
                    raise ValueError('Release models must have checksums and must not contain experimental image files.')
            models[name] = {key: asset[key] for key in ('id', 'file', 'version', 'url', 'bytes', 'sha256', 'unpacked_bytes', 'source_commit')}
            for key in ('selection', 'scope'):
                if key in info:
                    models[name][key] = info[key]
            target = output / filename
            try:
                os.link(path, target)
            except OSError:
                shutil.copy2(path, target)
        value = dict(schema_version=1, adapter_api=catalog.API_VERSION, repository=catalog.REPOSITORY,
                     release_tag=tag, models=models, runtimes=catalog.runtime_definitions(app))
        catalog.validate(value, app)
        atomic_json(output / 'model_catalog.json', value)
        (output / 'RELEASE_NOTES.md').write_text(
            f'Model release {tag}\n\n'
            'CPU model bundles for NeuroPAL ID adapter API 1. Models and app versions are independent.\n\n'
            f'MoE: {models["moe"]["version"]}; source {models["moe"]["source_commit"]}. '
            'This is the coherent fold-00 integration fixture; final production model selection remains unresolved.\n\n'
            f'GAT: {models["gat"]["version"]}; source {models["gat"]["source_commit"]}.\n\n'
            'No experimental images, labels or fitted tracking results are included.\n'
            'Install or update through Tools > Models & runtimes in a compatible app.\n')
        files = sorted(output.iterdir())
        (output / 'SHA256SUMS').write_text(''.join(f'{catalog.digest(p)}  {p.name}\n' for p in files))
        verify(output, app)
        return value
    except BaseException:
        shutil.rmtree(output)
        raise


def verify(folder, app=APP):
    value = catalog.load(folder / 'model_catalog.json', app)
    for asset in value['models'].values():
        path = local_asset(asset, folder)
        if path is None:
            raise FileNotFoundError(asset['file'])
        with zipfile.ZipFile(path) as package:
            entries = archive_entries(package, asset['unpacked_bytes'])
            if any(e.filename.lower().endswith(('.nwb', '.czi', '.nd2', '.h5')) for e in entries):
                raise ValueError('Experimental images cannot be published with models.')
            checked = set()
            for line in package.read('SHA256SUMS').decode('utf-8').splitlines():
                checksum, name = line.split(None, 1)
                h = hashlib.sha256()
                with package.open(name) as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b''):
                        h.update(block)
                if h.hexdigest() != checksum:
                    raise ValueError('Inner model checksum failed: ' + name)
                checked.add(name)
            # Historical packs added distribution metadata after sealing model files.
            # The archive checksum covers this metadata and the checksum manifest.
            if checked != {e.filename for e in entries if not e.is_dir()} - {'SHA256SUMS', 'distribution.json'}:
                raise ValueError('Every model file must be covered by its checksum manifest.')
    kit.verify(folder)
    return value


def release_record(repository, tag):
    # A draft without a published Git tag cannot be fetched through releases/tags.
    url = subprocess.check_output(['gh', 'release', 'view', tag, '--repo', repository,
                                   '--json', 'apiUrl', '--jq', '.apiUrl'], text=True).strip()
    prefix = f'https://api.github.com/repos/{repository}/releases/'
    if not url.startswith(prefix) or not re.fullmatch(r'\d+', url[len(prefix):]):
        raise ValueError('GitHub returned an unexpected release API location.')
    response = json.loads(subprocess.check_output(['gh', 'api', url], text=True))
    if response.get('tag_name') != tag:
        raise ValueError('GitHub returned a different model release.')
    return response


def stage_draft(folder, app=APP):
    value = verify(folder, app)
    repository = value['repository']
    tag = value['release_tag']
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=app, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=app, text=True).strip():
        raise ValueError('Commit the reviewed release tooling/catalog before staging a draft.')
    subprocess.run(['gh', 'api', f'repos/{repository}/commits/{revision}', '--silent'], check=True)
    # Refuse to reuse a tag/release; replacing a published model changes its meaning.
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', repository], capture_output=True)
    if existing.returncode == 0:
        raise ValueError('This model release already exists. Use a new version; assets are never clobbered.')
    if b'release not found' not in existing.stderr.lower():
        raise RuntimeError('Could not establish that this release is absent. Check GitHub access before retrying.')
    tag_check = subprocess.run(['gh', 'api', f'repos/{repository}/git/ref/tags/{tag}'], capture_output=True)
    if tag_check.returncode == 0 or b'HTTP 404' not in tag_check.stderr:
        raise ValueError('This tag exists or could not be checked. Choose a new model tag.')
    command = ['gh', 'release', 'create', tag, '--repo', repository, '--target', revision, '--draft',
               '--title', tag, '--notes-file', str(folder / 'RELEASE_NOTES.md')]
    command += [str(folder / a['file']) for a in value['models'].values()]
    command += [str(folder / 'model_catalog.json'), str(folder / 'SHA256SUMS')]
    subprocess.run(command, check=True)
    response = release_record(repository, tag)
    remote = {a['name']: a for a in response['assets']}
    for path in [*(folder / a['file'] for a in value['models'].values()), folder / 'model_catalog.json', folder / 'SHA256SUMS']:
        asset = remote.get(path.name, {})
        if asset.get('state') != 'uploaded' or asset.get('digest') != 'sha256:' + catalog.digest(path):
            raise RuntimeError('The draft upload failed verification. Leave it unpublished and inspect its assets.')
    if not response['draft']:
        raise RuntimeError('Expected an unpublished draft.')
    print(response['html_url'], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'verify', 'stage-draft'))
    parser.add_argument('--source-packs', type=Path)
    parser.add_argument('--source-catalog', type=Path, help='Catalog accompanying development LFS assets')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tag')
    args = parser.parse_args()
    if args.action == 'prepare':
        if not args.source_packs or not args.tag:
            parser.error('prepare needs --source-packs and --tag')
        build(args.source_packs, args.output, args.tag, base=args.source_catalog)
    elif args.action == 'verify':
        verify(args.output)
    else:
        stage_draft(args.output)


if __name__ == '__main__':
    main()
