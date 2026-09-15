"""Numerical extraction and interrupted tracking contracts on synthetic images."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
import h5py
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import reference_analysis as analysis
from reference_video import source_info


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.data=np.full((7,2,9,19,23),10,dtype=np.uint16)
        self.rows=[dict(track_id=7,t=t+1,x=12.,y=10.,z=5.,confidence=1.,channel=0,provenance='reviewed') for t in range(7)]
        core,_,_=analysis.roi_indices([12,10,5],[2,2,1],(23,19,9))
        for t in range(7):
            self.data[t,0].flat[core]=20+t*10
            self.data[t,1].flat[core]=30
        self.write()

    def tearDown(self): self.temp.cleanup()

    def write(self,legacy=False):
        with h5py.File(self.root/'data.h5','w') as f:
            f['data']=self.data.transpose(0,1,2,4,3) if legacy else self.data
            f['times']=np.arange(7)*.25
        meta=dict(zip(('shape_'+a for a in 'tczyx'),self.data.shape))
        (self.root/'metadata.json').write_text(json.dumps(meta))
        self.info=source_info(self.root/'data.h5')

    def request(self,rows=None):
        return dict(source=self.info,observations=self.rows if rows is None else rows,frame_range=[0,6],output_dir=str(self.root),
                    options=dict(radius_xyz=[2,2,1],baseline_percentile=0,reference_channel=1))

    def test_exact_fluorescence_background_baseline_and_ratio(self):
        for legacy in (False,True):
            self.write(legacy)
            out=analysis.activity(self.request())
            with h5py.File(Path(out['directory'])/'activity.h5') as f:
                np.testing.assert_allclose(f['raw/channel_0'][:,0],20+np.arange(7)*10)
                np.testing.assert_allclose(f['background/channel_0'][:,0],10)
                np.testing.assert_allclose(f['signal'][:,0],10+np.arange(7)*10)
                np.testing.assert_allclose(f['dff'][:,0],np.arange(7))
                np.testing.assert_allclose(f['ratio'][:,0],(10+np.arange(7)*10)/20)
                np.testing.assert_allclose(f['ratio_dff'][:,0],np.arange(7))
                np.testing.assert_allclose(f['source_time'][:],np.arange(7)*.25)
                self.assertEqual(f.attrs['time_units'],'unknown')
                self.assertEqual(f['neuron_id'][0],7)

    def test_missing_excluded_and_zero_baseline_remain_nan(self):
        rows=[dict(r) for r in self.rows if r['t']!=3];rows[0]['excluded']=True
        out=analysis.activity(self.request(rows))
        with h5py.File(Path(out['directory'])/'activity.h5') as f:
            self.assertTrue(np.isnan(f['dff'][0,0]));self.assertTrue(np.isnan(f['dff'][2,0]))
            self.assertTrue(f['quality_flags'][0,0]&analysis.FLAGS['excluded'])
            self.assertTrue(f['quality_flags'][2,0]&analysis.FLAGS['missing'])
        self.data[:]=0;self.write()
        out=analysis.activity(self.request())
        with h5py.File(Path(out['directory'])/'activity.h5') as f:
            self.assertTrue(np.isnan(f['dff'][:]).all())
            self.assertTrue(np.isnan(f['ratio'][:]).all())
            self.assertTrue(np.all(f['quality_flags'][:]&analysis.FLAGS['invalid_baseline']))

    def test_overlap_does_not_double_count_voxels(self):
        rows=self.rows+[dict(r,track_id=8,x=13.) for r in self.rows]
        out=analysis.activity(self.request(rows))
        one,_,_=analysis.roi_indices([12,10,5],[2,2,1],(23,19,9))
        two,_,_=analysis.roi_indices([13,10,5],[2,2,1],(23,19,9))
        with h5py.File(Path(out['directory'])/'activity.h5') as f:
            self.assertEqual(np.sum(f['roi_voxels'][0]),len(set(one)|set(two)))
            self.assertTrue(np.all(f['quality_flags'][0]&analysis.FLAGS['overlap']))
        rows=self.rows+[dict(r,track_id=8) for r in self.rows]
        out=analysis.activity(self.request(rows))
        with h5py.File(Path(out['directory'])/'activity.h5') as f:
            self.assertTrue(np.all(f['roi_voxels'][:,1]==0))
            self.assertTrue(np.isnan(f['dff'][:,1]).all())

    def test_clipping_saturation_and_changed_source(self):
        rows=[dict(r,x=1,y=1,z=1) for r in self.rows]
        self.data[:]=65535;self.write()
        out=analysis.activity(self.request(rows))
        with h5py.File(Path(out['directory'])/'activity.h5') as f:
            self.assertTrue(np.all(f['quality_flags'][:]&analysis.FLAGS['clipped_roi']))
            self.assertTrue(np.all(f['quality_flags'][:]&analysis.FLAGS['saturated']))
        (self.root/'metadata.json').write_text((self.root/'metadata.json').read_text()+' ')
        # Semantic metadata changes, rather than whitespace, invalidate source identity.
        meta=json.loads((self.root/'metadata.json').read_text());meta['strain']='changed'
        (self.root/'metadata.json').write_text(json.dumps(meta))
        with self.assertRaises(ValueError):analysis.activity(self.request())

    def test_full_recording_window_plan_and_invalid_options(self):
        plan=analysis.windows(0,1799,889,50)
        self.assertEqual(set(t for first,last,_ in plan for t in range(first,last+1)),set(range(1800)))
        self.assertTrue(all(last-first+1<=50 and anchor in (first,last) for first,last,anchor in plan))
        for options in (dict(radius_xyz=[0,2,1]),dict(baseline_percentile=101),dict(reference_channel=0),dict(max_step=0)):
            request=self.request();request['options'].update(options)
            with self.assertRaises(ValueError):analysis.activity(request)

    def test_tracking_resume_bidirectional_ids_and_settings(self):
        calls=[]
        def worker(request,directory,number):
            calls.append(number)
            if len(calls)==2: raise RuntimeError('interrupted')
            stage=directory/f'zephir-{number}';stage.mkdir(exist_ok=True)
            (stage/'data.h5').write_text('staged')
            (stage/'.neuropal-window').write_text(self.info['source_id'])
            rows=[dict(self.rows[t],provenance='zephir',confidence=0.) for t in range(request['frame_range'][0],request['frame_range'][1]+1)]
            return dict(directory=str(stage),observations=rows)
        request=dict(source=self.info,observations=[self.rows[3]],frame_range=[0,6],reference_frame=3,channel=1,
                     window_size=3,epochs=1,output_dir=str(self.root))
        with patch.object(analysis,'run_window',worker):
            with self.assertRaises(RuntimeError):analysis.track_sequence(request)
            directory=next(self.root.glob('tracking-*'))
            manifest=json.loads((directory/'tracking.json').read_text())
            self.assertEqual(manifest['completed'],[0]);self.assertEqual(manifest['state'],'failed')
            result=analysis.track_sequence(dict(request,resume_dir=str(directory)))
            self.assertEqual(calls,[0,1,1,2,3])
            self.assertEqual([r['t'] for r in result['observations']],list(range(1,8)))
            self.assertTrue(all(r['channel']==0 and r['track_id']==7 for r in result['observations']))
            for key,value in self.rows[3].items(): self.assertEqual(result['observations'][3][key],value)
            self.assertFalse(list(directory.glob('zephir-*')))
            with self.assertRaises(ValueError):analysis.track_sequence(dict(request,resume_dir=str(directory),epochs=2))
            again=analysis.track_sequence(dict(request,resume_dir=str(directory)))
            self.assertEqual(again['observations'],result['observations'])

if __name__=='__main__':unittest.main()
