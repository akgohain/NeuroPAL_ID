#!/usr/bin/env python3
"""Annotation-free, frozen fold-00 MoE inference for the MATLAB volume bridge.

Research functions are imported from the verified bundle; fitting/evaluation
entry points are never invoked. Each neural expert runs in a separate process.
Launch CLI commands through resource_control.py for memory and cancellation monitoring.
"""
from __future__ import annotations
import argparse
import importlib.metadata
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import signal
import sys
import time

import numpy as np
import pandas as pd

from resource_control import JobLease, available_memory_bytes

SPACING = np.array([0.4, 0.4, 1.5])
COLUMNS = ['animal_id','pred_id','x_vox','y_vox','z_vox','x_um','y_um','z_um','score']


def progress(message):
    print('NEUROPAL_PROGRESS:' + message, flush=True)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(8*1024*1024), b''): h.update(block)
    return h.hexdigest()


def setup(bundle, verify=False):
    bundle = Path(bundle).resolve()
    manifest = json.loads((bundle/'manifest.json').read_text())
    if manifest['source_commit'] != '2276e61dedf9671740c1a36fab7d6d976b86de37' or manifest['fold'] != 0:
        raise ValueError('Unsupported model provenance; expected the pinned fold-00 bundle')
    if verify:
        for line in (bundle/'SHA256SUMS').read_text().splitlines():
            expected, name = line.split(None, 1)
            if not name.startswith(('models/', 'configuration/', 'provenance/', 'source/')): continue
            path = (bundle/name).resolve()
            if not path.is_relative_to(bundle) or digest(path) != expected:
                raise ValueError(f'Bundle checksum mismatch: {name}')
        for line in (bundle/'app_support/SHA256SUMS').read_text().splitlines():
            expected, name = line.split(None, 1)
            path = (bundle/'app_support'/name).resolve()
            if not path.is_relative_to(bundle) or digest(path) != expected:
                raise ValueError(f'YOLO source checksum mismatch: {name}')
    source = bundle/'source/GAT-NeuroPAL'
    sys.path[:0] = [str(source), str(source/'reproduction/vendor')]
    os.environ.setdefault('OMP_NUM_THREADS', '4')
    os.environ.setdefault('MPLBACKEND', 'Agg')
    return source


def validate_volume(volume, spacing):
    if volume.ndim != 4 or volume.shape[-1] != 4 or min(volume.shape[:3]) < 1:
        raise ValueError(f'Expected nonempty XYZC RGBW volume; got {volume.shape}')
    if not np.isfinite(volume).all(): raise ValueError('Image contains nonfinite values')
    if np.shape(spacing) != (3,) or not np.isfinite(spacing).all() or np.any(np.asarray(spacing) <= 0):
        raise ValueError('Voxel spacing must contain three finite positive micron values')


def prepare_input(volume_xyzc, spacing, input_mode='rgbw'):
    """Adapt one explicitly selected channel without consuming other channels."""
    volume = np.asarray(volume_xyzc)
    if input_mode == 'single_channel':
        if volume.ndim != 4 or volume.shape[-1] != 1:
            raise ValueError('Single-channel mode requires exactly one selected source channel')
        if not np.isfinite(volume).all() or not np.any(volume > 0):
            raise ValueError('Selected channel has no positive signal or contains nonfinite values')
        volume = np.repeat(volume, 4, axis=-1)
    elif input_mode != 'rgbw':
        raise ValueError('Input mode must be rgbw or single_channel')
    validate_volume(volume, spacing)
    return volume


def preprocess(volume_xyzc, spacing, source, dataset_id='unknown'):
    """Run image-only SM4-SM9. No ROI loading or annotation-guided cropping."""
    from data import preprocessing as pp
    validate_volume(volume_xyzc, spacing)
    pp.REFERENCE_HIST_PATH = str(source/pp.REFERENCE_HIST_PATH)
    volume = volume_xyzc.transpose(3, 2, 1, 0)
    volume = pp.apply_denoise(volume, kernel_xy=pp.KERNEL_XY, kernel_z=pp.KERNEL_Z)
    volume = pp.apply_background_threshold(volume, threshold=pp.BG_THRESHOLD)
    volume = pp.apply_per_channel_data_range_norm(volume, dataset_id)
    volume = pp.apply_background_threshold_percentile(volume, percentile=pp.BG_PERCENTILE)
    volume = pp.apply_histogram_matching(volume)
    volume, _ = pp.apply_zoom(volume, [], tuple(spacing))
    volume = pp.apply_morphological_closing(volume, close_radius_xy=pp.CLOSING_RADIUS_XY, close_radius_z=pp.CLOSING_RADIUS_Z)
    return np.ascontiguousarray(volume.transpose(3, 2, 1, 0), dtype=np.float32)


