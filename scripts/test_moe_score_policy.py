"""Router threshold and source pixel-center boundary contracts."""
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np
import pandas as pd

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import moe_inference as moe


class ScorePolicyTests(unittest.TestCase):
    def test_threshold_default_and_override(self):
        default=.5506612350559745
        self.assertEqual(moe.score_threshold(default),default)
        for value in (0,.2,1): self.assertEqual(moe.score_threshold(default,value),value)
        for value in (-.1,1.1,float('nan'),float('inf'),True,'0.5',[]):
            with self.assertRaises(ValueError): moe.score_threshold(default,value)

    def test_resampling_edge_preserves_valid_centers(self):
        spacing=np.array([.4,.8,1.5])
        # Source shape is Y=5, X=7, Z=3; only tiny endpoint roundoff is clipped.
        points=np.array([[0,0,0],[6,4,2],[6+1e-8,4,2],[6.2,4,2],[-.1,0,0]])
        rows=pd.DataFrame(points*spacing,columns=['x_um','y_um','z_um'])
        rows['score']=[.9,.8,.7,.6,.5]
        kept,centers,outside=moe.original_centers(rows,[5,7,3,4],spacing)
        self.assertEqual(outside,2)
        np.testing.assert_array_equal(centers,[[1,1,1],[5,7,3],[5,7,3]])
        np.testing.assert_array_equal(kept.score,[.9,.8,.7])
        rows.loc[0,'x_um']=float('nan')
        with self.assertRaises(ValueError): moe.original_centers(rows,[5,7,3,4],spacing)

    def test_empty_centers_and_single_plane(self):
        rows=pd.DataFrame(columns=['x_um','y_um','z_um','score'])
        _,centers,outside=moe.original_centers(rows,[1,1,1,4],[.4,.4,1.5])
        self.assertEqual(centers.shape,(0,3)); self.assertEqual(outside,0)
        rows.loc[0]=[0,0,0,.8]
        _,centers,outside=moe.original_centers(rows,[1,1,1,4],[.4,.4,1.5])
        np.testing.assert_array_equal(centers,[[1,1,1]])

    def test_request_rejects_threshold_for_other_backend(self):
        with tempfile.TemporaryDirectory() as directory:
            raw=Path(directory)/'volume.bin'
            np.ones((2,3,1,4),dtype='float32').tofile(raw)
            request=dict(volume_raw=str(raw),volume_shape_yxzc=[2,3,1,4],scale_um_xyz=[.4,.4,1.5])
            moe.preflight_request(dict(request,score_threshold=0))
            with self.assertRaises(ValueError):
                moe.preflight_request(dict(request,score_threshold=.2,backend='spotiflow'))


if __name__=='__main__': unittest.main()
