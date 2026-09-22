"""Native NWB frame ordering, calibration and named output contracts."""
import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest
import h5py
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import reference_video as video
import reference_analysis as analysis


class NWBTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.path=self.root/'paired.nwb'
        self.raw=np.arange(4*11*9*3*2,dtype=np.uint16).reshape(4,11,9,3,2)+10
        with h5py.File(self.path,'w') as f:
            series=f.create_group('acquisition/CalciumImageSeries');series.attrs['neurodata_type']='MultiChannelVolumeSeries'
            series.create_dataset('data',data=self.raw,chunks=(1,11,9,3,1),compression='gzip')
            grid=series.create_dataset('imaging_volume/grid_spacing',data=[.4,.6,1.5]);grid.attrs['unit']='micrometer'
            start=series.create_dataset('starting_time',data=5.);start.attrs['rate']=2.
            ref=f.create_group('acquisition/NeuroPALImageRaw');ref.attrs['neurodata_type']='MultiChannelVolume'
            ref['data']=np.zeros((4,3,22,18),np.uint16);ref['RGBW_channels']=[0,1,2,3]
            grid=ref.create_dataset('imaging_volume/grid_spacing',data=[.2,.3,1.5]);grid.attrs['unit']='micrometer'
        self.info=video.source_info(self.path)

    def tearDown(self):self.temp.cleanup()

    def test_native_frames_and_time(self):
        self.assertEqual((self.info['nt'],self.info['nc'],self.info['nz'],self.info['ny'],self.info['nx']),(4,2,3,9,11))
        self.assertEqual(self.info['neuropal']['dimensions_xyzc'],[22,18,3,4])
        for frame in (0,2,3):
            np.testing.assert_array_equal(video.read_frame(self.info,frame),self.raw[frame].transpose(3,2,1,0))
            np.testing.assert_array_equal(video.read_frame(self.info,frame,1),self.raw[frame,:,:,:,1:2].transpose(3,2,1,0))
        with h5py.File(self.path,'r') as f:np.testing.assert_array_equal(video.frame_times(f,self.info,1,3),[5.5,6,6.5])
        self.assertEqual(self.info['spacing_um_xyz'],[.4,.6,1.5])

    def test_named_activity_and_roundtrip(self):
        rows=[dict(track_id=8,t=t,x=5.,y=4.,z=2.,confidence=.9,channel=0,name='AVAL',
                   identity_source='auto-id',identity_confidence=.8,provenance='reviewed') for t in range(1,5)]
        result=analysis.activity(dict(source=self.info,observations=rows,frame_range=[0,3],output_dir=str(self.root),
            options=dict(radius_xyz=[1,1,.5],background=False)))
        directory=Path(result['directory'])
        with h5py.File(directory/'activity.h5') as f:
            self.assertEqual(f['neuron_name'].asstr()[0],'AVAL')
            np.testing.assert_array_equal(f['source_time'][:],[5,5.5,6,6.5])
        with (directory/'activity.csv').open() as f:self.assertEqual(next(csv.DictReader(f))['neuron_name'],'AVAL')
        seeds=video.export_seeds(dict(source=self.info,observations=rows,output_dir=str(self.root),provenance={}))
        restored=video.read_seeds(seeds['directory'],self.info)
        self.assertEqual(restored[0]['name'],'AVAL');self.assertEqual(restored[0]['identity_source'],'auto-id')
        self.assertEqual(restored[0]['identity_confidence'],.8)
        analysis.update_activity_names(directory,[dict(r,name='AVAR',identity_source='reviewed',identity_confidence=1) for r in rows])
        with h5py.File(directory/'activity.h5') as f:
            self.assertEqual(f['neuron_name'].asstr()[0],'AVAR')
            self.assertEqual(f['identity_source'].asstr()[0],'reviewed')
        with (directory/'activity.csv').open() as f:self.assertEqual(next(csv.DictReader(f))['neuron_name'],'AVAR')

    def test_alignment_uses_images_and_checks_bounds(self):
        from reference_nwb import align_reference
        random=np.random.default_rng(7)
        fixed=random.integers(10,1000,size=(3,9,11),dtype=np.uint16)
        with h5py.File(self.path,'r+') as f:
            f['acquisition/CalciumImageSeries/data'][0,:,:,:,0]=fixed.transpose(2,1,0)
            moving=np.repeat(np.repeat(fixed,2,axis=1),2,axis=2)
            f['acquisition/NeuroPALImageRaw/data'][0]=moving.transpose(0,2,1)
        info=video.source_info(self.path)
        request=dict(source=info,frame_index=0,channel=0,reference_channel=0,scale_mode='extent')
        aligned=align_reference(request)
        self.assertGreater(aligned['correlation'],.9)
        np.testing.assert_allclose(aligned['scale_xyz'],[10/21,8/17,1])
        with self.assertRaises(ValueError):align_reference(dict(request,reference_channel=-1))
        with self.assertRaisesRegex(ValueError,'no signal'):align_reference(dict(request,reference_channel=1))
        with self.assertRaises(ValueError):align_reference(dict(request,scale_mode='unknown'))

    def test_invalid_names_are_rejected(self):
        row=dict(track_id=1,t=1,x=2,y=2,z=2,confidence=1)
        for change in (dict(name='x'*65),dict(name=['AVAL']),dict(identity_confidence=float('nan'))):
            with self.assertRaises(ValueError):video.validate_observations([dict(row,**change)],self.info)
        name='α'*64
        exported=video.export_seeds(dict(source=self.info,observations=[dict(row,name=name)],output_dir=str(self.root),provenance={}))
        self.assertEqual(video.read_seeds(exported['directory'],self.info)[0]['name'],name)

    def test_changed_source(self):
        previous=self.info['source_id']
        with h5py.File(self.path,'r+') as f:f['acquisition/CalciumImageSeries/starting_time'].attrs['rate']=3.
        self.assertNotEqual(video.source_info(self.path)['source_id'],previous)
        with self.assertRaises(ValueError):analysis.verify_source(self.info)


if __name__=='__main__':unittest.main()