def stamp(frame, animal, method):
    frame = frame.copy()
    frame['animal_id'] = animal
    frame['pred_id'] = [f'{animal}__{method}_{i:06d}' for i in range(len(frame))]
    return frame


def spotiflow(bundle, volume, animal, device):
    from detection.spotiflow import FrozenSpotiflowPolicy, load_spotiflow_model, detect_volume
    model = load_spotiflow_model(bundle/'models/spotiflow', device=device)
    policy = json.loads((bundle/'provenance/spotiflow.json').read_text())
    frame = detect_volume(volume, tuple(SPACING), model,
                          FrozenSpotiflowPolicy(operating_score_threshold=policy['score_threshold']), device=device)
    return stamp(frame, animal, 'spotiflow')


def heatmap3d(bundle, volume, animal, device, output):
    import torch
    import tifffile
    from skimage.feature import peak_local_max
    from methods.nnunet.src.inference import build_nnUNet_model, sliding_window_inference
    from autoid_benchmark.detection_image_export import _uint16_volume
    torch.set_num_threads(4)
    model = build_nnUNet_model().to(device)
    model.load_state_dict(torch.load(bundle/'models/heatmap3d/model.pth', map_location=device, weights_only=True), strict=True)
    model.eval()
    image = torch.from_numpy(np.ascontiguousarray(_uint16_volume(volume)[..., :3].transpose(3,2,0,1), dtype=np.float32))
    image = torch.clamp(image, 0, 60000)
    deviation = image.std()
    if deviation == 0: return pd.DataFrame(columns=COLUMNS)
    image = (image-image.mean())/deviation
    patch = (32,96,64)
    # Sliding inference also pads small images to valid network dimensions.
    pred = sliding_window_inference(model,image,patch,(16,48,32),torch.device(device))
    heatmap = pred.cpu().numpy()[0]
    extent = float(heatmap.max()-heatmap.min())
    if extent == 0: return pd.DataFrame(columns=COLUMNS)
    quantized = ((heatmap-heatmap.min())/extent*255).astype(np.uint8)
    tifffile.imwrite(output/'heatmap.tiff',quantized)
    heatmap = quantized.astype(np.float32)
    if heatmap.max(initial=0) > 1.5: heatmap /= 255.0
    coords = peak_local_max(heatmap,min_distance=3,threshold_abs=0.3,exclude_border=False)
    scores = heatmap[tuple(coords.T)]
    order = np.argsort(-scores)
    points = coords[order][:,[1,2,0]].astype(float)
    frame = pd.DataFrame(points,columns=['x_vox','y_vox','z_vox'])
    for i,axis in enumerate('xyz'): frame[axis+'_um'] = points[:,i]*SPACING[i]
    frame['score'] = scores[order]
    return stamp(frame,animal,'nnunet')


def run_command(command, log, timeout=3600, env=None):
    with log.open('w') as handle:
        process = subprocess.Popen([str(x) for x in command], stdout=handle,
                                   stderr=subprocess.STDOUT, start_new_session=os.name != 'nt', env=env)
        try:
            code = process.wait(timeout=timeout)
            if code: raise subprocess.CalledProcessError(code, command)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            with log.open('rb') as source_log:
                source_log.seek(max(0, log.stat().st_size-5000))
                tail = source_log.read().decode(errors='replace')
            raise RuntimeError(f'Inference failed; see {log}\n{tail}') from exc
        finally:
            if process.poll() is None:
                if os.name != 'nt': os.killpg(process.pid, signal.SIGTERM)
                else: process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    if os.name != 'nt': os.killpg(process.pid, signal.SIGKILL)
                    else: process.kill()
                    process.wait()


