#!/usr/bin/env python3
"""Stage app-resident NeuroPAL data as a minimal NWB for transformer inference."""

from __future__ import annotations

import argparse
import os
from datetime import datetime

import numpy as np
import pandas as pd
import scipy.io as sio
from dateutil.tz import tzlocal
from ndx_multichannel_volume import (
    CElegansSubject,
    ImagingVolume,
    MultiChannelVolume,
    OpticalChannelPlus,
    OpticalChannelReferences,
)
from pynwb import NWBFile, NWBHDF5IO
from pynwb.ophys import ImageSegmentation


def _load_request(path: str) -> dict:
    return sio.loadmat(path, squeeze_me=True, struct_as_record=False)


def _as_array(value, dtype=None) -> np.ndarray:
    arr = np.asarray(value)
    if dtype is not None:
        arr = arr.astype(dtype)
    return arr


def _labels(value, n: int) -> list[str]:
    if value is None:
        return [""] * n
    arr = np.asarray(value, dtype=object).reshape(-1)
    labels = []
    for item in arr[:n]:
        if isinstance(item, np.ndarray):
            item = item.item() if item.size == 1 else "".join(map(str, item.ravel()))
        text = str(item).strip()
        if text.lower() in {"nan", "none", "<missing>"}:
            text = ""
        labels.append(text)
    labels.extend([""] * max(0, n - len(labels)))
    return labels


def _ensure_four_channels(volume_yxzc: np.ndarray) -> np.ndarray:
    if volume_yxzc.ndim != 4:
        raise ValueError(f"Expected volume [Y,X,Z,C], got shape {volume_yxzc.shape}")
    n_channels = volume_yxzc.shape[3]
    if n_channels < 1:
        raise ValueError("Volume has no channels")
    if n_channels >= 4:
        return volume_yxzc[:, :, :, :4]
    pad_shape = (*volume_yxzc.shape[:3], 4 - n_channels)
    pad = np.zeros(pad_shape, dtype=volume_yxzc.dtype)
    return np.concatenate([volume_yxzc, pad], axis=3)


def _make_channel(name: str) -> OpticalChannelPlus:
    return OpticalChannelPlus(
        name=name,
        description=name,
        excitation_lambda=500.0,
        excitation_range=[400.0, 650.0],
        emission_lambda=600.0,
        emission_range=[450.0, 750.0],
    )


def write_minimal_nwb(request: dict) -> str:
    output_path = str(np.asarray(request["output_path"]).item())
    volume_yxzc = _ensure_four_channels(_as_array(request["volume"]))
    positions_yxz = _as_array(request["positions_yxz"], np.float32)
    if positions_yxz.ndim == 1:
        positions_yxz = positions_yxz.reshape(1, -1)
    positions_yxz = positions_yxz[:, :3]
    scale = _as_array(request.get("scale_um_xyz", [1.0, 1.0, 1.0]), np.float32).reshape(-1)
    if scale.size < 3:
        scale = np.pad(scale, (0, 3 - scale.size), constant_values=1.0)
    labels = _labels(request.get("labels"), positions_yxz.shape[0])

    # App data is [Y, X, Z, C].  The GAT 000981 config expects raw NWB data
    # in [C, Z, X, Y], then transposes it to canonical [C, Z, Y, X].
    volume_czxy = np.transpose(volume_yxzc, (3, 2, 1, 0))

    nwb = NWBFile(
        session_description="Temporary NeuroPAL transformer staging file",
        identifier=os.path.splitext(os.path.basename(output_path))[0],
        session_start_time=datetime.now(tzlocal()),
        lab="NeuroPAL_ID",
        institution="NeuroPAL_ID",
    )
    nwb.subject = CElegansSubject(
        subject_id="neuropal_app",
        date_of_birth=datetime.now(tzlocal()),
        growth_stage="Adult",
        growth_stage_time=pd.Timedelta(hours=0).isoformat(),
        cultivation_temp=20.0,
        description="Temporary app-resident NeuroPAL volume",
        species="http://purl.obolibrary.org/obo/NCBITaxon_6239",
        sex="O",
        strain="",
    )

    device = nwb.create_device(
        name="Microscope",
        description="Temporary NeuroPAL_ID device",
        manufacturer="NeuroPAL_ID",
    )
    channels = [_make_channel(name) for name in ("R", "G", "B", "W")]
    channel_refs = OpticalChannelReferences(
        name="order_optical_channels",
        channels=["R", "G", "B", "W"],
    )
    imaging_volume = ImagingVolume(
        name="NeuroPALImVol",
        optical_channel_plus=channels,
        order_optical_channels=channel_refs,
        description="Temporary NeuroPAL image volume",
        device=device,
        location="head",
        grid_spacing=[float(scale[0]), float(scale[1]), float(scale[2])],
        grid_spacing_unit="micrometer",
        origin_coords=[0.0, 0.0, 0.0],
        origin_coords_unit="micrometer",
        reference_frame="worm",
    )
    nwb.add_imaging_plane(imaging_volume)

    image = MultiChannelVolume(
        name="NeuroPALImageRaw",
        description="Temporary app-resident raw NeuroPAL volume",
        RGBW_channels=[0, 1, 2, 3],
        data=volume_czxy,
        imaging_volume=imaging_volume,
    )
    nwb.add_acquisition(image)

    module = nwb.create_processing_module(
        name="NeuroPAL",
        description="Temporary NeuroPAL segmentation for transformer inference",
    )
    segmentation = ImageSegmentation(name="NeuroPALSegmentation")
    plane_seg = segmentation.create_plane_segmentation(
        name="NeuroPALNeurons",
        description="Segmentation of NeuroPAL volume. IDs found in NeuroPALNeurons.",
        imaging_plane=imaging_volume,
    )
    plane_seg.add_column("ID_labels", "Neuron ID labels from segmentation image mask.")

    y_max, x_max, z_max = volume_yxzc.shape[:3]
    for row, label in zip(positions_yxz, labels):
        y = int(np.clip(round(float(row[0])), 1, y_max)) - 1
        x = int(np.clip(round(float(row[1])), 1, x_max)) - 1
        z = int(np.clip(round(float(row[2])), 1, z_max)) - 1
        plane_seg.add_roi(
            voxel_mask=[(float(x), float(y), float(z), 1.0)],
            ID_labels=label,
        )

    module.add(segmentation)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with NWBHDF5IO(output_path, "w") as io:
        io.write(nwb)
    print(f"NEUROPAL_PROGRESS: Staged temporary NWB with {positions_yxz.shape[0]} neurons.")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    write_minimal_nwb(_load_request(args.request))


if __name__ == "__main__":
    main()
