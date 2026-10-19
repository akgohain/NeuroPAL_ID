"""Recommend representative video frames without changing annotations or metadata."""
from __future__ import annotations
from numbers import Real
import h5py
import numpy as np


def recommend(request):
    from reference_video import source_info, frame_from_file
    supplied = request['source']
    info = source_info(supplied['file'])
    if info['source_id'] != supplied['source_id']:
        raise ValueError('Recording changed; reopen it before recommending frames')
    channel = request.get('channel', 0)
    count = request.get('count', 5)
    limit = request.get('max_candidates', 128)
    for value, low, high in ((channel, 0, info['nc']-1), (count, 1, 20), (limit, 2, 512)):
        if isinstance(value, bool) or not isinstance(value, Real) or not np.isfinite(value) or int(value) != value or not low <= value <= high:
            raise ValueError('Invalid recommendation channel, count or sampling limit')
    frames = np.unique(np.linspace(0, info['nt']-1, min(info['nt'], int(limit)), dtype=int))
    features = []
    signal = []
    with h5py.File(info['file'], 'r') as source:
        for i, frame in enumerate(frames):
            volume = frame_from_file(source, info, int(frame), int(channel))[0]
            # Three small projections describe pose without retaining full frames.
            parts = []
            for axis in range(3):
                projection = np.max(volume, axis=axis)
                y = np.linspace(0, projection.shape[0], min(32, projection.shape[0])+1, dtype=int)[:-1]
                x = np.linspace(0, projection.shape[1], min(32, projection.shape[1])+1, dtype=int)[:-1]
                # Pool every pixel so narrow neurons cannot fall between sampled columns.
                thumbnail = np.maximum.reduceat(np.maximum.reduceat(projection, y, axis=0), x, axis=1)
                flat = thumbnail.astype(float).ravel()
                flat -= flat.mean()
                length = np.linalg.norm(flat)
                parts.append(flat / length if length else np.zeros_like(flat))
            features.append(np.concatenate(parts))
            signal.append(bool(np.any(volume > 0)) and any(np.any(part) for part in parts))
            if i % 8 == 0:
                print(f'NEUROPAL_PROGRESS:Comparing frames {i+1}/{len(frames)}', flush=True)
    if not any(signal):
        raise ValueError('The sampled frames have no positive signal with spatial structure in this channel')
    features = np.asarray(features)
    # Zero-signal frames cannot become annotation recommendations.
    valid = np.flatnonzero(signal)
    features = features[valid]
    norms = np.linalg.norm(features, axis=1, keepdims=True)
    normalized = np.divide(features, norms, out=np.zeros_like(features), where=norms > 0)
    distances = np.clip(1 - normalized @ normalized.T, 0, 2)
    np.fill_diagonal(distances, 0)
    costs = distances.mean(axis=1)
    ties = np.flatnonzero(np.isclose(costs, costs.min(), rtol=1e-8, atol=1e-10))
    middle = (info['nt']-1)/2
    chosen = [int(ties[np.argmin(np.abs(frames[valid[ties]]-middle))])]
    nearest = distances[chosen[0]].copy()
    for _ in range(min(int(count), len(valid))-1):
        costs = np.minimum(distances, nearest[None, :]).mean(axis=1)
        costs[chosen] = np.inf
        ties = np.flatnonzero(np.isclose(costs, costs.min(), rtol=1e-8, atol=1e-10))
        separation = np.min(np.abs(frames[valid[ties], None]-frames[valid[chosen]][None, :]), axis=1)
        index = int(ties[np.argmax(separation)])
        chosen.append(index)
        nearest = np.minimum(nearest, distances[index])
    if source_info(info['file'])['source_id'] != info['source_id']:
        raise ValueError('Recording changed while recommending frames; reopen it before continuing')
    return dict(frames=frames[valid[chosen]].tolist(), channel=int(channel),
                source_id=info['source_id'], sampled_frames=len(frames),
                method='greedy_correlation_medoids', frame_index_base=0,
                mean_correlation_distance=float(nearest.mean()))
