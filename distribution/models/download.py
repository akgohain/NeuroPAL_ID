"""Resumable, content-addressed downloads and bounded model extraction."""
from pathlib import Path
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from catalog import digest


def progress(message):
    print('NEUROPAL_PROGRESS:' + str(message), flush=True)


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != 'https':
            raise ValueError('A model download attempted an insecure redirect.')
        return super().redirect_request(request, response, code, message, headers, newurl)


def fetch(asset, cache, opener=None):
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / (asset['sha256'] + '.zip')
    if target.is_file():
        if target.stat().st_size == asset['bytes'] and digest(target) == asset['sha256']:
            progress('Using verified cached download')
            return target
        target.unlink()
    partial = target.with_suffix('.part')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > asset['bytes']:
        partial.unlink()
        offset = 0
    if offset == asset['bytes']:
        if digest(partial) == asset['sha256']:
            os.replace(partial, target)
            return target
        partial.unlink()
        offset = 0
    if opener is None:
        if urllib.parse.urlsplit(asset['url']).scheme != 'https':
            raise ValueError('Model downloads require HTTPS.')
        opener = urllib.request.build_opener(HTTPSRedirect()).open
    headers = {'User-Agent': 'NeuroPAL-ID-model-manager'}
    if offset:
        headers['Range'] = f'bytes={offset}-'
    request = urllib.request.Request(asset['url'], headers=headers)
    try:
        response = opener(request, timeout=30)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise RuntimeError('This model release is not public yet, or its asset is missing. Use Check updates or a local package.') from error
        if error.code in (403, 429):
            raise RuntimeError('Download limit reached. Try later or select a local methods package.') from error
        raise
    with response:
        status = response.status
        if status == 206:
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response.headers.get('Content-Range', ''))
            if not match or int(match[1]) != offset or int(match[3]) != asset['bytes'] or int(match[2]) >= asset['bytes']:
                raise ValueError('The server returned an invalid download range.')
        elif status == 200:
            offset = 0
        else:
            raise ValueError('Unexpected download response.')
        count = offset
        last = -1
        with partial.open('ab' if offset else 'wb') as stream:
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                if count + len(block) > asset['bytes']:
                    raise ValueError('Download exceeded the size in its model catalog.')
                stream.write(block)
                count += len(block)
                percent = int(100 * count / asset['bytes'])
                if percent != last:
                    progress(f'Downloading {asset["file"]}: {percent}%')
                    last = percent
            stream.flush()
            os.fsync(stream.fileno())
    if count != asset['bytes']:
        raise RuntimeError('Download was interrupted. Retry to resume the partial download.')
    if digest(partial) != asset['sha256']:
        partial.unlink()
        raise ValueError('Model download failed SHA-256 verification. The active installation was kept.')
    os.replace(partial, target)
    return target


def local_asset(asset, directory):
    path = Path(directory) / asset['file']
    if not path.is_file():
        return None
    with path.open('rb') as stream:
        if stream.read(100).startswith(b'version https://git-lfs.github.com/spec'):
            raise RuntimeError('Development model is a Git LFS pointer. Run git lfs pull for distribution/models/development/*.zip, or download the published release.')
    if path.stat().st_size != asset['bytes'] or digest(path) != asset['sha256']:
        raise ValueError('Local development weights do not match this catalog. Rebuild the catalog with the same model bundle.')
    return path


def archive_entries(package, expected_bytes):
    entries = package.infolist()
    if len(entries) > 20000 or sum(p.file_size for p in entries) != expected_bytes:
        raise ValueError('The model archive does not match its declared extraction size.')
    names = set()
    for entry in entries:
        name = entry.filename
        key = name.rstrip('/').casefold()
        if not name or '\\' in name or ':' in name or name.startswith('/') or '..' in Path(name).parts or key in names:
            raise ValueError('Unsafe or duplicate model archive path.')
        if (entry.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError('Model archives cannot contain symbolic links.')
        names.add(key)
    return entries


def extract(archive, stage, expected_bytes):
    stage = Path(stage).resolve()
    with zipfile.ZipFile(archive) as package:
        archive_entries(package, expected_bytes)
        package.extractall(stage)


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
