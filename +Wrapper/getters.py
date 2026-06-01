"""
To ease the pain of ensuring compatibility with new data structures or datasets,
this file collects key IO functions for data, metadata, and annotations
that may be edited by a user to fit their particular use case.
"""

import h5py
import json
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Optional
from pynwb import NWBHDF5IO
from pims import ND2_Reader

nwbfile = None
nd2file = None

# default getters
def get_slice(dataset: Path, t: int, filename: Optional[str] = None) -> np.ndarray:
    """Return a slice at specified index t.
    This should return a 4-D numpy array containing multi-channel volumetric data
    with the dimensions ordered as (C, Z, Y, X).
    """
    global nwbfile
    global nd2file

    if filename is None or filename is False or str(filename) == "":
        filename = dataset / "data.h5"
    else:
        filename = Path(filename)
        if not filename.is_absolute():
            filename = dataset / filename

    if filename.suffix == '.h5':
        is_data_layout = False
        with h5py.File(filename, 'r') as f:
            if "data" in f:
                is_data_layout = True
                frame = f["data"][t]
            elif f"t{t}" in f:
                t_group = f[f"t{t}"]
                channel_keys = sorted(
                    [key for key in t_group.keys() if key.startswith("c")],
                    key=lambda key: int(key[1:]),
                )
                if not channel_keys:
                    raise KeyError(f"Grouped H5 frame /t{t} has no c* channel datasets.")
                frame = np.stack([np.asarray(t_group[key]) for key in channel_keys], axis=0)
                # ASCENT grouped H5 stores each channel volume as [Z, Y, X],
                # which is already ZephIR's expected [C, Z, Y, X] after stacking.
            else:
                raise KeyError(
                    f"Unsupported H5 structure in {filename}: expected /data or /t{t}/c*."
                )
        if is_data_layout and frame.ndim == 4:
            # MATLAB writes /data as [Y X Z C T], which h5py exposes as
            # [T C Z X Y]. Native ZephIR H5 is commonly [T C Z Y X].
            # Use metadata when available so both layouts return [C Z Y X].
            try:
                metadata = get_metadata(dataset)
                expected_zyx = (
                    metadata["shape_c"],
                    metadata["shape_z"],
                    metadata["shape_y"],
                    metadata["shape_x"],
                )
                expected_zxy = (
                    metadata["shape_c"],
                    metadata["shape_z"],
                    metadata["shape_x"],
                    metadata["shape_y"],
                )
            except (FileNotFoundError, KeyError, json.JSONDecodeError):
                expected_zyx = None
                expected_zxy = None

            if expected_zyx is not None and tuple(frame.shape) == expected_zyx:
                pass
            elif expected_zxy is None or tuple(frame.shape) == expected_zxy:
                frame = np.transpose(frame, [0, 1, 3, 2])
            else:
                raise ValueError(
                    f"Unsupported H5 frame shape {frame.shape}; expected "
                    f"{expected_zyx} or {expected_zxy} from metadata."
                )
    elif filename.suffix == '.nwb':
        if nwbfile is None:
            io = NWBHDF5IO(filename, mode="r")
            nwbfile = io.read()

        if 'CalciumImageSeries' in nwbfile.acquisition.keys():
            targ_mod = nwbfile.acquisition['CalciumImageSeries']
        else:
            for eachKey in nwbfile.acquisition.keys():
                if 'Calcium' in eachKey:
                    targ_mod = nwbfile.acquisition[eachKey]

        if 'targ_mod' not in locals():
            raise KeyError(f"Unable to find any Calcium key in {filename} acquisition module.")

        frame = targ_mod.data[t, :, :, :, :]
        frame = np.transpose(frame, [3, 2, 1, 0])

    elif filename.suffix == '.nd2':
        if nd2file is None:
            try:
                nd2file = ND2_Reader(filename)
            except ImportError as exc:
                raise ImportError(
                    "Python ND2 reading requires pims_nd2, which is not "
                    "installed in this environment. Convert the video to the "
                    "chunked HDF5 data.h5 format before running ZephIR "
                    "tracking/recommendation/extraction."
                ) from exc

        if 't' in nd2file.sizes:
            nd2file.bundle_axes = ['c', 'z', 'y', 'x']
            frame = np.asarray(nd2file[t])
        else:
            raise KeyError(f"Unable to find time dimension in {filename}.")
    else:
        raise ValueError(f"Unsupported video file type: {filename.suffix}")

    return frame


def get_annotation_df(dataset: Path) -> pd.DataFrame:
    """Load and return annotations as an ordered pandas dataframe.
    This should contain the following:
    - t_idx: time index of each annotation
    - x: x-coordinate as a float between (0, 1)
    - y: y-coordinate as a float between (0, 1)
    - z: z-coordinate as a float between (0, 1)
    - worldline_id: track or worldline ID as an integer
    - provenance: scorer or creator of the annotation as a byte string
    """
    with h5py.File(dataset / 'annotations.h5', 'r') as f:
        data = pd.DataFrame()
        for k in f:
            data[k] = f[k]
    return data


def get_metadata(dataset: Path) -> dict:
    """Load and return metadata for the dataset as a Python dictionary.
    This should contain at least the following:
    - shape_t
    - shape_c
    - shape_z
    - shape_y
    - shape_x
    """
    json_filename = dataset / "metadata.json"
    with open(json_filename) as json_file:
        metadata = json.load(json_file)
    return metadata
