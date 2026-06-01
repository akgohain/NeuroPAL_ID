#!/usr/bin/env python3
"""Convert ASCENT/Zenodo C. elegans tracking data for NeuroPAL_ID ZephIR UI.

The target dataset folder is the ZephIR-style layout used by this app:

    dataset/
      data.h5          # optional, /data as [T, C, Z, X, Y] for +Wrapper/getters.py
      metadata.json    # optional, shape_x/shape_y/shape_z/shape_c/shape_t
      annotations.h5   # /t_idx, /x, /y, /z, /worldline_id, /parent_id, /provenance
      worldlines.h5    # /id, /name, /color

Coordinates in annotations.h5 are normalized to [0, 1], matching ZephIR.
"""

from __future__ import annotations

import argparse
import colorsys
import json
import re
from pathlib import Path
from typing import Iterable

import h5py
import numpy as np
import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert ASCENT/Zenodo tracks and optional raw H5 video to NeuroPAL_ID ZephIR layout."
    )
    parser.add_argument("--coords-csv", required=True, type=Path, help="CSV with per-frame point coordinates.")
    parser.add_argument("--tracks-csv", type=Path, help="Optional CSV with track/worldline metadata.")
    parser.add_argument("--source-h5", type=Path, help="Optional raw video H5 to convert to data.h5.")
    parser.add_argument("--output-dir", required=True, type=Path, help="Output dataset folder.")
    parser.add_argument("--metadata", type=Path, help="Existing metadata.json to use for dimensions.")
    parser.add_argument("--shape-x", type=int, help="X dimension override for annotation-only conversion.")
    parser.add_argument("--shape-y", type=int, help="Y dimension override for annotation-only conversion.")
    parser.add_argument("--shape-z", type=int, help="Z dimension override for annotation-only conversion.")
    parser.add_argument("--shape-t", type=int, help="Time dimension override for metadata output.")
    parser.add_argument("--shape-c", type=int, help="Channel dimension override for metadata output.")
    parser.add_argument(
        "--source-layout",
        choices=("auto", "grouped-tc", "TCZYX", "TCZXY"),
        default="auto",
        help="Raw H5 layout. ASCENT-style grouped t*/c* is auto-detected.",
    )
    parser.add_argument(
        "--coord-space",
        choices=("auto", "pixel", "normalized"),
        default="auto",
        help="Coordinate space for the CSV coordinates.",
    )
    parser.add_argument("--x-column", help="Override x coordinate column.")
    parser.add_argument("--y-column", help="Override y coordinate column.")
    parser.add_argument("--z-column", help="Override z coordinate column.")
    parser.add_argument("--frame-column", help="Override frame/time column.")
    parser.add_argument("--track-column", help="Override track/worldline id column.")
    parser.add_argument("--name-column", help="Override worldline name column.")
    parser.add_argument("--provenance", default="GT", help="Annotation provenance string.")
    return parser.parse_args()


def clean_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value).lower())


def find_column(df: pd.DataFrame, explicit: str | None, candidates: Iterable[str]) -> str:
    if explicit:
        if explicit not in df.columns:
            raise KeyError(f"Requested column {explicit!r} is not present. Available: {list(df.columns)}")
        return explicit

    by_clean = {clean_key(col): col for col in df.columns}
    for candidate in candidates:
        match = by_clean.get(clean_key(candidate))
        if match is not None:
            return match
    raise KeyError(f"Unable to find one of {list(candidates)}. Available columns: {list(df.columns)}")


def optional_column(df: pd.DataFrame, explicit: str | None, candidates: Iterable[str]) -> str | None:
    try:
        return find_column(df, explicit, candidates)
    except KeyError:
        return None


def read_metadata(path: Path | None) -> dict:
    if not path:
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def h5_string_array(values: Iterable[str]) -> np.ndarray:
    return np.asarray([str(value).encode("utf-8") for value in values])


def write_vector(handle: h5py.File, name: str, values: np.ndarray) -> None:
    if name in handle:
        del handle[name]
    handle.create_dataset(name, data=values)


def deterministic_color(index: int, total: int) -> str:
    hue = (index / max(total, 1)) % 1.0
    red, green, blue = colorsys.hsv_to_rgb(hue, 0.65, 0.9)
    return f"#{round(red * 255):02x}{round(green * 255):02x}{round(blue * 255):02x}"


def sorted_tc_keys(keys: Iterable[str]) -> list[str]:
    def key_value(key: str) -> tuple[int, str]:
        match = re.search(r"(\d+)$", key)
        return (int(match.group(1)) if match else 10**9, key)

    return sorted(keys, key=key_value)


