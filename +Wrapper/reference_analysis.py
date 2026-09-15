"""Resumable tracking and streamed fluorescence measurements for reference videos."""
from __future__ import annotations
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import numpy as np
import h5py
from reference_video import source_info, read_frame, validate_observations, write_seed_files


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('w') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def verify_source(info):
    if source_info(info['file'])['source_id'] != info['source_id']:
        raise ValueError('Source recording changed; reopen it before continuing')


def windows(first, last, reference, size):
    result = []
    start = reference
    while start < last:
        end = min(last, start + size - 1)
        result.append((start, end, start))
        start = end
    end = reference
    while end > first:
        start = max(first, end - size + 1)
        result.append((start, end, end))
        end = start
    return result


def run_window(request, directory, number):
    request_path = directory / f'window-{number:04d}.request.json'
    response_path = directory / f'window-{number:04d}.response.json'
    atomic_json(request_path, request)
    log_path=directory/f'window-{number:04d}.log'
    with log_path.open('a') as log:
        process=subprocess.run([sys.executable, '-u', str(Path(__file__).with_name('reference_video.py')),
                        '--request', str(request_path), '--response', str(response_path)],
                       stdout=log, stderr=subprocess.STDOUT, check=False, timeout=7200)
    if process.returncode:
        with log_path.open('rb') as stream:
            stream.seek(max(0,log_path.stat().st_size-4096)); tail=stream.read().decode(errors='replace').strip().splitlines()
        reason=tail[-1] if tail else 'No diagnostic output'
        raise RuntimeError(f'ZephIR window failed: {reason}. Saved progress is in {directory}; see {log_path}')
    return json.loads(response_path.read_text())


def canonical_rows(rows):
    return [dict(track_id=int(r['track_id']),parent_id=0,t=int(r['t']),x=float(r['x']),y=float(r['y']),z=float(r['z']),
                 confidence=float(r['confidence']),channel=int(r.get('channel',0)),provenance=r.get('provenance','reviewed'),
                 excluded=bool(r.get('excluded',False)),name=r.get('name','Neuron '+str(int(r['track_id'])))) for r in rows]


