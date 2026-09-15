#!/usr/bin/env python3
"""Keep a bounded H5 frame reader alive for the MATLAB viewer."""
import argparse
import json
import os
from pathlib import Path
import time

import h5py
import numpy as np

from reference_video import source_info


def publish(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def serve(directory, parent):
    directory = Path(directory)
    request = json.loads((directory / 'source.json').read_text())
    info = source_info(request['file'])
    if info['source_id'] != request['source_id']:
        raise ValueError('Recording changed. Reopen the source before browsing.')
    stat = Path(info['file']).stat()
    identity = (stat.st_size, stat.st_mtime_ns)
    with h5py.File(info['file'], 'r', rdcc_nbytes=2**20) as source:
        publish(directory / 'ready.json', {'ready': True})
        while os.getppid() == parent and not (directory / 'stop').exists():
            path = directory / 'request.json'
            if not path.exists():
                time.sleep(.005)
                continue
            message = json.loads(path.read_text())
            path.unlink()
            try:
                stat = Path(info['file']).stat()
                if (stat.st_size, stat.st_mtime_ns) != identity:
                    raise ValueError('Recording changed. Reopen the source before browsing.')
                frame = message['frame']
                if not isinstance(frame, int) or not 0 <= frame < info['nt']:
                    raise ValueError('Frame index is outside recording')
                raw = source['data'][frame]
                if info['axis_order'] == 'TCZXY':
                    raw = raw.transpose(0, 1, 3, 2)
                if not np.isfinite(raw).all():
                    raise ValueError('Selected frame contains nonfinite values')
                # MATLAB receives YXZC in column-major order, including singleton axes.
                raw.transpose(2, 3, 1, 0).ravel(order='F').tofile(directory / 'frame.bin')
                del raw
                publish(directory / 'response.json', {'sequence': message['sequence']})
            except Exception as error:
                publish(directory / 'response.json', {'sequence': message['sequence'], 'error': str(error)})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    parser.add_argument('--parent', required=True, type=int)
    args = parser.parse_args()
    try:
        serve(args.directory, args.parent)
    except Exception as error:
        publish(Path(args.directory) / 'ready.json', {'error': str(error)})
        raise