def infer_h5_layout(handle: h5py.File, requested: str) -> str:
    if requested != "auto":
        return requested
    if "data" in handle and getattr(handle["data"], "ndim", None) == 5:
        return "TCZXY"
    t_keys = [key for key in handle.keys() if re.match(r"^t\d+$", key)]
    if t_keys:
        return "grouped-tc"
    raise ValueError("Unable to infer H5 layout. Use --source-layout explicitly.")


def convert_source_h5(source_h5: Path, output_dir: Path, metadata: dict, source_layout: str) -> dict:
    output_h5 = output_dir / "data.h5"
    with h5py.File(source_h5, "r") as src:
        layout = infer_h5_layout(src, source_layout)
        if layout == "grouped-tc":
            t_keys = sorted_tc_keys(key for key in src.keys() if re.match(r"^t\d+$", key))
            c_keys = sorted_tc_keys(src[t_keys[0]].keys())
            first = np.asarray(src[t_keys[0]][c_keys[0]])
            if first.ndim != 3:
                raise ValueError(f"Expected grouped t*/c* volumes to be 3-D, got {first.shape}.")
            shape_t, shape_c = len(t_keys), len(c_keys)
            shape_z, shape_y, shape_x = first.shape

            with h5py.File(output_h5, "w") as dst:
                data = dst.create_dataset(
                    "data",
                    shape=(shape_t, shape_c, shape_z, shape_x, shape_y),
                    dtype=first.dtype,
                    chunks=(1, shape_c, shape_z, shape_x, shape_y),
                    compression="gzip",
                )
                for t_idx, t_key in enumerate(t_keys):
                    for c_idx, c_key in enumerate(c_keys):
                        data[t_idx, c_idx] = np.transpose(np.asarray(src[t_key][c_key]), (0, 2, 1))

        else:
            if "data" not in src:
                raise KeyError("Source H5 does not contain /data.")
            raw = src["data"]
            if raw.ndim != 5:
                raise ValueError(f"Expected /data to be 5-D, got {raw.shape}.")
            shape_t, shape_c, shape_z = raw.shape[:3]
            if layout == "TCZYX":
                _, _, _, shape_y, shape_x = raw.shape
            else:
                _, _, _, shape_x, shape_y = raw.shape

            with h5py.File(output_h5, "w") as dst:
                data = dst.create_dataset(
                    "data",
                    shape=(shape_t, shape_c, shape_z, shape_x, shape_y),
                    dtype=raw.dtype,
                    chunks=(1, shape_c, shape_z, shape_x, shape_y),
                    compression="gzip",
                )
                for t_idx in range(shape_t):
                    frame = np.asarray(raw[t_idx])
                    if layout == "TCZYX":
                        frame = np.transpose(frame, (0, 1, 3, 2))
                    data[t_idx] = frame

    metadata.update(
        {
            "shape_t": int(shape_t),
            "shape_c": int(shape_c),
            "shape_z": int(shape_z),
            "shape_y": int(shape_y),
            "shape_x": int(shape_x),
        }
    )
    return metadata


def infer_dims(coords: pd.DataFrame, metadata: dict, x_col: str, y_col: str, z_col: str) -> dict:
    dims = dict(metadata)
    if {"shape_x", "shape_y", "shape_z"}.issubset(dims):
        return dims

    # Fallback for annotation-only conversion. These inferred dimensions are
    # enough to normalize pixel-space coordinates, but real metadata is better.
    dims.setdefault("shape_x", int(np.ceil(coords[x_col].max())))
    dims.setdefault("shape_y", int(np.ceil(coords[y_col].max())))
    dims.setdefault("shape_z", int(np.ceil(coords[z_col].max())))
    dims.setdefault("shape_t", int(np.ceil(coords.shape[0])))
    dims.setdefault("shape_c", 1)
    return dims


def normalize_coordinate(values: pd.Series, dim: int, coord_space: str) -> np.ndarray:
    numeric = pd.to_numeric(values, errors="coerce").to_numpy(dtype=np.float64)
    if np.isnan(numeric).any():
        raise ValueError(f"Coordinate column {values.name!r} contains non-numeric values.")

    use_normalized = coord_space == "normalized" or (coord_space == "auto" and np.nanmax(numeric) <= 1.0)
    if use_normalized:
        normalized = numeric
    else:
        normalized = (numeric - 0.5) / float(dim)
    eps = np.finfo(np.float32).eps
    return np.clip(normalized, eps, 1.0 - eps).astype(np.float32)


def zero_based_frames(values: pd.Series) -> np.ndarray:
    frames = pd.to_numeric(values, errors="coerce").to_numpy(dtype=np.float64)
    if np.isnan(frames).any():
        raise ValueError(f"Frame column {values.name!r} contains non-numeric values.")
    frames = np.round(frames).astype(np.int64)
    if frames.size and frames.min() >= 1:
        frames = frames - 1
    return frames.astype(np.uint32)