def track_sequence(request):
    info = request['source']
    verify_source(info)
    first, last = request['frame_range']
    reference = request['reference_frame']
    channel = request['channel']
    size = request.get('window_size', 50)
    epochs = request.get('epochs', 40)
    for value in (first, last, reference, channel, size, epochs):
        if not np.isfinite(value) or int(value) != value:
            raise ValueError('Tracking frames, channel, window size and epochs must be integers')
    first, last, reference, channel, size, epochs = map(int, (first,last,reference,channel,size,epochs))
    if not 0 <= first <= reference <= last < info['nt']:
        raise ValueError('The reference frame must lie inside the tracking range')
    if not 0 <= channel < info['nc'] or not 2 <= size <= 100 or not 1 <= epochs <= 1000:
        raise ValueError('Invalid tracking channel, window size (2–100) or epochs (1–1000)')
    if not np.any(read_frame(info,reference,channel)>0):
        raise ValueError('The tracking channel has no signal in the reference frame; choose another channel')
    observations = validate_observations(request['observations'], info)
    seeds = [dict(r) for r in observations if r['t'] == reference+1 or r.get('provenance') != 'zephir']
    seeds = [r for r in seeds if first < r['t'] <= last+1]
    root_rows = [r for r in seeds if r['t'] == reference+1]
    ids = {int(r['track_id']) for r in root_rows}
    if not ids or any(int(r['track_id']) not in ids for r in seeds):
        raise ValueError('Every seed ID must be present at the reference frame; review that seed set first')
    seeds=canonical_rows(seeds)
    seeds.sort(key=lambda r:(r['t'],r['track_id']))
    root_rows=[r for r in seeds if r['t']==reference+1]
    annotation_channel = int(root_rows[0].get('channel', channel))
    parameters = dict(source_id=info['source_id'], frame_range=[first,last], reference_frame=reference,
                      channel=channel, window_size=size, epochs=epochs, observations=seeds)
    signature = hashlib.sha256(json.dumps(parameters,sort_keys=True).encode()).hexdigest()
    resume = request.get('resume_dir')
    if resume:
        directory = Path(resume).resolve()
        manifest = json.loads((directory/'tracking.json').read_text())
        if manifest['signature'] != signature:
            raise ValueError('Seeds or tracking settings changed. Start a new run instead of resuming this one')
        results = json.loads((directory/'checkpoint.json').read_text())
    else:
        root = Path(request['output_dir']); root.mkdir(parents=True,exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='tracking-',dir=root)).resolve()
        results = root_rows
        software={name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest() for name in ('reference_analysis.py','reference_video.py','main.py','track_all.py')}
        manifest = dict(schema_version=1, signature=signature, parameters=parameters, source=info, software_sha256=software,
                        completed=[], state='running', request={k:v for k,v in request.items() if k!='resume_dir'})
        atomic_json(directory/'checkpoint.json', results)
        atomic_json(directory/'tracking.json', manifest)
    for orphan in directory.glob('zephir-*'):
        marker=orphan/'.neuropal-window'
        if orphan.is_dir() and not orphan.is_symlink() and marker.is_file() and marker.read_text()==info['source_id']:
            shutil.rmtree(orphan)
    print(f'NEUROPAL_PROGRESS:Tracking workspace: {directory}',flush=True)
    by_key = {(int(r['track_id']),int(r['t'])):r for r in results}
    plan = windows(first,last,reference,size)
    try:
        for index,(start,end,anchor) in enumerate(plan):
            if index in manifest['completed']:
                continue
            boundary = [dict(r) for r in by_key.values() if r['t']==anchor+1]
            if {int(r['track_id']) for r in boundary} != ids:
                raise ValueError('Incomplete boundary checkpoint; cannot propagate neuron identities')
            local_seeds = {(r['track_id'],r['t']):r for r in boundary}
            local_seeds.update({(r['track_id'],r['t']):r for r in seeds if start < r['t'] <= end+1})
            print(f'NEUROPAL_PROGRESS:ZephIR window {index+1}/{len(plan)} · frames {start+1}–{end+1}',flush=True)
            work = dict(action='track', source=info, frame_range=[start,end], channel=channel,
                        observations=list(local_seeds.values()), output_dir=str(directory), epochs=epochs,
                        provenance=request.get('provenance',{}))
            response = run_window(work,directory,index)
            result = validate_observations(response['observations'],info)
            expected = {(i,t) for i in ids for t in range(start+1,end+2)}
            if {(r['track_id'],r['t']) for r in result} != expected:
                raise ValueError('Tracking window returned incomplete or unexpected neuron IDs')
            for row in result:
                row['channel'] = annotation_channel
                by_key[(row['track_id'],row['t'])] = row
            # Keep explicit manual coordinates and the original reference exactly.
            by_key.update({(r['track_id'],r['t']):r for r in seeds if (r['track_id'],r['t']) in by_key})
            results = canonical_rows(sorted(by_key.values(),key=lambda r:(r['t'],r['track_id'])))
            atomic_json(directory/'checkpoint.json',results)
            manifest['completed'].append(index)
            manifest['state']='running'; manifest.pop('error',None)
            atomic_json(directory/'tracking.json',manifest)
            # Only discard this job's staged pixels after its durable checkpoint.
            stage = Path(response['directory']).resolve()
            if stage.parent == directory and stage.name.startswith('zephir-'):
                shutil.rmtree(stage)
        results=canonical_rows(results)
        atomic_json(directory/'checkpoint.json',results)
        manifest['state']='complete'
        atomic_json(directory/'tracking.json',manifest)
        export = directory/'tracks'
        export.mkdir(exist_ok=True)
        write_seed_files(export,results,info,dict(tracking=str(directory),parameters=parameters))
        return dict(directory=str(directory),observations=results,completed_windows=len(manifest['completed']))
    except Exception as error:
        manifest['state']='failed'; manifest['error']=str(error)
        atomic_json(directory/'tracking.json',manifest)
        raise


