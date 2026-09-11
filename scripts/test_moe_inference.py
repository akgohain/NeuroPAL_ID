#!/usr/bin/env python3
"""Real-bundle annotation-free preprocessing/routing parity and edge contracts."""
import argparse
import json
from pathlib import Path
import sys

import h5py
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'+Wrapper'))
import moe_inference as moe


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--full',action='store_true')
    args = parser.parse_args()
    source = moe.setup(args.bundle,verify=True)
    examples = json.loads((args.bundle/'configuration/examples.json').read_text())
    reports = []
    for ex in examples:
        animal = ex['animal_id']
        output = args.output/animal
        output.mkdir(parents=True,exist_ok=True)
        # Read only the acquisition array. Never read segmentation/annotation groups.
        with h5py.File(args.bundle/ex['original'],'r') as f:
            acquisitions = [v for v in f['acquisition'].values() if 'data' in v and 'RGBW_channels' in v and len(v['data'].shape)==4]
            assert len(acquisitions)==1
            raw = acquisitions[0]['data'][...][...,ex['rgbw_channels']]
        spacing = np.array(ex['original_spacing_um_xyz'])
        volume = moe.preprocess(raw,spacing,source,ex['dataset_id'])
        expected_input = np.load(args.bundle/ex['input'])
        assert np.array_equal(volume,expected_input), (animal,'preprocessing parity',np.max(abs(volume-expected_input)))
        proposals = {}
        for method,filename in [('spotiflow','spotiflow'),('yolo','yolo'),('nnunet','heatmap3d')]:
            rows = pd.read_csv(args.bundle/f'fixtures/expert_predictions/{filename}.csv')
            proposals[method] = rows[rows.animal_id.eq(animal)].copy()
        replay = moe.route(args.bundle,volume,proposals,animal,ex['dataset_id'],output)
        expected = pd.read_csv(args.bundle/'fixtures/final_predictions/nonlinear_moe.csv')
        expected = expected[expected.animal_id.eq(animal)]
        cols = ['x_um','y_um','z_um','score']
        a = replay.sort_values(cols[:3])[cols].to_numpy()
        b = expected.sort_values(cols[:3])[cols].to_numpy()
        assert a.shape==b.shape and np.allclose(a,b,rtol=0,atol=1e-9), (animal,'routing parity')
        empty = {method:rows.iloc[:0] for method,rows in proposals.items()}
        assert moe.route(args.bundle,volume,empty,animal,'unknown',output).empty
        report = dict(animal=animal,preprocessing='exact',replay_count=len(a),replay_max_error=float(np.max(abs(a-b))))
        if args.full:
            yxzc = raw.transpose(1,0,2,3)
            raw_path = output/'raw.bin'
            yxzc.ravel(order='F').tofile(raw_path)
            request = dict(bundle=str(args.bundle),output_dir=str(output/'full'),volume_raw=str(raw_path),
                           volume_shape_yxzc=list(yxzc.shape),volume_dtype=str(yxzc.dtype),scale_um_xyz=spacing.tolist(),
                           animal_id=animal,dataset_id=ex['dataset_id'],device='cpu')
            (output/'request.json').write_text(json.dumps(request,indent=2))
            moe.run(request,output/'response.json')
            actual = pd.read_csv(output/'full/predictions_processed.csv')
            # Record true cross-device errors without relaxing research tolerances.
            from scipy.optimize import linear_sum_assignment
            from scipy.spatial.distance import cdist
            distances = cdist(actual[cols[:3]],expected[cols[:3]])
            left,right = linear_sum_assignment(distances)
            actual_sorted = actual.sort_values(cols[:3])[cols].to_numpy()
            exact = actual_sorted.shape == b.shape and np.allclose(actual_sorted,b,rtol=0,atol=1e-9)
            report.update(full_parity='passed' if exact else 'not_exact_cross_device', full_count=len(actual),expected_count=len(expected),
                          max_matched_distance_um=float(distances[left,right].max()),
                          max_matched_score_error=float(abs(actual.score.to_numpy()[left]-expected.score.to_numpy()[right]).max()))
            for method,reference in proposals.items():
                expert = pd.read_csv(output/f'full/{method}.csv')
                ds = cdist(expert[cols[:3]],reference[cols[:3]])
                l,r = linear_sum_assignment(ds)
                report[method] = dict(actual_count=len(expert),expected_count=len(reference),max_distance_um=float(ds[l,r].max()),max_score_error=float(abs(expert.score.to_numpy()[l]-reference.score.to_numpy()[r]).max()))
        reports.append(report)
        print(json.dumps(report),flush=True)
        (args.output/'report.json').write_text(json.dumps(reports,indent=2)+'\n')
    print('MOE_PREPROCESSING_AND_REPLAY=PASS; inspect report.json for full cross-device differences',flush=True)

if __name__ == '__main__': main()