def yolo(bundle, volume_path, animal, device, output):
    from autoid_benchmark.yolo_inf2 import convert_fused_csv
    scripts = bundle/'app_support/yolo_inf2'
    infer = output/'yolo_slices'
    run_command([sys.executable,scripts/'infer_volume_slices_yolo.py','--volume',volume_path,
                 '--weights',bundle/'models/yolo/best.pt','--out_dir',infer,'--conf','0.3','--imgsz','512',
                 '--device',device,'--stretch_slices','--p_lo','0.5','--p_hi','99.5',
                 '--voxel-spacing-um','0.4','0.4','1.5','--scale-bar-um','0'], output/'yolo_infer.log')
    fused = output/'yolo_fused.csv'
    run_command([sys.executable,scripts/'mip_centroids_iou_color_fuse.py','--summary',infer/'predictions_summary.json',
                 '--volume',volume_path,'--out_png',output/'yolo_mip.png','--stretch_mip','--device','cpu',
                 '--fuse-max-dz','1','--iou-min','0.5','--no-color-match','--crop-z-to-summary',
                 '--voxel-spacing-um','0.4','0.4','1.5','--depth-sanity-ratio-cap','2.0','--export_csv',fused],output/'yolo_fuse.log')
    convert_fused_csv(animal,fused,output/'yolo.csv',tuple(SPACING))
    return pd.read_csv(output/'yolo.csv')


def route(bundle, volume, proposals, animal, dataset, output):
    import joblib
    from scripts.run_detection_moe_image_gate import normalize_volume, sample_features, feature_names
    from scripts.experiment_detection_moe_nonlinear import _base_design, add_volume_context
    from scripts.experiment_detection_moe_calibrated_stack import build_candidates, CandidateConfig
    count = sum(len(frame) for frame in proposals.values())
    if not count: return pd.DataFrame(columns=COLUMNS)
    limit = float(os.environ.get('NEUROPAL_ROUTER_MIB', '512')) * 2**20
    estimated = count*count*32 + count*4096
    if not math.isfinite(limit) or limit <= 0 or estimated > limit:
        raise MemoryError(f'Routing {count} proposals requires an estimated {estimated/2**20:.0f} MiB; budget is {limit/2**20:g} MiB')
    if importlib.metadata.version('scikit-learn') != '1.6.0':
        raise RuntimeError('This fitted bundle requires scikit-learn 1.6.0; install requirements-moe.txt')
    gate = joblib.load(bundle/'models/appearance_gate/image_gate.joblib')
    estimators = joblib.load(bundle/'models/nonlinear_router/estimators.joblib')
    ordered = json.loads((bundle/'configuration/ordered_features.json').read_text())
    columns = feature_names()
    if list(gate.feature_names_in_) != columns or columns != ordered['appearance_gate']:
        raise ValueError('Appearance feature order does not match the bundle')
    normalized = normalize_volume(volume)
    scored = {}
    for method, rows in proposals.items():
        rows = rows.copy()
        if len(rows):
            features = pd.DataFrame([sample_features(normalized,np.array([r.x_vox,r.y_vox,r.z_vox]),dataset) for r in rows.itertuples()])
            rows['image_gate_score'] = gate.predict_proba(features[columns])[:,1]
        else: rows['image_gate_score'] = pd.Series(dtype=float)
        rows.to_csv(output/f'{method}_scored.csv',index=False)
        # Preserve the historical CSV float roundtrip before tree routing.
        scored[method] = pd.read_csv(output/f'{method}_scored.csv')
        scored[method]['source_method'] = method
    router_config = json.loads((bundle/'provenance/router.json').read_text())
    association = router_config['association']
    candidates = build_candidates(scored,{animal:dataset},CandidateConfig(association['mode'],association['radius_um'],association['coordinate']))
    context = output/'context.csv'
    pd.DataFrame([dict(animal_id=animal,shape_xyzc=json.dumps(list(volume.shape)),spacing_um_xyz=json.dumps(SPACING.tolist()))]).to_csv(context,index=False)
    candidates = add_volume_context(candidates,context)
    design = _base_design(candidates)
    if list(design.columns) != ordered['router'] or list(estimators[3].feature_names_in_) != list(design.columns):
        raise ValueError('Router feature order does not match the bundle')
    design.to_csv(output/'router_features.csv',index=False)
    candidates.to_csv(output/'candidates.csv',index=False)
    policy = router_config['nonlinear_moe']
    p3 = estimators[3].predict_proba(design)[:,1]
    p6 = np.maximum(p3,estimators[6].predict_proba(design)[:,1])
    score = policy['alpha']*p3+(1-policy['alpha'])*p6
    result = candidates.loc[score >= policy['threshold']].copy()
    result['score'] = score[score >= policy['threshold']]
    return result


