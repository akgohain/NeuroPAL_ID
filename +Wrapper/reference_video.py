#!/usr/bin/env python3
"""Bounded calcium frame IO and explicit ZephIR seed coordinates."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import numpy as np
import h5py


def source_info(path):
    path = Path(path).resolve()
    sidecar = path.parent / 'metadata.json'
    metadata = json.loads(sidecar.read_text()) if sidecar.is_file() else {}
    with h5py.File(path, 'r') as f:
        data = f['data']
        if data.ndim != 5 or any(n < 1 for n in data.shape):
            raise ValueError('Expected a nonempty five-dimensional /data recording')
        if data.dtype.kind not in 'uif' or data.dtype.itemsize > 8:
            raise ValueError('Unsupported recording dtype')
        shape = tuple(data.shape)
        declared = tuple(metadata.get('shape_' + a, 0) for a in 'tczyx')
        order = metadata.get('axis_order', '')
        if order and order not in ('TCZYX','TCZXY'):
            raise ValueError('Unsupported axis_order')
        if order == 'TCZYX' or (not order and all(declared) and shape == declared):
            order = 'TCZYX'
        elif order == 'TCZXY' or (not order and all(declared) and shape == declared[:3] + declared[:2:-1]):
            order = 'TCZXY'
        elif all(declared):
            raise ValueError('Recording shape disagrees with metadata.json')
        else:
            raise ValueError('Specify shape_t/c/z/y/x or axis_order in metadata.json for this H5 recording')
        nt, nc, nz, ny, nx = shape if order == 'TCZYX' else shape[:3] + (shape[4], shape[3])
        if np.prod(shape[1:],dtype=np.int64)*data.dtype.itemsize > 256*2**20:
            raise MemoryError('A frame exceeds the 256 MiB reference viewer limit')
        if data.chunks and np.prod(data.chunks,dtype=np.int64)*data.dtype.itemsize > 256*2**20:
            raise MemoryError('An H5 chunk exceeds the 256 MiB reference viewer limit')
        if all(declared) and (nt,nc,nz,ny,nx) != declared:
            raise ValueError('Explicit axis order disagrees with shape metadata')
        # Sample bounded voxels, never hash or load the whole recording.
        sample = np.asarray(data[0, :, :, ::max(1,shape[3]//8), ::max(1,shape[4]//8)])
        stat = path.stat()
        identity = hashlib.sha256(str((path, stat.st_size, stat.st_mtime_ns, shape, json.dumps(metadata,sort_keys=True))).encode() + sample.tobytes()).hexdigest()
        info = dict(file=str(path), nx=nx, ny=ny, nz=nz, nc=nc, nt=nt,
                    dtype=str(data.dtype), axis_order=order, source_id=identity,
                    metadata=metadata, spacing_measured=False, time_units=metadata.get('time_units', 'unknown'))
        spacing = metadata.get('spacing_um_xyz')
        if spacing is not None:
            spacing = np.asarray(spacing, float)
            if spacing.shape != (3,) or not np.isfinite(spacing).all() or np.any(spacing <= 0):
                raise ValueError('spacing_um_xyz must contain three positive values')
            info.update(spacing_um_xyz=spacing.tolist(), spacing_measured=True)
        info['has_times'] = 'times' in f and f['times'].shape == (nt,)
    return info


def read_frame(info, frame, channel=None):
    if int(frame) != frame or not 0 <= frame < info['nt']:
        raise ValueError('Frame index is outside recording')
    if channel is not None and not 0 <= channel < info['nc']:
        raise ValueError('Channel index is outside recording')
    frame = int(frame)
    if channel is not None: channel = int(channel)
    with h5py.File(info['file'], 'r') as f:
        raw = f['data'][frame] if channel is None else f['data'][frame, channel:channel+1]
    if info['axis_order'] == 'TCZXY':
        raw = raw.transpose(0, 1, 3, 2)
    if not np.isfinite(raw).all():
        raise ValueError('Selected frame contains nonfinite values')
    return raw


def validate_observations(rows, info):
    if not rows:
        return []
    seen = set()
    for row in rows:
        for key in ('track_id', 't', 'x', 'y', 'z', 'confidence'):
            if not np.isfinite(row[key]):
                raise ValueError('Nonfinite annotation value')
        if row['track_id'] < 1 or row['track_id'] > np.iinfo(np.uint32).max or int(row['track_id']) != row['track_id']:
            raise ValueError('Worldline IDs must be positive integers')
        if int(row['t']) != row['t'] or not 1 <= row['t'] <= info['nt']:
            raise ValueError('Frame must be a one-based integer')
        for key in 'xyz':
            if not 1 <= row[key] <= info['n'+key]:
                raise ValueError('Seed outside source volume: ' + key)
        if not 0 <= row['confidence'] <= 1:
            raise ValueError('Invalid confidence')
        if 'channel' in row and (int(row['channel']) != row['channel'] or not 0 <= row['channel'] < info['nc']):
            raise ValueError('Annotation channel is outside the recording')
        key = (int(row['track_id']), int(row['t']))
        if key in seen:
            raise ValueError('Duplicate worldline observation in the same frame')
        seen.add(key)
    return rows


def write_seed_files(directory, rows, info, provenance):
    validate_observations(rows, info)
    if not rows:
        raise ValueError('No reference annotations to save')
    directory = Path(directory)
    ids = sorted({int(r['track_id']) for r in rows})
    with h5py.File(directory/'annotations.h5', 'w') as f:
        f['id'] = np.arange(1, len(rows)+1, dtype='uint32')
        f['t_idx'] = np.array([r['t']-1 for r in rows], dtype='uint32')
        f['worldline_id'] = np.array([r['track_id'] for r in rows], dtype='uint32')
        f['parent_id'] = np.zeros(len(rows), dtype='uint32')
        f['provenance'] = np.array([b'ZEIR' if r.get('provenance') == 'zephir' else b'MANU' for r in rows], dtype='S4')
        for key in 'xyz':
            f[key] = np.array([(r[key]-.5)/info['n'+key] for r in rows], dtype='float32')
    with h5py.File(directory/'worldlines.h5', 'w') as f:
        f['id'] = np.array(ids, dtype='uint32')
        names = {int(r['track_id']): r.get('name', 'Neuron '+str(int(r['track_id']))) for r in rows}
        f['name'] = np.array([names[i].encode() for i in ids], dtype='S64')
        f['color'] = np.array([b'#66cc99']*len(ids), dtype='S7')
    with (directory/'centers.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['track_id','t','x','y','z','confidence'])
        writer.writeheader()
        writer.writerows({k:r[k] for k in writer.fieldnames} for r in rows)
    (directory/'observations.json').write_text(json.dumps(rows, indent=2))
    (directory/'provenance.json').write_text(json.dumps(dict(source=info, detection=provenance,
        coordinates='one-based MATLAB pixel centers; t is one-based', schema_version=1), indent=2))


def read_seeds(path, info):
    path = Path(path)
    if path.is_dir(): path = path/'annotations.h5'
    with h5py.File(path, 'r') as f:
        n = len(f['t_idx'])
        rows = [dict(track_id=int(f['worldline_id'][i]), parent_id=0, t=int(f['t_idx'][i])+1,
                     confidence=1., provenance='imported', **{a:float(f[a][i])*info['n'+a]+.5 for a in 'xyz'}) for i in range(n)]
    with h5py.File(path.parent/'worldlines.h5', 'r') as f:
        names = {int(i): n.decode() if isinstance(n,bytes) else str(n) for i,n in zip(f['id'][:], f['name'][:])}
    # Float32 normalized centers have a small endpoint rounding error.
    for row in rows:
        if row['track_id'] not in names: raise ValueError('Missing worldline ID')
        row['name'] = names[row['track_id']]
        for a in 'xyz':
            if abs(row[a]-1) < 1e-4: row[a] = 1.
            if abs(row[a]-info['n'+a]) < 1e-4: row[a] = float(info['n'+a])
    sidecar = path.parent/'observations.json'
    if sidecar.is_file():
        original = json.loads(sidecar.read_text())
        by_key = {(int(r['track_id']),int(r['t'])):r for r in original}
        for row in rows:
            old = by_key.get((row['track_id'],row['t']))
            if old and all(abs(row[a]-old[a]) < 1e-4 for a in 'xyz'):
                row.update({k:v for k,v in old.items() if k not in ('track_id','t','name')})
    for row in rows: row.setdefault('excluded',False)
    validate_observations(rows, info)
    return rows


def export_seeds(request):
    info = request['source']
    actual = source_info(info['file'])
    if actual['source_id'] != info['source_id']:
        raise ValueError('Source recording changed since detection')
    root = Path(request['output_dir']).resolve()
    root.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.seeds-', dir=root))
    destination = root/('seeds-'+stage.name[7:])
    try:
        write_seed_files(stage, request['observations'], info, request.get('provenance', {}))
        check = read_seeds(stage, info)
        if len(check) != len(request['observations']): raise ValueError('Seed validation failed')
        stage.rename(destination)
    finally:
        if stage.exists(): shutil.rmtree(stage)
    return dict(directory=str(destination), count=len(check))


def run(request):
    if isinstance(request.get('observations'),dict): request['observations'] = [request['observations']]
    action = request['action']
    if action == 'inspect': return source_info(request['file'])
    if action == 'frame':
        info = request['source']
        raw = read_frame(info, request['frame_index'])
        # MATLAB reads the binary as YXZC, in column-major order.
        yxzc = raw.transpose(2,3,1,0)
        yxzc.ravel(order='F').tofile(request['output_raw'])
        return dict(shape_yxzc=list(yxzc.shape), dtype=str(raw.dtype))
    if action == 'export': return export_seeds(request)
    if action == 'import':
        info = request['source']
        if source_info(info['file'])['source_id'] != info['source_id']:
            raise ValueError('Source recording changed; reopen it before importing seeds')
        provenance = Path(request['file']).parent/'provenance.json'
        saved = json.loads(provenance.read_text()) if provenance.exists() else None
        if saved and saved['source']['source_id'] != info['source_id']:
            raise ValueError('These seeds belong to a different source recording')
        mapping_path = Path(request['file']).parent/'source_mapping.json'
        rows = read_seeds(request['file'], info)
        if mapping_path.exists():
            mapping = json.loads(mapping_path.read_text())
            if mapping['source']['source_id'] != info['source_id']:
                raise ValueError('Tracking output belongs to a different source')
            for row in rows:
                row['t'] += mapping['frame_start']
                row['channel'] = mapping['channel']
                if row['provenance'] == 'imported':
                    row['provenance'] = 'zephir'
                    row['confidence'] = 0.0
        elif saved and saved['source']['nt'] != info['nt']:
            raise ValueError('Incomplete tracking output has no source frame mapping')
        validate_observations(rows,info)
        return dict(observations=rows, provenance=saved.get('detection',{}) if saved else {})
    if action == 'track': return track(request)
    if action in ('track_sequence','activity'):
        import reference_analysis
        return getattr(reference_analysis,action)(request)
    if action == 'tracking_checkpoint':
        directory = Path(request['directory'])
        manifest = json.loads((directory/'tracking.json').read_text())
        actual = source_info(request['source']['file'])
        if manifest['source']['source_id'] != actual['source_id'] or request['source']['source_id'] != actual['source_id']:
            raise ValueError('Tracking checkpoint belongs to a different source')
        rows = validate_observations(json.loads((directory/'checkpoint.json').read_text()),request['source'])
        return dict(observations=rows,manifest=manifest)
    raise ValueError('Unknown reference action: '+action)


def track(request):
    """Run ZephIR in an isolated short-window workspace, never in the source folder."""
    info = request['source']
    if source_info(info['file'])['source_id'] != info['source_id']:
        raise ValueError('Source recording changed')
    first, last = request['frame_range']
    if int(first)!=first or int(last)!=last: raise ValueError('Frames must be integers')
    first, last = int(first),int(last)
    channel = int(request['channel'])
    if not (0 <= first <= last < info['nt']) or last-first+1 > 100:
        raise ValueError('Choose a tracking window of at most 100 frames')
    validate_observations(request['observations'],info)
    rows = [dict(r, t=r['t']-first, channel=0) for r in request['observations'] if first <= r['t']-1 <= last]
    if not rows: raise ValueError('Tracking window must include a reference annotation')
    root = Path(request['output_dir']);root.mkdir(parents=True, exist_ok=True)
    staged_bytes = (last-first+1)*info['nx']*info['ny']*info['nz']*np.dtype(info['dtype']).itemsize
    if staged_bytes > 1024*2**20:
        raise MemoryError('Selected tracking window exceeds the 1 GiB staging limit; shorten the window')
    if shutil.disk_usage(root).free < staged_bytes + 512*2**20:
        raise OSError('Insufficient free space for the isolated tracking window and checkpoint reserve')
    stage = Path(tempfile.mkdtemp(prefix='zephir-', dir=root))
    (stage/'.neuropal-window').write_text(info['source_id'])
    local = dict(info, nt=last-first+1, nc=1, axis_order='TCZYX')
    metadata = dict(info['metadata'])
    metadata.update({f'shape_{k}':v for k,v in zip('tczyx',[local['nt'],1,info['nz'],info['ny'],info['nx']])})
    metadata['axis_order'] = 'TCZYX'
    metadata['source_frame_start'] = first
    (stage/'metadata.json').write_text(json.dumps(metadata, indent=2))
    with h5py.File(stage/'data.h5','w') as f:
        d = f.create_dataset('data', shape=(local['nt'],1,info['nz'],info['ny'],info['nx']), dtype=info['dtype'],
                             chunks=(1,1,info['nz'],info['ny'],info['nx']), compression='lzf')
        for i,t in enumerate(range(first,last+1)):
            d[i] = read_frame(info,t,channel)
        with h5py.File(info['file'],'r') as src:
            if info.get('has_times'): f['times'] = src['times'][first:last+1]
    write_seed_files(stage,rows,local,request.get('provenance',{}))
    # Supplied coordinates anchor this window; the sidecar retains their provenance.
    with h5py.File(stage/'annotations.h5','r+') as annotations:
        annotations['provenance'][:]=np.array([b'MANU']*len(rows),dtype='S4')
    print('NEUROPAL_PROGRESS:Tracking selected window with ZephIR',flush=True)
    # Import lazily so ordinary frame reads do not load torch or model weights.
    from docopt import docopt
    import main as zephir_main
    args = docopt(zephir_main.__doc__, argv=[f'--dataset={stage}', '--filename=data.h5', '--channel=0',
        '--cuda=False', '--n_epoch='+str(request.get('epochs',40)), '--n_epoch_d=0', '--lambda_d=0',
        '--sort_mode=linear', '--save_mode=o', '--load_nn=False'])
    zephir_main.run_zephir(stage,args,filename='data.h5')
    result = read_seeds(stage,local)
    for r in result:
        r['t'] += first
        r['channel'] = channel
        if r['provenance'] == 'imported':
            r['provenance'] = 'zephir'
            r['confidence'] = 0.0
    expected = {int(r['track_id']) for r in rows}
    for t in range(first+1,last+2):
        if {r['track_id'] for r in result if r['t']==t} != expected:
            raise ValueError('ZephIR output is missing frame/worldline observations')
    validate_observations(result,info)
    (stage/'source_mapping.json').write_text(json.dumps(dict(source=info,frame_start=first,channel=channel),indent=2))
    return dict(directory=str(stage), observations=result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--request', required=True);parser.add_argument('--response', required=True)
    args = parser.parse_args()
    response = run(json.loads(Path(args.request).read_text()))
    Path(args.response).write_text(json.dumps(response, indent=2))
