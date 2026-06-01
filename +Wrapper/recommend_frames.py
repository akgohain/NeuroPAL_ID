"""
recommend_frames.py: search and determine optimal reference frames to annotate for ZephIR.

Determine median frames to recommend as reference frames via k-medoids clustering
based on thumbnail distances (see build_pdists). Clustering is done iteratively,
such that one cluster is determined at a time. n_iter > 0 will re-iterate over
the existing list of median frames to fine-tune recommendations.

Usage:
    recommend_frames.py -h | --help
    recommend_frames.py -v | --version
    recommend_frames.py --dataset=<dataset> [options]

Options:
    -h --help                           	show this message and exit.
    -v --version                        	show version information and exit.
    --dataset=<dataset>  					path to data directory to analyze.
    --n_frames=<n_frames>  					number of reference frames to search for. [default: 5]
    --n_iter=<n_iter>  						number of iterations for optimizing results; -1 to uncap. [default: 0]
    --t_list=<t_list>  						frames to analyze.
    --max_candidate_frames=<max_candidate_frames>   maximum frames to include when --t_list is omitted. [default: 512]
    --channel=<channel>  					data channel to use for calculating correlation coefficients.
    --nx=<nx>  	                            size of x-axis.
    --ny=<ny>  	                            size of y-axis.
    --nz=<nz>  	                            number of slices.
    --nc=<nc>  	                            number of channels.
    --nt=<nt>  	                            number of frames.
    --save_to_metadata=<save_to_metadata>  	save t_ref to metadata.json. [default: True]
    --verbose=<verbose>  					return score plots during search. [default: False]
"""

import h5py.defs
import h5py.utils
import h5py.h5ac
import h5py._proxy

import ast
import hashlib
from collections import OrderedDict
from docopt import docopt

from zephir.__version__ import __version__
#from zephir.methods.build_pdists import get_all_pdists
from skimage.transform import resize
from zephir.utils.utils import *
from zephir.utils.io import *
from getters import *
import numpy as np
import sys


def parse_literal_arg(value, name):
    if value is None:
        return None
    try:
        return ast.literal_eval(value)
    except (SyntaxError, ValueError) as exc:
        raise ValueError(f'Invalid literal for {name}: {value}') from exc


def dist_corrcoef(image_1, image_2):
    """Return a distance between two images corresponding to 1 minus the
    correlation coefficient between them. This can go from 0 to 2."""

    dist = 0
    for x1, x2 in zip(image_1, image_2):
        flat_1 = x1.ravel()
        flat_2 = x2.ravel()
        if flat_1.size < 2 or flat_2.size < 2:
            corr = 0.0
        elif np.std(flat_1) == 0 or np.std(flat_2) == 0:
            corr = 1.0 if np.array_equal(flat_1, flat_2) else 0.0
        else:
            corr = np.corrcoef(flat_1, flat_2)[0, 1]
        dist += (1 - corr)/len(image_1)
    return dist


