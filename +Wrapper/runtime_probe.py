"""Validate one app capability without opening or changing an experiment."""
from pathlib import Path
import importlib
import importlib.metadata
import json
import platform
import sys
import traceback


def check(request):
    capability = request['capability']
    app = Path(request['app'])
    profile = request['profile']
    sys.path.insert(0, str(app / '+Wrapper'))
    modules = ['numpy', 'h5py']
    extra = {
        'zephir': ['torch', 'docopt', 'zephir', 'main'],
        'detection_moe': ['torch', 'spotiflow', 'ultralytics', 'joblib', 'sklearn', 'scipy',
                          'dynamic_network_architectures', 'nnunetv2', 'pandas', 'skimage'],
        'spotiflow_supervised': ['torch', 'spotiflow', 'scipy'],
        'yolo': ['torch', 'ultralytics', 'scipy', 'pandas', 'cv2'],
        'cellpose': ['torch', 'cellpose', 'scipy'],
        'anshita_gat': ['torch', 'torch_geometric', 'scipy', 'pandas', 'sklearn', 'pynwb'],
        'czi_reader': ['czifile', 'xmltodict'],
        'legacy_segmentation': ['tensorflow', 'cv2', 'skimage'],
        'ensemble': ['scipy', 'pandas'],
        'activity': ['scipy'],
        'alignment': ['scipy', 'skimage'],
    }
    modules += extra.get(capability, [])
    if sys.version_info < (3, 9):
        raise RuntimeError('Python 3.9 or newer is required; managed model environments use Python 3.11.')
    versions = {}
    for name in modules:
        module = importlib.import_module(name)
        versions[name] = str(getattr(module, '__version__', 'available'))
    if capability == 'detection_moe' and versions['sklearn'] != '1.6.0':
        raise RuntimeError('This MoE gate/router requires scikit-learn 1.6.0.')
    if capability == 'spotiflow_supervised' and importlib.metadata.version('spotiflow') != '0.6.5':
        raise RuntimeError('The frozen Spotiflow adapter requires Spotiflow 0.6.5.')
    if request.get('deep'):
        if capability in ('detection_moe', 'yolo', 'anshita_gat', 'zephir'):
            # Reuse the distribution's real CPU-load checks without installing anything.
            import runpy
            component = {'detection_moe': 'moe', 'anshita_gat': 'gat', 'zephir': 'tracking'}.get(capability, capability)
            sys.argv = ['check_models.py', component, '--app', str(app)]
            if capability == 'detection_moe':
                sys.argv += ['--bundle', profile['bundle']]
            if capability == 'anshita_gat':
                source = Path(profile['source'])
                sys.path.insert(0, str(source))
                import argparse
                inference = importlib.import_module('run_app_volume_inference')
                args = argparse.Namespace(checkpoint_path=profile['checkpoint'], device='cpu', mc_samples=2,
                    uncertainty_threshold=.05, confidence_threshold=.5, quality_threshold=.3)
                inference.build_model_and_predictor(args)
            elif capability == 'yolo':
                from ultralytics import YOLO
                import numpy as np
                YOLO(profile['weights']).predict(np.zeros((64, 64, 3), np.uint8), device='cpu', verbose=False)
            else:
                runpy.run_path(str(app / 'distribution/macos/check_models.py'), run_name='__main__')
        elif capability == 'spotiflow_supervised':
            from spotiflow.model import Spotiflow
            manifest = json.loads((Path(profile['bundle']) / 'method_bundle.json').read_text())
            checkpoint = next(a['path'] for a in manifest['artifacts'] if a['role'] == 'checkpoint')
            Spotiflow.from_folder(Path(profile['bundle']) / checkpoint, which='last', map_location='cpu')
        elif capability == 'cellpose':
            from cellpose import models
            models.CellposeModel(gpu=False, pretrained_model=profile['weights'])
    return dict(ok=True, message='Validation passed.', python=sys.executable, version=platform.python_version(),
                platform=platform.system(), architecture=platform.machine(), packages=versions, deep=bool(request.get('deep')))


def main():
    request = json.loads(Path(sys.argv[1]).read_text())
    response = Path(sys.argv[2])
    try:
        result = check(request)
    except Exception as error:
        result = dict(ok=False, message=f'{type(error).__name__}: {error}')
        traceback.print_exc()
    response.write_text(json.dumps(result))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
