import json
import math
import os
import shutil
import sys

import h5py
import numpy as np
from czifile import CziFile


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _to_float(value, default=float("nan")):
    try:
        return float(value)
    except Exception:
        return default


def _channel_color(channel):
    color = str(channel.get("Color", ""))
    if len(color) >= 7:
        color = color[-6:]
        try:
            return [
                int(color[0:2], 16),
                int(color[2:4], 16),
                int(color[4:6], 16),
            ]
        except Exception:
            pass
    return [255, 255, 255]


def _channel_name(channel, index):
    return str(
        channel.get("Name")
        or channel.get("Fluor")
        or channel.get("Id")
        or f"Channel {index + 1}"
    )


def _channel_is_dic(channel):
    name_fields = " ".join(
        str(channel.get(key, "")) for key in ("Name", "Fluor", "ContrastMethod")
    ).lower()
    return any(token in name_fields for token in ("dic", "nomarski", "phase", "pmt"))


def _channel_excitation(channel):
    if "ExcitationWavelength" in channel:
        return _to_float(channel["ExcitationWavelength"])

    settings = channel.get("LightSourcesSettings", {}).get("LightSourceSettings")
    settings_list = _as_list(settings)
    if settings_list:
        return _to_float(settings_list[0].get("Wavelength"))

    return float("nan")


def _channel_emission(channel):
    ranges = channel.get("DetectionWavelength", {}).get("Ranges")
    if ranges:
        try:
            low, high = [float(part) for part in str(ranges).split("-", 1)]
            return [low, high]
        except Exception:
            pass

    emission = channel.get("EmissionWavelength")
    if emission is not None:
        peak = _to_float(emission)
        return [peak, peak]

    return [float("nan"), float("nan")]


def _extract_scale(metadata):
    distances = (
        metadata.get("ImageDocument", {})
        .get("Metadata", {})
        .get("Scaling", {})
        .get("Items", {})
        .get("Distance", [])
    )
    scale = {"X": float("nan"), "Y": float("nan"), "Z": float("nan")}
    for item in _as_list(distances):
        axis = str(item.get("Id", "")).upper()
        if axis in scale:
            scale[axis] = _to_float(item.get("Value"))
    return [scale["X"], scale["Y"], scale["Z"]]


def _normalize_axes(array, axes):
    squeezed_axes = "".join(axis for axis, size in zip(axes, array.shape) if size != 1)
    data = np.squeeze(array)

    for required_axis in ("X", "Y"):
        if required_axis not in squeezed_axes:
            raise RuntimeError(f"CZI data missing required axis {required_axis}")

    extra_axes = [axis for axis in squeezed_axes if axis not in "XYZC"]
    if extra_axes:
        raise RuntimeError(
            "Unsupported non-singleton CZI axes after squeeze: "
            + ",".join(extra_axes)
        )

    if "Z" not in squeezed_axes:
        data = np.expand_dims(data, axis=0)
        squeezed_axes = "Z" + squeezed_axes

    if "C" not in squeezed_axes:
        data = np.expand_dims(data, axis=0)
        squeezed_axes = "C" + squeezed_axes

    axis_order = [squeezed_axes.index(axis) for axis in "XYZC"]
    return np.transpose(data, axis_order)


def _check_size(czi):
    try:
        limit = float(os.environ.get("NEUROPAL_IMAGE_MAX_MIB", "512"))
    except ValueError:
        limit = 512
    if not math.isfinite(limit) or limit <= 0 or not math.isfinite(limit * 1024**2):
        limit = 512
    axes = czi.axes
    shape = czi.shape
    if len(axes) != len(shape) or len(set(axes)) != len(axes):
        raise RuntimeError("Unsupported CZI dimensions")
    if any(size != 1 and axis not in "XYZC" for axis, size in zip(axes, shape)):
        raise RuntimeError("Static image import requires a single time point and scene")
    if any(axis not in axes for axis in "XY"):
        raise RuntimeError("CZI data missing X or Y axis")
    size = math.prod(shape) * np.dtype(czi.dtype).itemsize
    if size > max(1, math.floor(limit * 1024**2)):
        raise RuntimeError(
            f"CZI decoded image requires {size / 1024**2:.1f} MiB, above the "
            f"{limit:.1f} MiB loading limit (NEUROPAL_IMAGE_MAX_MIB). "
            "Create a smaller source before importing."
        )
    return size


def convert(input_path, output_h5, output_json):
    with CziFile(input_path) as czi:
        size = _check_size(czi)
        metadata = czi.metadata(raw=False)
        directory = os.path.dirname(os.path.abspath(output_h5))
        if shutil.disk_usage(directory).free < size * 2 + 64 * 1024**2:
            raise RuntimeError("Insufficient temporary disk space for CZI conversion")

        # Decode subblocks sequentially into a disk-backed image.
        scratch = str(output_h5) + ".pixels"
        try:
            raw = czi.asarray(out=scratch, max_workers=1)
            try:
                data = _normalize_axes(raw, czi.axes)
                shape = data.shape
                with h5py.File(output_h5, "w") as handle:
                    dataset = handle.create_dataset(
                        "data", shape=shape, dtype=data.dtype,
                        chunks=(min(shape[0], 256), min(shape[1], 256), 1, 1),
                        compression="gzip",
                    )
                    for c in range(shape[3]):
                        for z in range(shape[2]):
                            dataset[:, :, z, c] = data[:, :, z, c]
                del data
            finally:
                raw._mmap.close()
        finally:
            if os.path.exists(scratch):
                os.unlink(scratch)

    channels = (
        metadata.get("ImageDocument", {})
        .get("Metadata", {})
        .get("Information", {})
        .get("Image", {})
        .get("Dimensions", {})
        .get("Channels", {})
        .get("Channel", [])
    )
    channels = _as_list(channels)

    payload = {
        "pixels": [int(shape[0]), int(shape[1]), int(shape[2])],
        "scale": _extract_scale(metadata),
        "channels": [_channel_name(channel, i) for i, channel in enumerate(channels)],
        "colors": [_channel_color(channel) for channel in channels],
        "dicChannel": 0,
        "lasers": [_channel_excitation(channel) for channel in channels],
        "emissions": [_channel_emission(channel) for channel in channels],
    }

    for i, channel in enumerate(channels, start=1):
        if _channel_is_dic(channel):
            payload["dicChannel"] = i
            break

    with open(output_json, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: read_czi.py <input.czi> <output.h5> <output.json>")
    convert(*sys.argv[1:4])


if __name__ == "__main__":
    main()