def get_thumbnail(dataset, filename, channel, t, scale):
    """Return low-resolution thumbnail of data volume."""

    v = get_slice(dataset, t, filename)
    if channel is not None:
        v = v[channel]
    elif len(v.shape) == 4:
        v = np.max(v, axis=0)
    tmg = []
    new_shape = np.array([max(1, l//s) for l, s in zip(v.shape, scale)])
    for d in range(len(v.shape)):
        mip = np.max(v, axis=d)
        tmg.append(resize(mip, np.delete(new_shape, d)))
    return tmg


def get_all_pdists(dataset, filename, shape_t, channel,
                   dist_fn=dist_corrcoef,
                   load=True, save=True,
                   scale=(4, 16, 16),
                   pbar=False
                   ) -> np.ndarray:
    """Return all pairwise distances between the first shape_t frames in a dataset."""

    f = dataset / 'null.npy'
    if load or save:
        if channel is not None:
            f = dataset / f'pdcc_c{channel}.npy'
        else:
            f = dataset / f'pdcc.npy'
    if f.is_file() and load:
        pdcc = np.load(str(f), allow_pickle=True)
        if pdcc.shape == (shape_t, shape_t):
            return pdcc

    thumbnails = []
    for t in tqdm(range(shape_t), desc='Compiling thumbnails from rf...', unit='frames', file=sys.stdout):
        thumbnails += [get_thumbnail(dataset, filename, channel, t, scale)]

    d = np.zeros((shape_t, shape_t))
    for i in (tqdm(range(shape_t), desc='Calculating distances', unit='frames', file=sys.stdout) if pbar else range(shape_t)):
        for j in range(i+1, shape_t):
            dist = dist_fn(thumbnails[i], thumbnails[j])
            if np.isnan(dist):
                d[i, j] = 2.0
            else:
                d[i, j] = dist

    d_full = d + np.transpose(d)
    if save:
        try:
            np.save(str(f), d_full, allow_pickle=True)
        except OSError as exc:
            print(
                f'Warning: unable to write distance cache {f}: {exc}. '
                'Continuing without cache.',
                file=sys.stderr,
            )

    return d_full


def frame_cache_path(dataset, filename, channel, t_list):
    """Return a cache path scoped to the exact candidate frame list."""

    suffix = hashlib.sha1(np.asarray(t_list, dtype=np.int64).tobytes()).hexdigest()[:12]
    prefix = f'{filename}_' if filename else ''
    channel_part = f'_c{channel}' if channel is not None else ''
    return dataset / f'{prefix}pdcc{channel_part}_frames_{len(t_list)}_{suffix}.npy'


def get_candidate_pdists(dataset, filename, t_list, channel,
                         dist_fn=dist_corrcoef,
                         load=True, save=True,
                         scale=(4, 16, 16),
                         pbar=False
                         ) -> np.ndarray:
    """Return pairwise distances only for the requested candidate frames."""

    t_list = [int(t) for t in t_list]
    cache_file = frame_cache_path(dataset, filename, channel, t_list)
    if load and cache_file.is_file():
        pdcc = np.load(str(cache_file), allow_pickle=True)
        if pdcc.shape == (len(t_list), len(t_list)):
            return pdcc

    thumbnails = []
    iterator = tqdm(t_list, desc='Compiling candidate thumbnails', unit='frames', file=sys.stdout)
    for t in iterator:
        thumbnails.append(get_thumbnail(dataset, filename, channel, t, scale))

    d = np.zeros((len(t_list), len(t_list)), dtype=np.float32)
    rows = tqdm(range(len(t_list)), desc='Calculating candidate distances', unit='frames', file=sys.stdout) if pbar else range(len(t_list))
    for i in rows:
        for j in range(i + 1, len(t_list)):
            dist = dist_fn(thumbnails[i], thumbnails[j])
            d[i, j] = 2.0 if np.isnan(dist) else dist

    d_full = d + np.transpose(d)
    if save:
        try:
            np.save(str(cache_file), d_full, allow_pickle=True)
        except OSError as exc:
            print(
                f'Warning: unable to write distance cache {cache_file}: {exc}. '
                'Continuing without cache.',
                file=sys.stderr,
            )
    return d_full


def get_partial_pdists(dataset, filename, shape_t, p_list, channel,
                       dist_fn=dist_corrcoef,
                       load=True,
                       scale=(4, 16, 16),
                       pbar=False
                       ) -> np.ndarray:
    """Return pairwise distances between shape_t frames and their parents in a dataset."""

    f = dataset / 'null.npy'
    if load:
        if channel is not None:
            f = dataset / f'pdcc_c{channel}.npy'
        else:
            f = dataset / f'pdcc.npy'
    d_full = None
    if f.is_file() and load:
        d_full = np.load(str(f), allow_pickle=True)

    print('Compiling thumbnails...')
    thumbnails = [get_thumbnail(dataset, filename, channel, t, scale) for t in range(shape_t)]

    d_partial = np.zeros(shape_t)
    for i in (tqdm(range(shape_t), desc='Calculating distances', unit='frames', file=sys.stdout) if pbar else range(shape_t)):

        if p_list[i] < 0:
            continue

        if d_full is not None and d_full.shape[1] > int(p_list[i]):
            d_partial[i] = d_full[i, int(p_list[i])]
        else:
            dist = dist_fn(thumbnails[i], thumbnails[int(p_list[i])])
            if np.isnan(dist):
                d_partial[i] = 2.0
            else:
                d_partial[i] = dist

    return d_partial


def recommend_frames(dataset, filename, n_frames, n_iter, t_list, channel, metadata, save_to_metadata, verbose, max_candidate_frames):

    if str(dataset)[-1] == '"':
        dataset = Path(str(dataset)[:-1])
    if str(dataset)[0] == '"':
        dataset = Path(str(dataset)[1:])

    shape_t = metadata['shape_t']
    if t_list is None:
        if shape_t > max_candidate_frames:
            t_list = np.unique(np.linspace(0, shape_t - 1, max_candidate_frames, dtype=int)).tolist()
            print(
                f'Using {len(t_list)} evenly spaced candidate frames out of {shape_t}. '
                'Pass --t_list to override.',
                flush=True,
            )
        else:
            t_list = list(range(shape_t))
    t_list = [int(t) for t in t_list]
    if not t_list:
        raise ValueError('No candidate frames were provided for reference-frame selection.')
    if min(t_list) < 0 or max(t_list) >= shape_t:
        raise ValueError(f'Candidate frames must be in [0, {shape_t - 1}], got range [{min(t_list)}, {max(t_list)}].')
    n_frames = min(n_frames, len(t_list))

    print('Building frame correlation graph...')
    d_slice = get_candidate_pdists(dataset, filename, t_list, channel, pbar=True)

    scores = np.mean(d_slice, axis=-1)
    opt_score, med_idx = np.min(scores), np.argmin(scores)

    i_ref = [med_idx]
    t_ref = [t_list[med_idx]]
    s_ref = [opt_score]
    scores = d_slice[med_idx, :]
    pbar = tqdm(range(n_frames - 1), desc='Optimizing reference frames', unit='n_frames', leave=False, file=sys.stdout)
    for i in pbar:
        d_adj = np.append(
            d_slice.copy()[:, :, None],
            np.tile(scores[None, :, None], (d_slice.shape[0], 1, 1)),
            axis=-1
        )
        d_opt = np.min(d_adj, axis=-1)
        iscores = np.mean(d_opt, axis=-1)
        iscores[i_ref] = np.inf
        opt_score, new_midx = np.min(iscores), np.argmin(iscores)

        i_ref.append(new_midx)
        t_ref.append(t_list[new_midx])
        s_ref.append(opt_score)
        scores = d_opt[new_midx, :]

    print(f'\nIterating over found reference frames...')
    n_i = 0
    while True:
        if 0 <= n_iter <= n_i:
            break
        kscore = opt_score
        for i in range(n_frames):
            i_ref_temp = i_ref.copy()
            i_ref_temp.pop(i)
            d_adj = d_slice.copy()[:, :, None]
            for t in i_ref_temp:
                d_adj = np.append(
                    d_adj,
                    np.tile(d_slice.copy()[t, None, :, None],
                            (d_adj.shape[0], 1, 1)),
                    axis=-1
                )

            iscores = np.mean(np.min(d_adj, axis=-1), axis=-1)
            iscores[i_ref_temp] = np.inf
            jscore, new_midx = np.min(iscores), np.argmin(iscores)

            if jscore < kscore:
                i_ref[i] = new_midx
                t_ref[i] = t_list[new_midx]
                kscore = jscore

        if kscore < opt_score:
            opt_score = kscore
            n_i += 1
        else:
            break

    if save_to_metadata:
        update_metadata(dataset, {f't_ref_fn{len(t_list)}': [int(i) for i in t_ref]})

    return t_ref


def main():
    args = docopt(__doc__, version=f'ZephIR recommend_frames {__version__}')
    dataset_arg = Path(args['--dataset'])
    if dataset_arg.is_dir():
        dataset = dataset_arg
        filename = None
    else:
        dataset = dataset_arg.parent
        filename = dataset_arg.name

    metadata_dict = {
        'shape_x': int(args['--nx']),
        'shape_y': int(args['--ny']),
        'shape_z': int(args['--nz']),
        'shape_c': int(args['--nc']),
        'shape_t': int(args['--nt'])
    }

    t_ref = recommend_frames(
        dataset=dataset,
        filename=filename,
        n_frames=int(args['--n_frames']),
        n_iter=int(args['--n_iter']),
        t_list=parse_literal_arg(args['--t_list'], '--t_list') if args['--t_list'] else None,
        channel=int(args['--channel']) if args['--channel'] else None,
        metadata=metadata_dict,
        save_to_metadata=args['--save_to_metadata'] in ['True', 'Y', 'y'],
        verbose=args['--verbose'] in ['True', 'Y', 'y'],
        max_candidate_frames=int(args['--max_candidate_frames']),
    )

    return t_ref


if __name__ == '__main__':
    t_ref = main()
    t_ref.sort()
    print(t_ref, flush=True)
