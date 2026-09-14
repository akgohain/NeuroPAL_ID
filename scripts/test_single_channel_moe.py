"""Single-channel adapter isolation, validation and RGBW preservation."""
from pathlib import Path
import sys
import tempfile
import unittest
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import moe_inference as moe


class SingleChannelTests(unittest.TestCase):
    def test_channel_isolation(self):
        rng=np.random.default_rng(42)
        frame=rng.integers(0,256,(9,7,4,3),dtype=np.uint8)
        selected=frame[...,:1].copy()
        first=moe.prepare_input(selected,[.4,.4,1.5],'single_channel')
        frame[...,1:]=255
        second=moe.prepare_input(frame[...,:1],[.4,.4,1.5],'single_channel')
        np.testing.assert_array_equal(first,second)
        for c in range(4):np.testing.assert_array_equal(first[...,c],selected[...,0])
        rgbw=rng.random((9,7,4,4)).astype('float32')
        self.assertIs(moe.prepare_input(rgbw,[.4,.4,1.5]),rgbw)

    def test_invalid_channel(self):
        for data in (np.zeros((9,7,4,1)),np.ones((9,7,4,3)),np.full((9,7,4,1),np.nan)):
            with self.assertRaises(ValueError):moe.prepare_input(data,[.4,.4,1.5],'single_channel')
        with tempfile.TemporaryDirectory() as root:
            file=Path(root)/'data.bin';np.ones((9,7,4,1),dtype='float32').tofile(file)
            request=dict(input_mode='single_channel',volume_shape_yxzc=[9,7,4,1],volume_raw=str(file),scale_um_xyz=[.4,.4,1.5])
            shape,_,_=moe.preflight_request(request)
            self.assertEqual(shape,(9,7,4,1))
            request['input_mode']='rgbw'
            with self.assertRaises(ValueError):moe.preflight_request(request)


if __name__=='__main__':unittest.main()