def preflight_request(request):
    mode = request.get('input_mode', 'rgbw')
    if mode not in ('rgbw', 'single_channel'): raise ValueError('Unsupported input mode')
    channels = 1 if mode == 'single_channel' else 4
    supplied = request['volume_shape_yxzc']
    if len(supplied) != 4 or any(isinstance(x, bool) or int(x) != x or x < 1 for x in supplied) or supplied[3] != channels:
        raise ValueError('Expected positive integer YXZC dimensions matching the selected input mode')
    shape = tuple(int(x) for x in supplied)
    spacing = np.asarray(request['scale_um_xyz'], dtype=float)
    if spacing.shape != (3,) or not np.isfinite(spacing).all() or np.any(spacing <= 0):
        raise ValueError('Voxel spacing must contain three finite positive micron values')
    dtype = np.dtype(request.get('volume_dtype','float32'))
    if dtype.kind not in 'uif' or dtype.itemsize > 8:
        raise ValueError('Unsupported image dtype')
    raw_bytes = math.prod(shape)*dtype.itemsize
    if Path(request['volume_raw']).stat().st_size != raw_bytes:
        raise ValueError('Raw image file size does not match its dimensions and dtype')
    target = np.array([shape[1],shape[0],shape[2]], dtype=float)*spacing/SPACING
    limit = float(os.environ.get('NEUROPAL_MOE_WORKSPACE_MIB','4096'))*2**20
    if not np.isfinite(target).all() or not math.isfinite(limit) or limit <= 0:
        raise ValueError('Invalid processed dimensions or memory budget')
    processed = math.prod(max(1,math.ceil(x)) for x in target)*4*4
    # Include preprocessing temporaries and a conservative model workspace.
    estimated = raw_bytes*(16 if mode == 'single_channel' else 4) + processed*12 + 1536*2**20
    if estimated > limit:
        raise MemoryError(f'MoE requires an estimated {estimated/2**20:.0f} MiB; workspace budget is {limit/2**20:g} MiB')
    return shape, spacing, estimated


def prepare(request):
    shape, spacing, _ = preflight_request(request)
    source = setup(request['bundle'])
    raw = np.memmap(request['volume_raw'], dtype=request.get('volume_dtype','float32'), mode='r', shape=shape, order='F')
    adapted = prepare_input(raw.transpose(1,0,2,3), spacing, request.get('input_mode','rgbw'))
    volume = preprocess(adapted, spacing, source, request.get('dataset_id','unknown'))
    np.save(Path(request['output_dir'])/'volume.npy', volume)


def run(request, response_path):
    with JobLease('MoE inference') as lease:
        return _run(request, Path(response_path), lease)


