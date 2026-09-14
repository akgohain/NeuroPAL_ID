"""Reference IO, coordinate and channel-isolation contracts (small synthetic volumes)."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

import h5py
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import reference_video as bridge


class ReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.data = np.arange(3*3*4*5*9,dtype=np.uint16).reshape(3,3,4,5,9)
        self.meta = dict(shape_t=3,shape_c=3,shape_z=4,shape_y=5,shape_x=9,strain='preserve')
        self.write()

    def tearDown(self):
        self.temp.cleanup()

    def write(self, swapped=False):
        with h5py.File(self.root/'data.h5','w') as f:
            f['data'] = self.data.transpose(0,1,2,4,3) if swapped else self.data
            f['times'] = np.arange(3,dtype=float)*.375
        (self.root/'metadata.json').write_text(json.dumps(self.meta))
        self.info = bridge.source_info(self.root/'data.h5')

    def test_native_and_legacy_axis_order(self):
        for swapped in (False,True):
            self.write(swapped)
            np.testing.assert_array_equal(bridge.read_frame(self.info,1),self.data[1])
            raw = self.root/'frame.bin'
            result = bridge.run(dict(action='frame',source=self.info,frame_index=1,output_raw=str(raw)))
            view = np.fromfile(raw,dtype=result['dtype']).reshape(result['shape_yxzc'],order='F')
            self.assertEqual(view[2,7,3,1],self.data[1,1,3,2,7])
            np.testing.assert_array_equal(bridge.read_frame(self.info,2,0),self.data[2,:1])

    def test_seed_roundtrip_and_source_unchanged(self):
        before = (self.root/'metadata.json').read_bytes()
        rows = [dict(track_id=i,parent_id=0,t=t,x=x,y=y,z=z,confidence=.6,channel=0,provenance='reviewed')
                for i,t,x,y,z in [(9,1,1,1,1),(12,3,9,5,4),(9,2,2.25,3.5,2.75)]]
        saved = bridge.export_seeds(dict(source=self.info,observations=rows,output_dir=str(self.root),provenance={'jobs':[{'fold':0,'channel':0}]}))
        restored = bridge.run(dict(action='import',source=self.info,file=str(Path(saved['directory'])/'annotations.h5')))
        self.assertEqual(restored['provenance']['jobs'][0]['fold'],0)
        imported = bridge.read_seeds(saved['directory'],self.info)
        for a,b in zip(rows,imported):
            for key in a:self.assertEqual(a[key],b[key])
        with h5py.File(Path(saved['directory'])/'annotations.h5') as f:
            self.assertEqual(f['t_idx'][1],2)
            self.assertAlmostEqual(float(f['x'][0]),.5/9)
            self.assertEqual(f['worldline_id'][2],9)
        self.assertEqual(before,(self.root/'metadata.json').read_bytes())
        self.meta['strain']='changed';(self.root/'metadata.json').write_text(json.dumps(self.meta))
        with self.assertRaises(ValueError):bridge.export_seeds(dict(source=self.info,observations=rows,output_dir=str(self.root)))

    def test_tracking_frame_mapping(self):
        rows=[dict(track_id=3,parent_id=0,t=1,x=3.,y=2.,z=2.,confidence=.8,channel=1,provenance='reviewed')]
        stage=self.root/'tracking';stage.mkdir()
        local=dict(self.info,nt=2)
        bridge.write_seed_files(stage,rows,local,{})
        request=dict(action='import',source=self.info,file=str(stage/'annotations.h5'))
        with self.assertRaises(ValueError):bridge.run(request)
        (stage/'source_mapping.json').write_text(json.dumps(dict(source=self.info,frame_start=1,channel=1)))
        result=bridge.run(request)['observations']
        self.assertEqual(result[0]['t'],2)
        self.assertEqual(result[0]['channel'],1)
        self.assertEqual(result[0]['track_id'],3)

    def test_invalid_inputs(self):
        row=dict(track_id=1,t=1,x=1,y=1,z=1,confidence=1)
        for change in (dict(x=0),dict(z=5),dict(t=0),dict(x=float('nan')),dict(track_id=0)):
            with self.assertRaises(ValueError):bridge.validate_observations([dict(row,**change)],self.info)
        with self.assertRaises(ValueError):bridge.validate_observations([row,row],self.info)
        for frame in (-1,3,.5):
            with self.assertRaises(ValueError):bridge.read_frame(self.info,frame)
        self.meta['axis_order']='TCZXY';(self.root/'metadata.json').write_text(json.dumps(self.meta))
        with self.assertRaises(ValueError):bridge.source_info(self.root/'data.h5')


if __name__=='__main__':unittest.main()
