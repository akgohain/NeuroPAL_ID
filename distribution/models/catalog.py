"""Model release metadata shared by the app installer and release tooling."""
from pathlib import Path
import hashlib
import json
import re
import urllib.error
import urllib.parse
import urllib.request

API_VERSION = 1
MAX_METADATA = 1024 * 1024
MAX_ASSET = 2 * 1024**3 - 1
REPOSITORY = 'akgohain/NeuroPAL_ID'
CAPABILITIES = {
    'detection_moe': ('moe', 'moe'), 'ensemble': ('moe', 'moe'),
    'anshita_gat': ('gat', 'gat'), 'yolo': (None, 'moe'),
    'recording_io': (None, 'bridge'), 'recommendation': (None, 'bridge'),
    'alignment': (None, 'bridge'), 'activity': (None, 'bridge'),
    'zephir': (None, 'tracking'),
}
HERE = Path(__file__).resolve().parent


class IncompatibleCatalog(ValueError):
    """A valid release intended for another application/runtime adapter."""


def digest(path):
    checksum = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(block)
    return checksum.hexdigest()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', value):
        raise ValueError('Invalid model release/version identifier.')
    return value


def asset_url(repository, tag, filename):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid model repository.')
    identifier(tag)
    if not isinstance(filename, str) or not filename or filename != Path(filename).name or not re.fullmatch(r'[A-Za-z0-9_.-]+', filename):
        raise ValueError('Model asset filenames must be plain filenames.')
    return f'https://github.com/{repository}/releases/download/{tag}/{filename}'


def runtime_definitions(app):
    folder = Path(app) / 'distribution/macos'
    result = {}
    for name in ('moe', 'gat', 'tracking', 'bridge'):
        revision = digest(folder / f'lock-macos-arm64-{name}.txt')
        if name == 'tracking':
            wheel = digest(folder / 'zephir-1.0.4-py3-none-any.whl')
            revision = hashlib.sha256((revision + wheel).encode()).hexdigest()
        result[name] = dict(requirements_sha256=revision, python='3.11', platform='macos-arm64')
    return result


def validate(value, app=None, repository=REPOSITORY):
    if not isinstance(value, dict):
        raise ValueError('Invalid model catalog.')
    if value.get('schema_version') != 1 or value.get('adapter_api') != API_VERSION:
        raise IncompatibleCatalog('This model catalog requires a different application adapter. Update the app first.')
    if value.get('repository') != repository:
        raise ValueError('The model catalog belongs to a different repository.')
    tag = identifier(value.get('release_tag'))
    if not tag.startswith('models-'):
        raise ValueError('A model release tag must start with models-.')
    if not isinstance(value.get('models'), dict) or not isinstance(value.get('runtimes'), dict):
        raise ValueError('The model catalog has no model/runtime definitions.')
    if set(value['models']) != {'moe', 'gat'} or set(value['runtimes']) != {'moe', 'gat', 'tracking', 'bridge'}:
        raise ValueError('The model catalog must define all supported model/runtime components.')
    for name, model in value['models'].items():
        if not isinstance(model, dict) or model.get('id') != name:
            raise ValueError('Unknown model adapter in catalog.')
        identifier(model.get('version'))
        if model.get('url') != asset_url(repository, tag, model.get('file', '')):
            raise ValueError('Model assets must come from their versioned release.')
        if not isinstance(model.get('sha256'), str) or not re.fullmatch('[0-9a-f]{64}', model['sha256']):
            raise ValueError('Each model needs a SHA-256 checksum.')
        for field, maximum in (('bytes', MAX_ASSET), ('unpacked_bytes', 5 * 1024**3)):
            number = model.get(field)
            if type(number) is not int or not 0 < number <= maximum:
                raise ValueError(f'Invalid {field} in model catalog.')
        if not isinstance(model.get('source_commit'), str) or not re.fullmatch('[0-9a-f]{40}', model['source_commit']):
            raise ValueError('Each model needs its original training/source revision.')
    if app is not None:
        expected = runtime_definitions(app)
        for name, runtime in value['runtimes'].items():
            if name not in expected or runtime != expected[name]:
                raise IncompatibleCatalog(f'This catalog needs a different {name} runtime. Update the app first.')
    return value


def load(path, app=None):
    path = Path(path)
    if path.stat().st_size > MAX_METADATA:
        raise ValueError('Model catalog is too large.')
    return validate(json.loads(path.read_text(encoding='utf-8')), app)


def plan(value, capability):
    if capability not in CAPABILITIES:
        raise ValueError('No managed download is supplied for this method. Select an existing installation.')
    model, runtime = CAPABILITIES[capability]
    if runtime not in value['runtimes'] or (model and model not in value['models']):
        raise ValueError('This release does not contain the selected component.')
    packs = [value['models'][model]] if model else []
    return dict(capability=capability, runtime=runtime, models=packs,
                release_tag=value['release_tag'], bytes=sum(p['bytes'] for p in packs))


def metadata(url):
    request = urllib.request.Request(url, headers={
        'User-Agent': 'NeuroPAL-ID-model-manager', 'Accept': 'application/vnd.github+json'})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if urllib.parse.urlsplit(response.url).scheme != 'https':
                raise ValueError('Model metadata requires HTTPS.')
            data = response.read(MAX_METADATA + 1)
    except urllib.error.HTTPError as error:
        if error.code in (403, 429):
            raise RuntimeError('GitHub is limiting downloads. Try later or use a local methods package.') from error
        raise
    if len(data) > MAX_METADATA:
        raise ValueError('Remote model metadata is too large.')
    return data


def latest(app, repository=REPOSITORY):
    """Only published stable model tags participate; app releases are ignored."""
    incompatible = []
    for page in range(1, 4):
        releases = json.loads(metadata(f'https://api.github.com/repos/{repository}/releases?per_page=30&page={page}'))
        if not isinstance(releases, list):
            raise ValueError('Invalid GitHub releases response.')
        for release in releases:
            tag = release.get('tag_name', '')
            if release.get('draft') or release.get('prerelease') or not tag.startswith('models-'):
                continue
            assets = [a for a in release.get('assets', []) if a.get('name') == 'model_catalog.json']
            if len(assets) != 1:
                continue
            asset = assets[0]
            if not 0 < asset.get('size', 0) <= MAX_METADATA or not re.fullmatch('sha256:[0-9a-f]{64}', asset.get('digest') or ''):
                raise ValueError('The published model catalog has no verifiable checksum.')
            url = asset_url(repository, tag, 'model_catalog.json')
            raw = metadata(url)
            if len(raw) != asset['size'] or 'sha256:' + hashlib.sha256(raw).hexdigest() != asset['digest']:
                raise ValueError('The released model catalog failed its checksum.')
            candidate = json.loads(raw)
            try:
                validate(candidate, app, repository)
            except IncompatibleCatalog:
                incompatible.append(tag)
                continue
            if candidate['release_tag'] != tag:
                raise ValueError('The model catalog does not match its release tag.')
            return candidate, raw
        if len(releases) < 30:
            break
    if incompatible:
        raise RuntimeError('Published models require a newer app/runtime adapter. Update the app or keep the current models.')
    raise RuntimeError('No compatible public model release has been published yet. Use a local methods package or existing installation.')
