"""Run bounded single-channel smoke cases on Bedant's supplied recording."""
import argparse
import json
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import reference_video
import moe_inference


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',required=True)
    parser.add_argument('--bundle',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    info=reference_video.source_info(args.source)
    reports=[]
    for frame,channel,backend in [(219,0,'moe'),(1630,0,'moe'),(26,1,'spotiflow')]:
        output=args.output/f't{frame}-c{channel}-{backend}'
        output.mkdir(parents=True,exist_ok=True)
        raw=reference_video.read_frame(info,frame,channel).transpose(2,3,1,0).astype('float32')
        raw.ravel(order='F').tofile(output/'volume.bin')
        request=dict(bundle=args.bundle,output_dir=str(output),volume_raw=str(output/'volume.bin'),
                     volume_shape_yxzc=list(raw.shape),volume_dtype='float32',scale_um_xyz=[.4,.4,1.5],
                     input_mode='single_channel',backend=backend,dataset_id='unknown',device='cpu',
                     source_metadata=dict(source_id=info['source_id'],frame_index=frame,channel_index=channel,spacing_measured=False))
        (output/'request.json').write_text(json.dumps(request,indent=2))
        moe_inference.run(request,output/'response.json')
        response=json.loads((output/'response.json').read_text())
        points=np.array(response['centroids_yxz']).reshape(-1,3)
        assert np.isfinite(points).all() and np.all(points>=1) and np.all(points <= [info['ny'],info['nx'],info['nz']])
        reports.append(dict(frame_index=frame,channel_index=channel,backend=backend,count=len(points),seconds=response['elapsed_seconds']))
        (args.output/'report.json').write_text(json.dumps(reports,indent=2))
        print(reports[-1],flush=True)


if __name__=='__main__':main()
