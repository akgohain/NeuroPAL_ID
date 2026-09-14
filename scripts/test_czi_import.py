"""Verify CZI admission before decoding and disk-backed conversion parity."""
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import h5py
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '+Wrapper'))
import read_czi


class CziImportTests(unittest.TestCase):
    def test_reject_before_decode(self):
        czi = SimpleNamespace(shape=(3, 25, 2000, 2000), axes='CZYX', dtype=np.uint16)
        with patch.dict(os.environ, {'NEUROPAL_IMAGE_MAX_MIB': '512'}):
            with self.assertRaisesRegex(RuntimeError, 'loading limit'):
                read_czi._check_size(czi)
        czi.shape = (3, 2, 7, 9)
        self.assertEqual(read_czi._check_size(czi), 756)
        czi.axes = 'CTYX'
        with self.assertRaisesRegex(RuntimeError, 'time point'):
            read_czi._check_size(czi)

    def test_conversion_rejects_before_pixels(self):
        reader = Mock()
        reader.shape = (3, 25, 2000, 2000)
        reader.axes = 'CZYX'
        reader.dtype = np.uint16
        factory = Mock()
        factory.__enter__ = Mock(return_value=reader)
        factory.__exit__ = Mock(return_value=False)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'out.h5'
            with patch.object(read_czi, 'CziFile', return_value=factory):
                with patch.dict(os.environ, {'NEUROPAL_IMAGE_MAX_MIB': '0.01'}):
                    with self.assertRaisesRegex(RuntimeError, 'loading limit'):
                        read_czi.convert('fixture', output, Path(directory) / 'out.json')
            reader.asarray.assert_not_called()
            self.assertFalse(output.exists())

    def test_conversion(self):
        source = np.arange(3 * 2 * 7 * 9, dtype=np.uint16).reshape(3, 2, 7, 9)

        class Fixture:
            shape = source.shape
            dtype = source.dtype
            axes = 'CZYX'

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def metadata(self, raw=False):
                return {}

            def asarray(self, out, max_workers):
                assert max_workers == 1
                data = np.memmap(out, dtype=self.dtype, mode='w+', shape=self.shape)
                data[:] = source
                return data

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'out.h5'
            with patch.object(read_czi, 'CziFile', return_value=Fixture()):
                read_czi.convert('fixture', output, Path(directory) / 'out.json')
            with h5py.File(output) as handle:
                np.testing.assert_array_equal(handle['data'][:], source.transpose(3, 2, 1, 0))
            self.assertFalse(Path(str(output) + '.pixels').exists())


if __name__ == '__main__':
    unittest.main()
