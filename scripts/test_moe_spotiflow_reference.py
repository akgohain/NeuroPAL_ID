#!/usr/bin/env python3
"""Compare app Spotiflow output with the original inference-only CPU runner."""
import argparse
import json
from pathlib import Path
import sys
import numpy as np
import pandas as pd
import torch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'+Wrapper'))
import moe_inference as moe

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--bundle',type=Path,required=True)
    p.add_argument('--validation',type=Path,required=True)
    a=p.parse_args()
    moe.setup(a.bundle)
    torch.set_num_threads(4)
    from autoid_benchmark import spotiflow_detector as reference
    examples=json.loads((a.bundle/'configuration/examples.json').read_text())
    output=a.validation/'original_spotiflow_cpu'
    output.mkdir(exist_ok=True)
    manifest=output/'inputs.csv'
    pd.DataFrame([dict(animal_id=e['animal_id'],source_volume_xyzc_npy=str(a.bundle/e['input']),spacing_um_xyz=json.dumps(e['input_spacing_um_xyz'])) for e in examples]).to_csv(manifest,index=False)
    args=reference.build_parser().parse_args(['predict','--manifest',str(manifest),'--out-dir',str(output),'--run-id','cpu_reference','--model-path',str(a.bundle/'models/spotiflow'),'--which','last','--input-mode','rgbw','--normalizer-mode','per-channel','--prob-thresh','0.02','--device','cpu','--tta-views','identity','flip-x','flip-y','flip-xy','--no-verbose'])
    reference.predict(args)
    rows=pd.read_csv(output/'predictions.csv')
    rows['score']*=rows.tta_support/4
    threshold=json.loads((a.bundle/'provenance/spotiflow.json').read_text())['score_threshold']
    rows=rows[rows.score>=threshold]
    report=[]
    for ex in examples:
     expected=rows[rows.animal_id.eq(ex['animal_id'])]
     actual=pd.read_csv(a.validation/ex['animal_id']/'full/spotiflow.csv')
     cols=['x_um','y_um','z_um','score']
     x=actual.sort_values(cols[:3])[cols].to_numpy()
     y=expected.sort_values(cols[:3])[cols].to_numpy()
     assert x.shape==y.shape and np.allclose(x,y,rtol=0,atol=1e-9),(ex['animal_id'],x.shape,y.shape)
     report.append(dict(animal=ex['animal_id'],count=len(x),max_error=float(np.max(abs(x-y)))))
    (output/'comparison.json').write_text(json.dumps(report,indent=2)+'\n')
    print('ORIGINAL_SPOTIFLOW_CPU_PARITY=PASS',report)

if __name__ == '__main__': main()
