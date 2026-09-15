#!/usr/bin/env python3
"""Check persistent frame transport, axes, errors and worker shutdown."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '+Wrapper'))
from reference_video import source_info, read_frame
from reference_frame_server import publish


def wait(path):
    deadline = time.monotonic() + 10
    while not path.exists():
        if time.monotonic() > deadline:
            raise TimeoutError(path)
        time.sleep(.005)
    result = json.loads(path.read_text())
    path.unlink()
    return result


class FrameServerTest(unittest.TestCase):
    def exercise(self, order, shape):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = np.arange(np.prod(shape), dtype=np.uint16).reshape(shape)
            stored = data if order == 'TCZYX' else data.transpose(0, 1, 2, 4, 3)
            with h5py.File(root / 'data.h5', 'w') as file:
                file.create_dataset('data', data=stored, compression='lzf')
            (root / 'metadata.json').write_text(json.dumps({'axis_order': order}))
            info = source_info(root / 'data.h5')
            (root / 'source.json').write_text(json.dumps(info))
            process = subprocess.Popen([sys.executable, str(ROOT / '+Wrapper/reference_frame_server.py'),
                                        '--directory', str(root), '--parent', str(os.getpid())])
            try:
                self.assertTrue(wait(root / 'ready.json')['ready'])
                for sequence, frame in enumerate([0, shape[0]-1, 0]):
                    publish(root / 'request.json', {'frame': frame, 'sequence': sequence})
                    self.assertEqual(wait(root / 'response.json'), {'sequence': sequence})
                    pixels = np.fromfile(root / 'frame.bin', dtype=np.uint16)
                    expected = data[frame].transpose(2, 3, 1, 0).ravel(order='F')
                    np.testing.assert_array_equal(pixels, expected)
                publish(root / 'request.json', {'frame': shape[0], 'sequence': 4})
                self.assertIn('outside', wait(root / 'response.json')['error'])
                stat = (root / 'data.h5').stat()
                os.utime(root / 'data.h5', ns=(stat.st_atime_ns, stat.st_mtime_ns + 1000000))
                publish(root / 'request.json', {'frame': 0, 'sequence': 5})
                self.assertIn('changed', wait(root / 'response.json')['error'])
                (root / 'stop').touch()
                self.assertEqual(process.wait(timeout=5), 0)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)

    def test_native(self):
        self.exercise('TCZYX', (4, 3, 2, 5, 7))

    def test_legacy(self):
        self.exercise('TCZXY', (3, 2, 4, 6, 5))

    def test_singleton(self):
        self.exercise('TCZYX', (1, 1, 1, 3, 5))


def make_fixtures(folder, recording):
    root = Path(folder)
    for name, order, shape, compression in [('native', 'TCZYX', (4, 3, 2, 5, 7), None),
                                           ('legacy', 'TCZXY', (3, 2, 4, 6, 5), None),
                                           ('singleton', 'TCZYX', (1, 1, 1, 3, 5), 'lzf')]:
        path = root / name
        path.mkdir(parents=True, exist_ok=True)
        data = np.arange(np.prod(shape), dtype=np.uint16).reshape(shape)
        with h5py.File(path / 'data.h5', 'w') as file:
            file.create_dataset('data', data=data if order == 'TCZYX' else data.transpose(0, 1, 2, 4, 3), compression=compression)
        (path / 'metadata.json').write_text(json.dumps({'axis_order': order}))
        (path / 'source.json').write_text(json.dumps(source_info(path / 'data.h5')))
        data[-1].transpose(2, 3, 1, 0).ravel(order='F').tofile(path / 'expected.bin')
    info = source_info(recording)
    read_frame(info, 399).transpose(2, 3, 1, 0).ravel(order='F').tofile(root / 'bedant-frame400.bin')


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--fixtures':
        make_fixtures(sys.argv[2], sys.argv[3])
    else:
        unittest.main()
