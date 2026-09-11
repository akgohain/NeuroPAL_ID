#!/usr/bin/env python3
"""Check image and candidate workspace rejection before model execution."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import moe_inference as moe


class LimitTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name)/'volume.bin'
        np.zeros((3,4,2,4),dtype=np.float32).tofile(self.path)
        self.request = dict(volume_raw=str(self.path), volume_shape_yxzc=[3,4,2,4],
                            scale_um_xyz=[0.4,0.4,1.5], volume_dtype='float32')

    def tearDown(self):
        self.directory.cleanup()

    def test_valid_metadata(self):
        shape,spacing,estimate = moe.preflight_request(self.request)
        self.assertEqual(shape,(3,4,2,4))
        np.testing.assert_array_equal(spacing,[0.4,0.4,1.5])
        self.assertGreater(estimate,self.path.stat().st_size)

    def test_dimensions_and_raw_size(self):
        for shape in ([3,4,2,3],[3,4,2.5,4],[3,4,0,4],[3,4,20,4]):
            with self.assertRaises(ValueError):
                moe.preflight_request(dict(self.request,volume_shape_yxzc=shape))

    def test_resampling_limit(self):
        with self.assertRaises(MemoryError):
            moe.preflight_request(dict(self.request,scale_um_xyz=[400,400,1500]))
        with patch.dict(os.environ,{'NEUROPAL_MOE_WORKSPACE_MIB':'1'}):
            with self.assertRaises(MemoryError):
                moe.preflight_request(self.request)


if __name__ == '__main__':
    unittest.main()