# Flags are stored with every frame/neuron measurement; gaps remain NaN.
FLAGS = dict(missing=1, excluded=2, clipped_roi=4, overlap=8, empty_roi=16,
             empty_background=32, invalid_baseline=64, invalid_reference=128, large_step=256, saturated=512, invalid_ratio_baseline=1024)


def roi_indices(center, radius, shape, inner=0., outer=1.):
    center = np.asarray(center,float)-1
    radius = np.asarray(radius,float)
    lower = np.floor(center-radius*outer).astype(int)
    upper = np.ceil(center+radius*outer).astype(int)
    clipped = bool(np.any(lower<0) or np.any(upper>=np.array(shape)))
    axes = [np.arange(max(0,lower[i]),min(shape[i]-1,upper[i])+1) for i in range(3)]
    grid = np.meshgrid(*axes,indexing='ij')
    xyz = np.stack([a.ravel() for a in grid],axis=1)
    distance = np.sum(((xyz-center)/radius)**2,axis=1)
    keep = (distance<=outer**2) & (distance>inner**2 if inner else True)
    xyz, distance = xyz[keep],distance[keep]
    flat = np.ravel_multi_index((xyz[:,2],xyz[:,1],xyz[:,0]),shape[::-1])
    return flat,distance,clipped


def activity(request):
    info = request['source']; verify_source(info)
    rows = validate_observations(request['observations'],info)
    if not rows: raise ValueError('Accept and track neurons before extracting activity')
    first,last = request['frame_range']
    if int(first)!=first or int(last)!=last or not 0<=first<=last<info['nt']:
        raise ValueError('Invalid activity frame range')
    first,last=int(first),int(last)
    options = dict(radius_xyz=[3,3,1], background=True, shell_inner=1.5, shell_outer=2.5,
                   baseline_percentile=20., signal_channel=0, reference_channel=-1, max_step=10.)
    options.update(request.get('options',{}))
    radius=np.asarray(options['radius_xyz'],float)
    if radius.shape!=(3,) or not np.isfinite(radius).all() or np.any(radius<=0) or np.any(radius>50):
        raise ValueError('ROI radii must be three positive pixel values, at most 50 each')
    if not 1<=options['shell_inner']<options['shell_outer']<=5:
        raise ValueError('Background shell must satisfy 1 <= inner < outer <= 5')
    if not np.isfinite(options['max_step']) or options['max_step']<=0:
        raise ValueError('Motion warning threshold must be positive')
    if not 0<=options['baseline_percentile']<=100 or not np.isfinite(options['baseline_percentile']):
        raise ValueError('Baseline percentile must lie between 0 and 100')
    signal,reference=options['signal_channel'],options['reference_channel']
    if int(signal)!=signal or not 0<=signal<info['nc'] or int(reference)!=reference or not -1<=reference<info['nc'] or reference==signal:
        raise ValueError('Invalid signal/reference channels; choose distinct channels or no reference')
    channels=[int(signal)] + ([int(reference)] if reference>=0 else [])
    ids=sorted({int(r['track_id']) for r in rows})
    nt,nn=last-first+1,len(ids)
    if nt*nn*len(channels)*8 > 128*2**20:
        raise MemoryError('Trace matrices exceed the 128 MiB analysis budget; shorten the range or reduce the seed set')
    by_frame={}
    for row in rows:
        if first < row['t'] <= last+1: by_frame.setdefault(int(row['t'])-1,{})[int(row['track_id'])]=row
    raw=np.full((nt,nn,len(channels)),np.nan); background=raw.copy()
    counts=np.zeros((nt,nn),np.uint32); flags=np.zeros((nt,nn),np.uint16)
    centers=np.full((nt,nn,3),np.nan); saturation=np.full((nt,nn),np.nan)
    shape=(info['nx'],info['ny'],info['nz'])
    shell_budget=np.prod(np.minimum(shape,2*np.ceil(radius*options['shell_outer'])+3))
    core_budget=np.prod(np.minimum(shape,2*np.ceil(radius)+3))*nn
    if shell_budget>250000 or core_budget>1000000:
        raise MemoryError('ROI neighborhoods exceed the analysis memory budget; use smaller radii or fewer neurons')
    with h5py.File(info['file'],'r') as source:
        times=source['times'][first:last+1] if info.get('has_times') else np.full(nt,np.nan)
        for ti,t in enumerate(range(first,last+1)):
            current=by_frame.get(t,{})
            cores={}; owners={}; occupied=set()
            for j,identity in enumerate(ids):
                row=current.get(identity)
                if row is None: flags[ti,j]|=FLAGS['missing']; continue
                center=[row[a] for a in 'xyz']; centers[ti,j]=center
                if row.get('excluded',False): flags[ti,j]|=FLAGS['excluded']
                if ti and np.isfinite(centers[ti-1,j]).all() and np.linalg.norm(centers[ti,j]-centers[ti-1,j])>options['max_step']:
                    flags[ti,j]|=FLAGS['large_step']
                core,dist,clipped=roi_indices(center,radius,shape)
                cores[j]=core; occupied.update(core.tolist())
                if clipped: flags[ti,j]|=FLAGS['clipped_roi']
                for voxel,distance in zip(core,dist):
                    previous=owners.get(int(voxel))
                    if previous is not None:
                        flags[ti,j]|=FLAGS['overlap']; flags[ti,previous[1]]|=FLAGS['overlap']
                    if previous is None or distance<previous[0]: owners[int(voxel)]=(distance,j)
            volume=np.asarray(source['data'][t])
            if info['axis_order']=='TCZXY': volume=volume.transpose(0,1,3,2)
            if not np.isfinite(volume).all(): raise ValueError(f'Nonfinite image values at frame {t+1}')
            values=volume[channels].reshape(len(channels),-1)
            ceiling=np.iinfo(volume.dtype).max if volume.dtype.kind in 'ui' else np.inf
            for j,core in cores.items():
                selected=np.array([v for v in core if owners[int(v)][1]==j],dtype=int)
                counts[ti,j]=len(selected)
                if not len(selected): flags[ti,j]|=FLAGS['empty_roi']; continue
                if flags[ti,j]&FLAGS['excluded']: continue
                raw[ti,j]=np.mean(values[:,selected],axis=1,dtype=np.float64)
                saturation[ti,j]=np.mean(values[0,selected]>=ceiling)
                if saturation[ti,j]>0: flags[ti,j]|=FLAGS['saturated']
                if options['background']:
                    shell,_,_=roi_indices(centers[ti,j],radius,shape,options['shell_inner'],options['shell_outer'])
                    shell=np.array([v for v in shell if v not in occupied],dtype=int)
                    if len(shell): background[ti,j]=np.median(values[:,shell],axis=1)
                    else: flags[ti,j]|=FLAGS['empty_background']
                else: background[ti,j]=0
            if ti%10==0 or t==last: print(f'NEUROPAL_PROGRESS:Extracting fluorescence · frame {t+1}/{last+1}',flush=True)
    corrected=raw-background
    f0=np.full(nn,np.nan); dff=np.full((nt,nn),np.nan)
    ratio=np.full((nt,nn),np.nan); ratio_dff=ratio.copy(); ratio_f0=f0.copy()
    for j in range(nn):
        trace=corrected[:,j,0]; valid=np.isfinite(trace)
        if np.any(valid): f0[j]=np.percentile(trace[valid],options['baseline_percentile'])
        if f0[j]>0: dff[valid,j]=(trace[valid]-f0[j])/f0[j]
        else: flags[:,j]|=FLAGS['invalid_baseline']
        if reference>=0:
            denominator=corrected[:,j,1]
            valid=valid & np.isfinite(denominator) & (denominator>0)
            flags[~valid,j]|=FLAGS['invalid_reference']
            ratio[valid,j]=trace[valid]/denominator[valid]
            if np.any(valid): ratio_f0[j]=np.percentile(ratio[valid,j],options['baseline_percentile'])
            if ratio_f0[j]>0: ratio_dff[valid,j]=(ratio[valid,j]-ratio_f0[j])/ratio_f0[j]
            else: flags[:,j]|=FLAGS['invalid_ratio_baseline']
    root=Path(request['output_dir']); root.mkdir(parents=True,exist_ok=True)
    if shutil.disk_usage(root).free < raw.nbytes*20+256*2**20: raise OSError('Insufficient free space for activity export')
    stage=Path(tempfile.mkdtemp(prefix='.activity-',dir=root)); destination=root/('activity-'+stage.name[10:])
    try:
        with h5py.File(stage/'activity.h5','w') as f:
            f.attrs['schema_version']=1; f.attrs['matrix_axes']='frame,neuron'; f.attrs['coordinate_axes']='frame,neuron,xyz'
            f.attrs['time_units']=info.get('time_units','unknown'); f.attrs['source_id']=info['source_id']
            arrays=dict(frame=np.arange(first+1,last+2), neuron_id=ids, source_time=times, centers_xyz=centers,
                        signal=corrected[:,:,0], dff=dff, f0=f0, ratio=ratio, ratio_dff=ratio_dff, ratio_f0=ratio_f0,
                        roi_voxels=counts, quality_flags=flags, saturation_fraction=saturation)
            for name,array in arrays.items(): f.create_dataset(name,data=array,compression='gzip')
            for ci,channel in enumerate(channels):
                f[f'raw/channel_{channel}']=raw[:,:,ci]; f[f'background/channel_{channel}']=background[:,:,ci]
        with (stage/'activity.csv').open('w',newline='') as stream:
            writer=csv.writer(stream)
            writer.writerow(['frame','source_time','neuron_id','x','y','z','raw_f','background_f','corrected_f','dff','ratio','ratio_dff','reference_raw_f','reference_background_f','roi_voxels','quality_flags'])
            for ti,t in enumerate(range(first,last+1)):
                for j,identity in enumerate(ids): writer.writerow([t+1,times[ti],identity,*centers[ti,j],raw[ti,j,0],background[ti,j,0],corrected[ti,j,0],dff[ti,j],ratio[ti,j],ratio_dff[ti,j],raw[ti,j,1] if reference>=0 else np.nan,background[ti,j,1] if reference>=0 else np.nan,counts[ti,j],flags[ti,j]])
        with (stage/'quality.csv').open('w',newline='') as stream:
            writer=csv.writer(stream);writer.writerow(['neuron_id','measured_frames','finite_dff_frames',*FLAGS])
            for j,identity in enumerate(ids):
                writer.writerow([identity,int(np.count_nonzero(np.isfinite(raw[:,j,0]))),int(np.count_nonzero(np.isfinite(dff[:,j]))),
                                 *[int(np.count_nonzero(flags[:,j]&flag)) for flag in FLAGS.values()]])
        revision={name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                  for name in ('reference_analysis.py','reference_video.py','main.py','track_all.py')}
        provenance=dict(source=info,software_sha256=revision,options=options,frame_range_one_based=[first+1,last+1],flags=FLAGS,
                        baseline='percentile of finite background-corrected fluorescence over the selected range; no interpolation, bleaching correction or clipping',
                        overlap='nearest center in normalized ellipsoid coordinates; ties go to the lower neuron ID',
                        history=request.get('provenance',{}),numpy=np.__version__,h5py=h5py.__version__)
        atomic_json(stage/'analysis.json',provenance)
        tracks=stage/'tracks'; tracks.mkdir();write_seed_files(tracks,rows,info,request.get('provenance',{}))
        stage.rename(destination)
    finally:
        if stage.exists(): shutil.rmtree(stage)
    return dict(directory=str(destination),neuron_count=nn,frame_count=nt,finite_fraction=float(np.mean(np.isfinite(dff))),
                flagged_fraction=float(np.mean(flags!=0)))
