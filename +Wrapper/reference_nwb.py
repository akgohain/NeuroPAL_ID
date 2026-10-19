"""Read paired NeuroPAL/calcium NWB metadata without loading image series."""
from pathlib import Path
import hashlib
import json
import h5py
import numpy as np


def text(value):
    return value.decode() if isinstance(value, bytes) else str(value)


def spacing(group):
    if 'grid_spacing' not in group:
        return None
    dataset = group['grid_spacing']
    scale = np.asarray(dataset[()], float).ravel()
    unit = text(dataset.attrs.get('unit', '')).lower()
    factor = {'micrometer': 1, 'micrometers': 1, 'um': 1, 'µm': 1,
              'meter': 1e6, 'meters': 1e6, 'm': 1e6}.get(unit)
    if factor is None or scale.size != 3 or not np.isfinite(scale).all() or np.any(scale <= 0):
        return None
    return (scale * factor).tolist()


def source_info(path):
    path = Path(path).resolve()
    with h5py.File(path, 'r') as f:
        acquisition = f.get('acquisition', {})
        candidates = [g for g in acquisition.values() if isinstance(g, h5py.Group)
                      and text(g.attrs.get('neurodata_type', '')) == 'MultiChannelVolumeSeries'
                      and 'data' in g and g['data'].ndim in (4, 5)]
        if len(candidates) != 1:
            raise ValueError('Expected one four- or five-dimensional MultiChannelVolumeSeries calcium recording in this NWB')
        series = candidates[0]; data = series['data']
        # Single-channel series may omit the trailing channel axis.
        nt, nx, ny, nz = data.shape[:4]
        nc = data.shape[4] if data.ndim == 5 else 1
        order = 'TXYZC' if data.ndim == 5 else 'TXYZ'
        if min(data.shape) < 1 or data.dtype.kind not in 'uif' or data.dtype.itemsize > 8:
            raise ValueError('Unsupported or empty NWB calcium series')
        if np.prod(data.shape[1:], dtype=np.int64)*data.dtype.itemsize > 256*2**20:
            raise MemoryError('A calcium frame exceeds the 256 MiB viewer limit')
        if data.chunks and np.prod(data.chunks,dtype=np.int64)*data.dtype.itemsize > 256*2**20:
            raise MemoryError('An NWB chunk exceeds the 256 MiB viewer limit')
        metadata = dict(axis_order=order, data_path=data.name)
        info = dict(file=str(path), nx=nx, ny=ny, nz=nz, nc=nc, nt=nt,
                    dtype=str(data.dtype), axis_order=order, data_path=data.name,
                    metadata=metadata, spacing_measured=False, has_times=False, time_units='unknown')
        scale = spacing(series['imaging_volume']) if 'imaging_volume' in series else None
        if scale is not None:
            info.update(spacing_measured=True, spacing_um_xyz=scale)
        if 'timestamps' in series and series['timestamps'].shape == (nt,):
            info.update(has_times=True, times_path=series['timestamps'].name, time_units='seconds')
        elif 'starting_time' in series:
            start = series['starting_time']; rate = float(start.attrs.get('rate', np.nan))
            if np.isfinite(rate) and rate > 0 and np.isfinite(start[()]):
                info.update(has_times=True, time_start=float(start[()]), frame_interval_seconds=1/rate, time_units='seconds')
        references = [g for g in acquisition.values() if isinstance(g, h5py.Group)
                      and text(g.attrs.get('neurodata_type','')) == 'MultiChannelVolume' and 'data' in g]
        if len(references) == 1:
            ref = references[0]; shape = ref['data'].shape
            # Support standard XYZC and the legacy CZXY NeuroPAL exporter.
            if len(shape) == 4:
                order = 'CZXY' if shape[0] <= 8 and shape[-1] > 8 else 'XYZC'
                dimensions = [shape[2],shape[3],shape[1],shape[0]] if order == 'CZXY' else list(shape)
                rgbw = np.asarray(ref['RGBW_channels'][()], int).ravel().tolist() if 'RGBW_channels' in ref else []
                info['neuropal'] = dict(dtype=str(ref['data'].dtype),itemsize=ref['data'].dtype.itemsize,data_path=ref['data'].name, axis_order=order, dimensions_xyzc=dimensions,
                    rgbw_channels=rgbw, spacing_um_xyz=spacing(ref['imaging_volume']) if 'imaging_volume' in ref else None)
        stat = path.stat()
        sample = data[(0, slice(None,None,max(1,nx//8)), slice(None,None,max(1,ny//8)),
                       slice(None,None,max(1,nz//4))) + ((slice(None),) if data.ndim == 5 else ())]
        identity = (str(path),stat.st_size,stat.st_mtime_ns,info)
        info['source_id'] = hashlib.sha256(json.dumps(identity,sort_keys=True).encode()+sample.tobytes()).hexdigest()
    return info


def align_reference(request):
    from scipy.ndimage import zoom, gaussian_filter
    from skimage.registration import phase_cross_correlation
    from reference_video import source_info, read_frame
    info = request['source']
    if source_info(info['file'])['source_id'] != info['source_id']:
        raise ValueError('Recording changed; reopen before aligning NeuroPAL')
    ref = info['neuropal']; channel = request.get('reference_channel',0)
    if int(channel)!=channel or not 0<=channel<ref['dimensions_xyzc'][3]:
        raise ValueError('Invalid NeuroPAL alignment channel')
    channel=int(channel)
    if request.get('scale_mode','extent') not in ('physical','extent'):
        raise ValueError('Choose image extents or voxel spacing for alignment')
    with h5py.File(info['file'],'r') as f:
        data = f[ref['data_path']]
        raw = data[channel] if ref['axis_order']=='CZXY' else data[:,:,:,channel]
        moving = raw.transpose(0,2,1) if ref['axis_order']=='CZXY' else raw.transpose(2,1,0)
    fixed = read_frame(info,int(request['frame_index']),int(request['channel']))[0].astype(np.float32)
    if not np.any(fixed) or not np.any(moving):
        raise ValueError('The selected alignment channel has no signal')
    source_shape = np.array(moving.shape)
    if request.get('scale_mode') == 'physical':
        if not ref.get('spacing_um_xyz') or not info.get('spacing_measured'):
            raise ValueError('Both volumes need voxel spacing for physical alignment')
        factors = np.array(ref['spacing_um_xyz'][::-1])/np.array(info['spacing_um_xyz'][::-1])
        if np.prod(np.ceil(source_shape*factors))*4>256*2**20:
            raise MemoryError('Aligned NeuroPAL volume exceeds the 256 MiB volume limit')
        resized = zoom(moving.astype(np.float32), factors, order=1)
        scaled = np.zeros_like(fixed)
        limits=tuple(slice(0,min(a,b)) for a,b in zip(scaled.shape,resized.shape))
        scaled[limits]=resized[limits]
        multiplier=(np.array(resized.shape)-1)/np.maximum(1,source_shape-1)
    else:
        factors = np.array(fixed.shape)/source_shape
        scaled = zoom(moving.astype(np.float32),factors,order=1)
        multiplier=(np.array(fixed.shape)-1)/np.maximum(1,source_shape-1)
    # Estimate translation from image intensities, without segmentation labels.
    a=gaussian_filter(fixed,1); b=gaussian_filter(scaled,1)
    shift,_,_=phase_cross_correlation(a,b,upsample_factor=10,normalization=None)
    from scipy.ndimage import shift as translate
    aligned=translate(b,shift,order=1,mode='constant',cval=0)
    correlation=float(np.corrcoef(a.ravel(),aligned.ravel())[0,1])
    if not np.isfinite(correlation): raise ValueError('Could not estimate an image alignment')
    return dict(scale_xyz=multiplier[::-1].tolist(),shift_xyz=shift[::-1].tolist(),
                correlation=correlation,frame_index=int(request['frame_index']),channel=int(request['channel']),
                reference_channel=channel,scale_mode=request.get('scale_mode','extent'),source_id=info['source_id'],
                coordinate_rule='video_xyz = (neuropal_xyz - 1) * scale_xyz + 1 + shift_xyz')
