"""Representative frames are deterministic, bounded and annotation-free."""
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import h5py
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'+Wrapper'))
from reference_video import source_info
from reference_recommendation import recommend
import reference_video

class Recommendations(unittest.TestCase):
    def test_distinct_poses_and_channel_isolation(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'data.h5'
            data=np.zeros((12,2,3,8,10),dtype=np.uint8)
            data[:6,0,:,1:3,2:4]=100; data[6:,0,:,5:7,7:9]=200
            with h5py.File(path,'w') as f: f['data']=data
            metadata=Path(folder)/'metadata.json'; metadata.write_text(json.dumps({'axis_order':'TCZYX','t_ref_fn12':[1,7]}))
            before=metadata.read_bytes(); info=source_info(path)
            req={'source':info,'channel':0,'count':2,'max_candidates':12}
            result=recommend(req)
            self.assertEqual(result,recommend(req))
            self.assertEqual(len(set(result['frames'])),2)
            self.assertTrue(any(t<6 for t in result['frames']))
            self.assertTrue(any(t>=6 for t in result['frames']))
            self.assertEqual(before,metadata.read_bytes())
            with self.assertRaisesRegex(ValueError,'no positive signal'): recommend(dict(req,channel=1))
            for overrides in ({'channel':2},{'count':0},{'max_candidates':513},{'count':1.5},
                              {'count':None},{'channel':'0'},{'count':True},{'max_candidates':[3]}):
                with self.assertRaises(ValueError): recommend(dict(req,**overrides))
            metadata.write_text(json.dumps({'axis_order':'TCZYX','changed':True}))
            with self.assertRaisesRegex(ValueError,'changed'): recommend(req)

    def test_transposed_axes_and_sampling_bound(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'data.h5'
            data=np.zeros((100,1,2,7,5),dtype=np.uint8); data[:,:,:,2:4,1:3]=30
            with h5py.File(path,'w') as f: f['data']=data
            (Path(folder)/'metadata.json').write_text(json.dumps({'axis_order':'TCZXY'}))
            result=recommend({'source':source_info(path),'count':5,'max_candidates':8})
            self.assertEqual(result['sampled_frames'],8)
            self.assertEqual(len(set(result['frames'])),5)
            self.assertTrue(all(t in np.linspace(0,99,8,dtype=int) for t in result['frames']))

    def test_thin_neurons_survive_pooling_and_ties_span_time(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'data.h5'
            # These pixels fall between the former stride-sampled thumbnail columns.
            data=np.zeros((10,1,2,65,67),dtype=np.uint8)
            data[:5,0,0,1,1]=100; data[5:,0,0,63,65]=100
            with h5py.File(path,'w') as f: f['data']=data
            metadata=Path(folder)/'metadata.json'; metadata.write_text(json.dumps({'axis_order':'TCZYX'}))
            info=source_info(path)
            result=recommend({'source':info,'count':2,'max_candidates':10})
            self.assertTrue(any(t<5 for t in result['frames']))
            self.assertTrue(any(t>=5 for t in result['frames']))
            data[:]=data[0]
            with h5py.File(path,'r+') as f: f['data'][:]=data
            info=source_info(path)
            result=recommend({'source':info,'count':3,'max_candidates':10})
            self.assertEqual(result['frames'],[4,9,0])
            data[:]=7
            with h5py.File(path,'r+') as f: f['data'][:]=data
            with self.assertRaisesRegex(ValueError,'spatial structure'):
                recommend({'source':source_info(path),'count':2})

    def test_source_change_during_recommendation_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'data.h5'
            data=np.zeros((3,1,2,8,9),dtype=np.uint8); data[:,:,:,2,3]=100
            with h5py.File(path,'w') as f: f['data']=data
            metadata=Path(folder)/'metadata.json'; metadata.write_text(json.dumps({'axis_order':'TCZYX'}))
            info=source_info(path); read=reference_video.frame_from_file
            def changed(*args,**kwargs):
                result=read(*args,**kwargs)
                metadata.write_text(json.dumps({'axis_order':'TCZYX','strain':'changed'}))
                return result
            with patch.object(reference_video,'frame_from_file',changed):
                with self.assertRaisesRegex(ValueError,'changed while recommending'):
                    recommend({'source':info,'count':2})

if __name__=='__main__': unittest.main()