def _run(request, response_path, lease):
    bundle = Path(request['bundle']).resolve()
    setup(bundle,verify=True)
    output = Path(request['output_dir']).resolve()
    output.mkdir(parents=True,exist_ok=True)
    response_path.unlink(missing_ok=True)
    started = time.monotonic()
    shape, spacing, estimated = preflight_request(request)
    available = available_memory_bytes()
    if available is not None and estimated + 512*2**20 > available:
        raise MemoryError(f'MoE needs an estimated {estimated/2**20:.0f} MiB plus reserve; current machine headroom is {available/2**20:.0f} MiB')
    dataset = str(request.get('dataset_id','unknown'))
    from scripts.run_detection_moe_image_gate import DATASETS
    if dataset not in (*DATASETS,'unknown'): raise ValueError('Dataset must be a supported DANDI ID or unknown')
    if request.get('input_mode') == 'single_channel' and dataset != 'unknown':
        raise ValueError('Single-channel detection requires dataset=unknown')
    animal = str(request.get('animal_id','app_volume'))
    progress(f'Preprocessing RGBW volume; estimated workspace {estimated/2**20:.0f} MiB')
    volume_path = output/'volume.npy'
    prepared_request = output/'preprocessing_request.json'
    prepared_request.write_text(json.dumps(request))
    run_command([sys.executable, Path(__file__).resolve(), 'prepare', '--request', prepared_request],
                output/'preprocessing.log', timeout=float(request.get('expert_timeout_seconds',3600)),
                env=lease.environment())
    device = request.get('device','cpu')
    if device == 'auto':
        import torch
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
    if device not in ('cpu','cuda'): raise ValueError('This MoE adapter supports CPU or CUDA; MPS parity is not validated')
    backend = request.get('backend','moe')
    if backend not in ('moe','spotiflow'): raise ValueError('Unknown detector backend')
    proposals = {}
    for method in (('spotiflow',) if backend == 'spotiflow' else ('spotiflow','yolo','nnunet')):
        progress(f'Running {method} expert')
        interpreter = request.get('interpreters',{}).get(method,sys.executable)
        run_command([interpreter,Path(__file__).resolve(),'expert','--bundle',bundle,'--volume',volume_path,
                     '--animal',animal,'--device',device,'--method',method,'--output',output],output/f'{method}.log',
                     timeout=float(request.get('expert_timeout_seconds',3600)), env=lease.environment())
        proposals[method] = pd.read_csv(output/f'{method}.csv')
    progress('Applying appearance gate and nonlinear routers')
    volume = np.load(volume_path, mmap_mode='r')
    result = route(bundle,volume,proposals,animal,dataset,output) if backend == 'moe' else proposals['spotiflow']
    del volume
    result.to_csv(output/'predictions_processed.csv',index=False)
    points = result[['x_um','y_um','z_um']].to_numpy(float)/spacing
    if len(points) and (not np.isfinite(points).all() or np.any(points < 0) or np.any(points >= np.array([shape[1],shape[0],shape[2]]))):
        raise ValueError('Detector returned centers outside the original image')
    centroids = points[:,[1,0,2]]+1
    response = dict(method_id='detection_moe' if backend == 'moe' else 'detection_spotiflow',num_centroids=len(result),centroids_yxz=centroids.tolist(),
                    scores=result.score.to_list(),predictions_csv=str(output/'predictions_processed.csv'),
                    source_revision='2276e61dedf9671740c1a36fab7d6d976b86de37',fold=0,
                    policy='nonlinear_moe_fold00' if backend == 'moe' else 'spotiflow_fold00',backend=backend,dataset_id=dataset,
                    input_mode=request.get('input_mode','rgbw'),
                    single_channel_unvalidated=request.get('input_mode')=='single_channel',
                    input_adaptation='repeat_selected_channel_four_times' if request.get('input_mode')=='single_channel' else 'none',
                    source_metadata=request.get('source_metadata', {}),
                    unknown_dataset_unvalidated=dataset=='unknown',
                    transform=dict(original_spacing_um_xyz=spacing.tolist(),processed_spacing_um_xyz=SPACING.tolist(),
                                   zoom_xyz=(spacing/SPACING).tolist(),crop_start_xyz=[0,0,0],matlab_axis_order='YXZ',index_base=1),
                    runtime_versions={name:importlib.metadata.version(name) for name in ('numpy','pandas','scipy','torch','spotiflow','ultralytics','scikit-learn','joblib')},
                    device=device, elapsed_seconds=time.monotonic()-started)
    temporary = response_path.with_suffix('.tmp')
    temporary.write_text(json.dumps(response,indent=2,allow_nan=False)+'\n')
    temporary.replace(response_path)
    progress(f'MoE finished: {len(result)} centers')


def main():
    def interrupted(signum, frame):
        raise KeyboardInterrupt('Detection canceled')
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command',required=True)
    p = sub.add_parser('run'); p.add_argument('--request',type=Path,required=True); p.add_argument('--response',type=Path,required=True)
    p = sub.add_parser('prepare'); p.add_argument('--request',type=Path,required=True)
    p = sub.add_parser('expert')
    for name in ('bundle','volume','output'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--animal',required=True); p.add_argument('--device',default='cpu'); p.add_argument('--method',choices=['spotiflow','yolo','nnunet'],required=True)
    args = parser.parse_args()
    if args.command == 'run': run(json.loads(args.request.read_text()),args.response)
    else:
        with JobLease('MoE ' + args.command):
            if args.command == 'prepare':
                prepare(json.loads(args.request.read_text()))
                return
            setup(args.bundle)
            import torch
            torch.set_num_threads(4)
            volume = None if args.method == 'yolo' else np.load(args.volume, mmap_mode='r')
            if args.method == 'spotiflow': frame = spotiflow(args.bundle,volume,args.animal,args.device)
            elif args.method == 'nnunet': frame = heatmap3d(args.bundle,volume,args.animal,args.device,args.output)
            else: frame = yolo(args.bundle,args.volume,args.animal,args.device,args.output)
            frame.to_csv(args.output/f'{args.method}.csv',index=False)
            print(f'{args.method}: {len(frame)} predictions',flush=True)

if __name__ == '__main__': main()