def build_name_map(
    coords: pd.DataFrame,
    tracks_csv: Path | None,
    track_col: str,
    name_col: str | None,
    args: argparse.Namespace,
) -> dict:
    name_map: dict[object, str] = {}
    if tracks_csv and tracks_csv.exists():
        tracks = pd.read_csv(tracks_csv)
        tracks_track_col = optional_column(
            tracks,
            args.track_column,
            ("TrackID", "track_id", "worldline_id", "neuron_id", "id", "label"),
        )
        tracks_name_col = optional_column(
            tracks,
            args.name_column,
            ("Name", "name", "neuron", "neuron_name", "label", "worldline"),
        )
        if tracks_track_col and tracks_name_col:
            for _, row in tracks[[tracks_track_col, tracks_name_col]].dropna().iterrows():
                name_map[row[tracks_track_col]] = str(row[tracks_name_col])

    if name_col:
        for _, row in coords[[track_col, name_col]].dropna().iterrows():
            name_map.setdefault(row[track_col], str(row[name_col]))
    return name_map


def convert_annotations(args: argparse.Namespace, metadata: dict) -> None:
    coords = pd.read_csv(args.coords_csv)
    frame_col = find_column(coords, args.frame_column, ("Frame", "t_idx", "t", "time", "Time"))
    track_col = find_column(
        coords,
        args.track_column,
        ("TrackID", "track_id", "worldline_id", "neuron_id", "id", "label", "Label"),
    )
    x_col = find_column(coords, args.x_column, ("X", "x", "x_px", "x_pixel", "centroid_x"))
    y_col = find_column(coords, args.y_column, ("Y", "y", "y_px", "y_pixel", "centroid_y"))
    z_col = find_column(coords, args.z_column, ("Z", "z", "z_px", "z_slice", "centroid_z"))
    name_col = optional_column(coords, args.name_column, ("Name", "name", "neuron", "neuron_name", "worldline"))

    metadata = infer_dims(coords, metadata, x_col, y_col, z_col)
    valid = coords[[frame_col, track_col, x_col, y_col, z_col]].dropna().copy()
    valid = valid.sort_values([track_col, frame_col], kind="stable")

    track_values = list(pd.unique(valid[track_col]))
    track_to_id = {track: idx for idx, track in enumerate(track_values)}
    name_map = build_name_map(coords, args.tracks_csv, track_col, name_col, args)
    names = [name_map.get(track, f"Track {track}") for track in track_values]
    colors = [deterministic_color(idx, len(track_values)) for idx in range(len(track_values))]

    annotations_file = args.output_dir / "annotations.h5"
    worldlines_file = args.output_dir / "worldlines.h5"

    worldline_ids = valid[track_col].map(track_to_id).to_numpy(dtype=np.uint32)
    with h5py.File(annotations_file, "w") as handle:
        write_vector(handle, "id", np.arange(1, len(valid) + 1, dtype=np.uint32))
        write_vector(handle, "t_idx", zero_based_frames(valid[frame_col]))
        write_vector(handle, "x", normalize_coordinate(valid[x_col], int(metadata["shape_x"]), args.coord_space))
        write_vector(handle, "y", normalize_coordinate(valid[y_col], int(metadata["shape_y"]), args.coord_space))
        write_vector(handle, "z", normalize_coordinate(valid[z_col], int(metadata["shape_z"]), args.coord_space))
        write_vector(handle, "worldline_id", worldline_ids)
        write_vector(handle, "parent_id", np.zeros(len(valid), dtype=np.uint32))
        write_vector(handle, "provenance", h5_string_array([args.provenance] * len(valid)))

    with h5py.File(worldlines_file, "w") as handle:
        write_vector(handle, "id", np.arange(0, len(track_values), dtype=np.uint32))
        write_vector(handle, "name", h5_string_array(names))
        write_vector(handle, "color", h5_string_array(colors))

    print(f"Wrote {annotations_file} with {len(valid)} annotations across {len(track_values)} worldlines.")
    print(f"Wrote {worldlines_file}.")


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    metadata = read_metadata(args.metadata)
    for key in ("shape_x", "shape_y", "shape_z", "shape_t", "shape_c"):
        value = getattr(args, key.replace("shape_", "shape_"))
        if value is not None:
            metadata[key] = int(value)

    if args.source_h5:
        metadata = convert_source_h5(args.source_h5, args.output_dir, metadata, args.source_layout)

    if {"shape_x", "shape_y", "shape_z", "shape_t", "shape_c"}.issubset(metadata):
        metadata_file = args.output_dir / "metadata.json"
        with metadata_file.open("w", encoding="utf-8") as handle:
            json.dump(metadata, handle, indent=2, sort_keys=True)
        print(f"Wrote {metadata_file}.")

    convert_annotations(args, metadata)


if __name__ == "__main__":
    main()
