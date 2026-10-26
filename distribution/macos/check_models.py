#!/usr/bin/env python3
"""Check real model loads and bridge imports on CPU before registering paths."""
import argparse
import gc
import json
import os
from pathlib import Path
import subprocess
import sys

os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
os.environ.setdefault('MPLBACKEND', 'Agg')
os.environ.setdefault('OMP_NUM_THREADS', '4')
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('component', choices=['moe', 'gat', 'yolo', 'tracking', 'bridge'])
p.add_argument('--bundle', type=Path)
p.add_argument('--app', type=Path, required=True)
a = p.parse_args()
sys.path.insert(0, str(a.app / '+Wrapper'))
if a.component == 'moe':
    import moe_inference as moe
    source = moe.setup(a.bundle, verify=True)
    from spotiflow.model import Spotiflow
    model = Spotiflow.from_folder(a.bundle / 'models/spotiflow', which='last', map_location='cpu')
    del model
    gc.collect()
    print('PASS: Spotiflow CPU weights', flush=True)
    from ultralytics import YOLO
    model = YOLO(str(a.bundle / 'models/yolo/best.pt')).to('cpu')
    del model
    gc.collect()
    print('PASS: YOLO CPU weights', flush=True)
    import torch
    from methods.nnunet.src.inference import build_nnUNet_model
    model = build_nnUNet_model()
    model.load_state_dict(torch.load(a.bundle / 'models/heatmap3d/model.pth', map_location='cpu', weights_only=True), strict=True)
    del model
    gc.collect()
    print('PASS: heatmap CPU weights', flush=True)
    import joblib
    from scripts.run_detection_moe_image_gate import feature_names
    gate = joblib.load(a.bundle / 'models/appearance_gate/image_gate.joblib')
    assert list(gate.feature_names_in_) == feature_names()
    router = joblib.load(a.bundle / 'models/nonlinear_router/estimators.joblib')
    assert 3 in router and 6 in router
    import numpy as np
    # Exercise preprocessing and its packaged histogram reference without GT.
    toy = np.random.default_rng(0).integers(0, 256, (32, 32, 8, 4), dtype=np.uint8)
    preprocessed = moe.preprocess(toy, np.array([0.4, 0.4, 1.5]), source)
    assert preprocessed.shape == toy.shape and np.isfinite(preprocessed).all()
    print('PASS: fitted gate, routers, feature order, preprocessing', flush=True)

elif a.component == 'yolo':
    import numpy as np
    from ultralytics import YOLO
    model = YOLO(str(a.app / 'External_Dependencies/yolo_inf2/best.pt'))
    result = model.predict(np.zeros((128, 128, 3), dtype=np.uint8), device='cpu', verbose=False)
    assert len(result) == 1
    print('PASS: standalone YOLO CPU forward pass', flush=True)
elif a.component == 'bridge':
    import reference_video
    import reference_nwb
    import reference_recommendation
    import reference_analysis
    from scipy.ndimage import zoom
    from skimage.registration import phase_cross_correlation
    assert 'zephir' not in sys.modules
    print('PASS: recording, recommendation, alignment and activity imports without ZephIR', flush=True)
elif a.component == 'tracking':
    import reference_video
    import main
    import torch
    from zephir.models.zephir import ZephIR
    assert not torch.cuda.is_available()
    print('PASS: video bridge and ZephIR CPU imports', flush=True)
else:
    source = a.bundle / 'source/GAT-NeuroPAL'
    os.chdir(source)
    sys.path.insert(0, str(source))
    import run_app_volume_inference as inference
    args = argparse.Namespace(checkpoint_path=str(a.bundle / 'models/gat'), device='cpu', mc_samples=2,
        uncertainty_threshold=0.05, confidence_threshold=0.5, quality_threshold=0.3)
    predictor, _, _, _ = inference.build_model_and_predictor(args)
    print('PASS: GAT CPU weights, architecture and preprocessing configuration', flush=True)
print('MODEL_CHECK_PASSED=' + a.component, flush=True)
