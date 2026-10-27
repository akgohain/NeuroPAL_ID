"""Register a completed installation without shell environment configuration."""
from contextlib import contextmanager
from pathlib import Path
import json
import os
import tempfile


@contextmanager
def locked(path):
    with path.open('a+b') as handle:
        if os.name == 'nt':
            import msvcrt
            handle.seek(0)
            if handle.read(1) == b'':
                handle.write(b'\0')
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.lockf(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            if os.name == 'nt':
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.lockf(handle.fileno(), fcntl.LOCK_UN)


def profiles(configuration):
    def profile(python=''):
        return dict(python=python, bundle='', source='', checkpoint='', weights='', origin='installed package')

    result = {}
    video = configuration.get('NEUROPAL_VIDEO_PYTHON', '')
    if video:
        for capability in ('recording_io', 'recommendation', 'alignment', 'activity', 'zephir'):
            result[capability] = profile(video)
    moe = configuration.get('NEUROPAL_MOE_PYTHON', '')
    if moe:
        result['detection_moe'] = profile(moe)
        result['ensemble'] = profile(moe)
        result['detection_moe']['bundle'] = configuration['NEUROPAL_DETECTION_MOE_BUNDLE']
    yolo = configuration.get('NEUROPAL_YOLO_PYTHON', '')
    if yolo:
        result['yolo'] = profile(yolo)
    gat = configuration.get('NEUROPAL_TRANSFORMER_PYTHON', '')
    if gat:
        result['anshita_gat'] = profile(gat)
        result['anshita_gat'].update(source=configuration['NEUROPAL_GAT_REPO'], checkpoint=configuration['NEUROPAL_GAT_CHECKPOINT'])
    return result


def register(root, registry):
    """Add a discoverable installation, leaving all selected profiles pinned."""
    registry = Path(registry)
    registry.parent.mkdir(parents=True, exist_ok=True)
    with locked(registry.with_suffix(registry.suffix + '.lock')):
        data = json.loads(registry.read_text()) if registry.exists() else dict(schema_version=1, profiles={}, resources={})
        if data.get('schema_version') != 1 or not isinstance(data.get('profiles'), dict):
            raise ValueError('Dependency settings need repair in Models & runtimes; the completed installation is retained.')
        installations = data.setdefault('installations', [])
        root = str(Path(root).resolve())
        if root not in installations:
            installations.append(root)
        fd, temporary = tempfile.mkstemp(prefix='.dependencies-', dir=registry.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(data, stream, indent=2)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, registry)
        finally:
            Path(temporary).unlink(missing_ok=True)
