#!/usr/bin/env python3
"""
Build a Z maximum-intensity projection (MIP) from a NeuroPAL-style volume (X,Y,Z,C)
with the same slice convention as infer_volume_slices_yolo.py, then overlay centroids of
every 2D bounding box recorded in predictions_summary.json.

YOLO/OpenCV xyxy convention: x = horizontal axis (columns), y = vertical (rows).

**3D centroids (default):** merge **across different** ``z`` only (same-slice pairs are **not**
linked). If |Δz| ≤ ``--fuse-max-dz`` and √(Δx²+Δy²) ≤ ``--fuse-max-dxy-px``, union-find can
still chain transitively—tighten radii if everything collapses. Each cluster gets a
confidence-weighted mean ``(z,x,y)``. ``--no-fuse-3d`` draws every raw 2D box centre.

By default the MIP is **colour** (Z-max per RGB channel, like compositing your slice images);
use ``--mip_mode gray`` for the older mean-RGB-then-Z-max black-and-white MIP.

Centroid markers default to **small red dots** (``--radius`` / ``--centroid_rgb``); use
``--centroid_rgb 0 255 255`` for the same cyan as ``predicted_boxes_cyan`` overlays, or
``--colour_centroids_by_z`` for green→red by depth.

Usage:
  cd neuroPAL-detection/yolov8-cell
  python mip_centroids_from_predictions_summary.py \\
    --summary results/infer_terminal_test/predictions_summary.json \\
    --out_png results/infer_terminal_test/mip_centroids_overlay.png \\
    --stretch_mip

python3 "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/mip_centroids_from_predictions_summary.py" \
  --summary "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/results/infer_unseen_000714_sub-2_stretched_model_conf05/predictions_summary.json" \
  --out_png "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/results/infer_unseen_000714_sub-2_stretched_model_conf05/mip_centroids_overlay.png" \
  --stretch_mip \
  --fuse-max-dz 1 \
  --fuse-max-dxy-px 6 \
  --device cpu \
  --export_csv "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/results/infer_unseen_000714_sub-2_stretched_model_conf05/yolo_centroids_fused.csv" \
  --export-mat "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/results/infer_unseen_000714_sub-2_stretched_model_conf05/yolo_centroids_vol.mat"

Writes timing JSON next to the PNG by default.

Optional ``--export-mat`` writes a **custom** scipy MAT v5 analysis file (label volume + tables). It does
**not** include NeuroPAL-required top-level ``data``, ``info``, ``prefs`` → **File→Open will error**. For
visualize_light, use ``--export-neuropal-gui-mat OUT.mat`` which writes ``OUT.mat`` (volume bundle) plus
``OUT_ID.mat`` (replace ``OUT`` stem with ``basename_ID`` pattern, e.g. ``foo.mat`` / ``foo_ID.mat``).
Optionally keep ``--export-neuropal-id-mat`` if you already have a lab volume ``*.mat`` and only need a
replacement sidecar beside it.

Use PYTHONUNBUFFERED=1 or `python -u` if logs appear delayed on non-TTY runs.

Note: YOLO "num_slices" is how many planes were run through the model; this script still
loads the full volume path from the summary unless you pass --crop-z-to-summary, so Z in
the .npy file (and X×Y footprint) dominates runtime, not the slice count in the JSON.
"""

from __future__ import annotations

import argparse
import json
import logging
import time
from pathlib import Path
from typing import Any, Mapping, Sequence

import cv2
import numpy as np

# Default marker colour: red in RGB. Cyan matching infer_volume_slices_yolo is (0, 255, 255).
DEFAULT_CENTROID_RGB: tuple[int, int, int] = (255, 0, 0)


def load_volume(path: Path) -> np.ndarray:
    """Same semantics as infer_volume_slices_yolo.load_volume (no Ultralytics import)."""
    vol = np.load(path, allow_pickle=True)
    if vol.dtype == object:
        raise ValueError("Expected one dense volume, got an object array of slices/volumes.")
    vol = np.asarray(vol)
    if vol.ndim == 3:
        vol = vol[..., np.newaxis]
    if vol.ndim != 4:
        raise ValueError(f"Expected volume shape (X,Y,Z,C) or (X,Y,Z), got {vol.shape}")
    return vol


def _summary_z_window(slices: Sequence[Mapping[str, Any]]) -> tuple[int, int] | None:
    zs: list[int] = []
    for block in slices:
        if not isinstance(block, dict) or "z" not in block:
            continue
        zs.append(int(block["z"]))
    if not zs:
        return None
    return min(zs), max(zs)


def mip_xy_gray(
    volume: np.ndarray,
    *,
    percentile_stretch: bool,
    p_lo: float,
    p_hi: float,
    log: logging.Logger | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Return (uint8_gray_hxw, mip_float_hxw before stretch) for stacking."""
    if log:
        log.info(
            "MIP sub-step: ndarray dtype=%s shape=%s (X,Y,Z,C)",
            volume.dtype,
            volume.shape,
        )
    t_cast = time.perf_counter()
    v = volume.astype(np.float32)
    if log:
        log.debug("MIP sub-step: cast to float32 in %.4fs", time.perf_counter() - t_cast)

    t_gray = time.perf_counter()
    if v.shape[-1] >= 3:
        gray_xyz = np.mean(v[..., :3], axis=-1)
        if log:
            log.info("MIP sub-step: grayscale = mean of first 3 channels -> shape %s", gray_xyz.shape)
    else:
        gray_xyz = v[..., 0]
        if log:
            log.info("MIP sub-step: single channel -> shape %s", gray_xyz.shape)

    mip = np.max(gray_xyz, axis=2)
    if log:
        log.debug(
            "MIP sub-step: max along z in %.4fs; raw MIP min/max = %.6g / %.6g",
            time.perf_counter() - t_gray,
            float(np.nanmin(mip)),
            float(np.nanmax(mip)),
        )

    mip_f = np.asarray(mip, dtype=np.float32)
    out = mip_f.copy()
    if percentile_stretch:
        lo, hi = np.percentile(out, [p_lo, p_hi])
        if hi <= lo + 1e-6:
            lo, hi = float(out.min()), float(out.max()) + 1e-6
        if log:
            log.info(
                "MIP sub-step: percentile stretch p%.2f–p%.2f → lo=%.6g hi=%.6g",
                p_lo,
                p_hi,
                lo,
                hi,
            )
        out = np.clip((out - lo) / (hi - lo) * 255.0, 0, 255).astype(np.uint8)
    else:
        mx = float(np.nanmax(out)) + 1e-9
        if log:
            log.info("MIP sub-step: normalize by global max=%.6g (no percentile stretch)", mx)
        out = np.clip(out / mx * 255.0, 0, 255).astype(np.uint8)
    if log:
        log.info("MIP sub-step: uint8 MIP shape %s (H×W for drawing)", out.shape)
    return out, mip_f


def mip_rgb_bgr(
    volume: np.ndarray,
    *,
    percentile_stretch: bool,
    p_lo: float,
    p_hi: float,
    log: logging.Logger | None = None,
) -> np.ndarray:
    """Z-max per RGB channel; optional per-channel p_lo/p_hi stretch (like infer slice stretch). Returns BGR uint8."""
    if volume.shape[-1] < 3:
        raise ValueError("mip_rgb_bgr needs volume with at least 3 channels")
    if log:
        log.info(
            "MIP sub-step (RGB): ndarray dtype=%s shape=%s — Z-max per channel on first 3",
            volume.dtype,
            volume.shape,
        )
    v = volume.astype(np.float32)[..., :3]
    mip = np.max(v, axis=2)
    out = np.empty_like(mip, dtype=np.float32)
    if percentile_stretch:
        for c in range(3):
            ch = mip[..., c]
            lo, hi = np.percentile(ch, [p_lo, p_hi])
            if hi <= lo + 1e-6:
                lo, hi = float(np.nanmin(ch)), float(np.nanmax(ch)) + 1e-6
            out[..., c] = np.clip((ch - lo) / (hi - lo) * 255.0, 0, 255)
            if log:
                log.debug("MIP sub-step (RGB): ch%d p%.1f–p%.1f → lo=%.6g hi=%.6g", c, p_lo, p_hi, lo, hi)
    else:
        for c in range(3):
            mx = float(np.nanmax(mip[..., c])) + 1e-9
            out[..., c] = np.clip(mip[..., c] / mx * 255.0, 0, 255)
    rgb_u8 = out.astype(np.uint8)
    if log:
        log.info("MIP sub-step (RGB): uint8 RGB shape %s → BGR canvas", rgb_u8.shape)
    return cv2.cvtColor(rgb_u8, cv2.COLOR_RGB2BGR)


def mip_rgb_bgr_torch_cuda(
    volume: np.ndarray,
    *,
    percentile_stretch: bool,
    p_lo: float,
    p_hi: float,
    log: logging.Logger | None = None,
) -> np.ndarray:
    """GPU Z-max on first 3 channels; stretch stays on CPU (small H×W×3)."""
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("device=gpu but torch.cuda.is_available() is False")
    if volume.shape[-1] < 3:
        raise ValueError("mip_rgb_bgr_torch_cuda needs volume with at least 3 channels")

    dev = torch.device("cuda")
    if log:
        log.info(
            "MIP sub-step (RGB GPU): torch %s cuda=%s",
            torch.__version__,
            torch.version.cuda,
        )
    t0 = time.perf_counter()
    v = torch.from_numpy(np.ascontiguousarray(volume[..., :3])).to(device=dev, dtype=torch.float32)
    mip = torch.amax(v, dim=2)
    mip_np = mip.detach().float().cpu().numpy()
    if log:
        log.debug("MIP sub-step (RGB GPU): H2D + Z-max in %.4fs", time.perf_counter() - t0)

    out = np.empty_like(mip_np, dtype=np.float32)
    if percentile_stretch:
        for c in range(3):
            ch = mip_np[..., c]
            lo, hi = np.percentile(ch, [p_lo, p_hi])
            if hi <= lo + 1e-6:
                lo, hi = float(np.nanmin(ch)), float(np.nanmax(ch)) + 1e-6
            out[..., c] = np.clip((ch - lo) / (hi - lo) * 255.0, 0, 255)
    else:
        for c in range(3):
            mx = float(np.nanmax(mip_np[..., c])) + 1e-9
            out[..., c] = np.clip(mip_np[..., c] / mx * 255.0, 0, 255)
    rgb_u8 = out.astype(np.uint8)
    return cv2.cvtColor(rgb_u8, cv2.COLOR_RGB2BGR)


def mip_xy_gray_torch_cuda(
    volume: np.ndarray,
    *,
    percentile_stretch: bool,
    p_lo: float,
    p_hi: float,
    log: logging.Logger | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """GPU path: Z-max and RGB→gray on CUDA; stretch + uint8 on CPU (2D MIP only)."""
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("device=gpu but torch.cuda.is_available() is False")
    dev = torch.device("cuda")
    if log:
        log.info("MIP sub-step (GPU): torch %s cuda=%s", torch.__version__, torch.version.cuda)

    t0 = time.perf_counter()
    v = torch.from_numpy(np.ascontiguousarray(volume)).to(device=dev, dtype=torch.float32)
    if log:
        log.debug("MIP sub-step (GPU): H2D + float32 in %.4fs", time.perf_counter() - t0)

    t_gray = time.perf_counter()
    if v.shape[-1] >= 3:
        gray_xyz = v[..., :3].mean(dim=-1)
    else:
        gray_xyz = v[..., 0]
    mip = torch.amax(gray_xyz, dim=2)
    if log:
        log.debug(
            "MIP sub-step (GPU): gray + max(z) in %.4fs",
            time.perf_counter() - t_gray,
        )

    mip_f = mip.detach().float().cpu().numpy()
    out = np.asarray(mip_f, dtype=np.float32).copy()
    if percentile_stretch:
        lo, hi = np.percentile(out, [p_lo, p_hi])
        if hi <= lo + 1e-6:
            lo, hi = float(out.min()), float(out.max()) + 1e-6
        if log:
            log.info(
                "MIP sub-step: percentile stretch p%.2f–p%.2f → lo=%.6g hi=%.6g (CPU, 2D)",
                p_lo,
                p_hi,
                lo,
                hi,
            )
        out = np.clip((out - lo) / (hi - lo) * 255.0, 0, 255).astype(np.uint8)
    else:
        mx = float(np.nanmax(out)) + 1e-9
        if log:
            log.info("MIP sub-step: normalize by global max=%.6g (no percentile stretch)", mx)
        out = np.clip(out / mx * 255.0, 0, 255).astype(np.uint8)
    if log:
        log.info("MIP sub-step: uint8 MIP shape %s (H×W for drawing)", out.shape)
    return out, mip_f


class _DSU:
    __slots__ = ("parent", "rank")

    def __init__(self, n: int) -> None:
        self.parent = list(range(n))
        self.rank = [0] * n

    def find(self, x: int) -> int:
        p = self.parent
        while p[x] != x:
            p[x] = p[p[x]]
            x = p[x]
        return x

    def union(self, a: int, b: int) -> None:
        pa, pb = self.find(a), self.find(b)
        if pa == pb:
            return
        ra, rb = self.rank[pa], self.rank[pb]
        if ra < rb:
            self.parent[pa] = pb
        elif ra > rb:
            self.parent[pb] = pa
        else:
            self.parent[pb] = pa
            self.rank[pa] += 1


def _linked_2d_slice_pair(
    za: float,
    xa: float,
    ya: float,
    zb: float,
    xb: float,
    yb: float,
    *,
    max_dz: int,
    max_dxy_px: float,
) -> bool:
    """Link only across different z (never merge two boxes on the same slice here)."""
    dz = abs(za - zb)
    if dz < 1e-9:
        return False
    if dz > float(max_dz) + 1e-9:
        return False
    dx = xa - xb
    dy = ya - yb
    return (dx * dx + dy * dy) ** 0.5 <= max_dxy_px


def fuse_slice_detections_to_3d_centroids(
    rows: list[list[float]],
    *,
    max_dz: int,
    max_dxy_px: float,
    log: logging.Logger | None = None,
) -> tuple[list[list[float]], dict[str, Any]]:
    """Cluster per-slice (z, cx, cy, conf) rows; return fused rows [z,cx,cy,conf_max,n_merged]."""
    stats: dict[str, Any] = {"num_raw": len(rows)}
    if not rows:
        stats["num_fused"] = 0
        stats["max_merge_size"] = 0
        return [], stats

    n = len(rows)
    dsu = _DSU(n)
    for i in range(n):
        zi, xi, yi, _ = rows[i]
        for j in range(i + 1, n):
            zj, xj, yj, _ = rows[j]
            if _linked_2d_slice_pair(zi, xi, yi, zj, xj, yj, max_dz=max_dz, max_dxy_px=max_dxy_px):
                dsu.union(i, j)

    groups: dict[int, list[int]] = {}
    for i in range(n):
        r = dsu.find(i)
        groups.setdefault(r, []).append(i)

    fused: list[list[float]] = []
    for members in groups.values():
        zs = [rows[i][0] for i in members]
        xs = [rows[i][1] for i in members]
        ys = [rows[i][2] for i in members]
        confs = np.array([rows[i][3] for i in members], dtype=np.float64)
        wsum = float(confs.sum())
        if wsum <= 0:
            w = np.ones(len(members), dtype=np.float64) / len(members)
        else:
            w = confs / wsum
        zf = float(np.dot(zs, w))
        xf = float(np.dot(xs, w))
        yf = float(np.dot(ys, w))
        conf_max = float(np.max(confs))
        fused.append([zf, xf, yf, conf_max, float(len(members))])

    fused.sort(key=lambda r: (r[0], r[1], r[2]))
    stats["num_fused"] = len(fused)
    stats["max_merge_size"] = int(max((int(r[4]) for r in fused), default=1))
    if log:
        log.info(
            "3D fuse: %d raw → %d fused (max_dz=%d max_dxy=%.4g px, largest merge=%d; "
            "same-z pairs are never merged)",
            stats["num_raw"],
            stats["num_fused"],
            max_dz,
            max_dxy_px,
            stats["max_merge_size"],
        )
    if log and stats["num_raw"] >= 30 and (
        stats["num_fused"] <= 8 or stats["max_merge_size"] >= max(40, stats["num_raw"] // 4)
    ):
        log.warning(
            "Fuse result looks over-merged (%d→%d, largest cluster=%d). "
            "Lower --fuse-max-dxy-px (default 12), or use --no-fuse-3d to draw all slice centroids.",
            stats["num_raw"],
            stats["num_fused"],
            stats["max_merge_size"],
        )
    return fused, stats


def paint_label_volume_uint16(
    vol_shape_xyz: tuple[int, int, int],
    draw_rows: list[list[float]],
    *,
    crop_z_offset: int,
    radius_xy: int,
    radius_z: int,
    log: logging.Logger | None = None,
) -> np.ndarray:
    """
    Rasterize fused centroid ids onto a volume matching ``volume[...,0].shape``: label_vol[row, col, z]
    with OpenCV/YOLO row=cy, col=cx.

    Background 0; foreground labels 1..N (overwrite only empty voxels, or tie-break to smallest id).

    ``crop_z_offset``: if the numpy volume was cropped ``[:, :, z0:z1+1, :]``, pass ``z0`` so
    absolute slice indices from the summary map into array index ``z - z0``.
    """
    h, w, nz = vol_shape_xyz[0], vol_shape_xyz[1], vol_shape_xyz[2]
    label = np.zeros((h, w, nz), dtype=np.uint16)
    rxy2 = radius_xy * radius_xy
    n_out = 0
    for k, (zf, xf, yf, _cf, _nm) in enumerate(draw_rows, start=1):
        z_abs = int(round(zf))
        zi = z_abs - int(crop_z_offset)
        yi = int(round(yf))
        xi = int(round(xf))
        if zi < 0 or zi >= nz:
            n_out += 1
            continue
        for dz in range(-radius_z, radius_z + 1):
            tz = zi + dz
            if tz < 0 or tz >= nz:
                continue
            for dy in range(-radius_xy, radius_xy + 1):
                ty = yi + dy
                if ty < 0 or ty >= h:
                    continue
                for dx in range(-radius_xy, radius_xy + 1):
                    tx = xi + dx
                    if tx < 0 or tx >= w:
                        continue
                    if dx * dx + dy * dy > rxy2:
                        continue
                    prev = label[ty, tx, tz].item()
                    if prev == 0 or k < prev:
                        label[ty, tx, tz] = np.uint16(k)
    if log and n_out:
        log.warning(
            "%d centroid(s) had z indices outside cropped volume [%d,%d]",
            n_out,
            int(crop_z_offset),
            int(crop_z_offset) + nz - 1,
        )
    return label


def _ensure_writable_parent(path: Path, what: str) -> None:
    """Create ``path.parent`` if needed, or raise with a clear hint."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        hint = ""
        s = str(path)
        if s.startswith("/Users/") or "/Users/" in s:
            hint = (
                " You used a macOS `/Users/...` path but this job runs on Linux (e.g. a cluster)—"
                "that filesystem is not mounted here. Use a path under `/scratch/` or `$HOME/` "
                "on the cluster, then `scp` the *_ID.mat to your Mac beside your NeuroPAL volume."
            )
        raise RuntimeError(
            f"Cannot create directory for {what}: {path.parent} — {e!s}.{hint}"
        ) from e


def export_centroids_mat(
    out_path: Path,
    *,
    label_vol: np.ndarray,
    draw_rows: list[list[float]],
    volume_full_shape_pre_crop: tuple[int, int, int] | None,
    volume_shape_numpy: tuple[int, int, int],
    crop_z_offset: int,
    summary_path_str: str,
    volume_path_str: str,
    fuse_3d: bool,
    fuse_max_dz: int,
    fuse_max_dxy_px: float,
    label_radius_xy: int,
    label_radius_z: int,
    extra_savemat_variables: Mapping[str, Any] | None = None,
    pipeline_note: str = "mip_centroids_from_predictions_summary.py",
) -> None:
    """Write MATLAB-readable .mat (MAT v5 via scipy.io.savemat)."""
    try:
        from scipy.io import savemat  # type: ignore[import-untyped]
    except ImportError as e:
        raise RuntimeError(
            "export_mat needs scipy (`pip install scipy`) for scipy.io.savemat."
        ) from e

    n = len(draw_rows)
    centroid_table = np.zeros((max(n, 1), 6), dtype=np.float64)
    for i, row in enumerate(draw_rows):
        zf, xf, yf, cf, nm = row
        centroid_table[i, :] = (
            float(i + 1),
            float(zf),
            float(xf),
            float(yf),
            float(cf),
            float(nm),
        )

    mp_dtype = np.dtype(
        [
            ("coords_note", object),
            ("vol_shape_xyz", object),
            ("full_shape_precrop_xyz", object),
            ("crop_z0", object),
            ("n_centroids", object),
            ("summary_path", object),
            ("volume_path", object),
            ("fuse_3d", object),
            ("fuse_max_dz", object),
            ("fuse_dxy_px", object),
            ("lbl_r_xy", object),
            ("lbl_r_z", object),
        ]
    )
    mp = np.zeros(1, dtype=mp_dtype)
    conv = np.str_(
        "label_vol(row,col,z)==volume[row,col,z]; centroid cols id,z_abs,cx_sub,cy_sub,conf,n_merged."
    )
    mp[0]["coords_note"] = conv
    mp[0]["vol_shape_xyz"] = np.asarray(volume_shape_numpy, dtype=np.int64).reshape(3, 1)
    mp[0]["full_shape_precrop_xyz"] = np.asarray(
        volume_full_shape_pre_crop if volume_full_shape_pre_crop else volume_shape_numpy,
        dtype=np.int64,
    ).reshape(3, 1)
    mp[0]["crop_z0"] = np.asarray([[crop_z_offset]], dtype=np.int64)
    mp[0]["n_centroids"] = np.asarray([[n]], dtype=np.int64)
    mp[0]["summary_path"] = np.array(np.str_(summary_path_str))
    mp[0]["volume_path"] = np.array(np.str_(volume_path_str))
    mp[0]["fuse_3d"] = np.asarray([[int(fuse_3d)]], dtype=np.uint8)
    mp[0]["fuse_max_dz"] = np.asarray([[fuse_max_dz]], dtype=np.int64)
    mp[0]["fuse_dxy_px"] = np.asarray([[fuse_max_dxy_px]], dtype=np.float64)
    mp[0]["lbl_r_xy"] = np.asarray([[label_radius_xy]], dtype=np.int64)
    mp[0]["lbl_r_z"] = np.asarray([[label_radius_z]], dtype=np.int64)

    _ensure_writable_parent(out_path, "--export-mat output")
    mat_blob: dict[str, Any] = {
        "version": np.asarray([[1.0]], dtype=np.float64),
        "label_vol_uint16_YXZ": label_vol.astype(np.uint16, copy=False),
        "centroids_nby6_id_z_xy_conf_nm": centroid_table[:n] if n else centroid_table,
        "mp_params": mp,
        "pipeline": np.array(np.str_(pipeline_note)),
    }
    if extra_savemat_variables:
        mat_blob.update(dict(extra_savemat_variables))
    savemat(str(out_path), mat_blob, do_compression=True)


def neuropal_id_mat_path_for_volume_mat(volume_mat: Path) -> Path:
    """``foo.mat`` → ``foo_ID.mat`` (same rule as ``NeuroPALImage.loadNP``)."""
    return volume_mat.with_name(f"{volume_mat.stem}_ID{volume_mat.suffix}")


def _neuropal_hnsz_from_scale_um(scale_um: Sequence[float]) -> np.ndarray:
    """Odd window ≈ ``round(round(3./scale)/2)*2+1`` per axis (µm), ``loadNP`` default style."""
    s = np.asarray(list(scale_um), dtype=np.float64).ravel()
    s = np.maximum(s, 1e-9)
    h = np.round(np.round(3.0 / s) / 2.0) * 2.0 + 1.0
    return h.reshape(1, 3).astype(np.float64)


def build_neuropal_sp_and_mp_params(
    draw_rows: list[list[float]],
    *,
    ny: int,
    nx: int,
    nz: int,
    crop_z_offset: int,
    volume: np.ndarray | None,
    fallback_num_channels: int,
    summary_path_str: str,
    volume_path_str: str,
    fuse_3d: bool,
    fuse_max_dz: int,
    fuse_max_dxy_px: float,
    scale_um: tuple[float, float, float] | None,
    transpose_xy_for_neuropal: bool,
    log: logging.Logger | None = None,
) -> tuple[dict[str, Any], dict[str, Any], int]:
    """
    Build ``sp`` / ``mp_params`` for ``*_ID.mat`` (``version == 1`` path).

    With ``transpose_xy_for_neuropal`` (default for GUI bundle), the saved ``data`` volume is
    ``np.transpose(vol, (1,0,2,3))`` so MATLAB ``size(data,2)=nx`` (horizontal) carries the long
    OpenCV axis (worm “horizontal” in the viewer). Centroid indices then follow
    ``data(cx+1, cy+1, z, :)`` in 1-based form.

    Without transpose, positions are ``[cy+1, cx+1, z+1]`` matching raw numpy ``vol[cy, cx, z]``
    as written to ``data`` (tall ``ny`` × narrow ``nx`` if your .npy is OpenCV H×W).
    """
    n = len(draw_rows)
    # ny, nx = OpenCV / numpy plane size (rows, cols) for volume[:, :, z, :]
    ny0, nx0 = int(ny), int(nx)
    vwork: np.ndarray | None = None
    if volume is not None:
        if volume.ndim != 4:
            raise ValueError("volume must be 4-D (row, col, z, channels) for NeuroPAL exports")
        ny0, nx0 = int(volume.shape[0]), int(volume.shape[1])
        vwork = np.transpose(volume, (1, 0, 2, 3)) if transpose_xy_for_neuropal else volume
        nc = int(vwork.shape[3])
    else:
        nc = max(int(fallback_num_channels), 1)

    pos = np.zeros((n, 3), dtype=np.float64)
    cov = np.zeros((n, 3, 3), dtype=np.float64)
    d_cov = np.diag([10.0, 10.0, 3.0])
    color = np.full((n, nc), np.nan, dtype=np.float64)
    color_readout = np.full((n, nc), np.nan, dtype=np.float64)
    baseline = np.zeros((n, nc), dtype=np.float64)

    n_skipped = 0
    for i, row in enumerate(draw_rows):
        zf, xf, yf, _cf, _nm = row
        zi = int(round(float(zf))) - int(crop_z_offset)
        if zi < 0 or zi >= nz:
            n_skipped += 1
            zi = int(np.clip(zi, 0, max(nz - 1, 0)))
        cy = int(np.clip(int(round(float(yf))), 0, max(ny0 - 1, 0)))
        cx = int(np.clip(int(round(float(xf))), 0, max(nx0 - 1, 0)))

        if transpose_xy_for_neuropal:
            # Saved data is permute(vol,(1,0,2,3)): same voxel is vwork[cx, cy, z, :].
            pos[i, 0] = float(cx + 1)
            pos[i, 1] = float(cy + 1)
            ir, ic = cx, cy
        else:
            pos[i, 0] = float(cy + 1)
            pos[i, 1] = float(cx + 1)
            ir, ic = cy, cx
        pos[i, 2] = float(zi + 1)
        cov[i, :, :] = d_cov

        if vwork is not None:
            samp = vwork[ir, ic, zi, :].astype(np.float64, copy=False).ravel()
            color[i, : samp.size] = samp[:nc]
            color_readout[i, : samp.size] = samp[:nc]

    if log and n_skipped:
        log.warning(
            "%d fused centroid(s) had z index outside cropped volume after crop_z0=%d — clamped",
            n_skipped,
            int(crop_z_offset),
        )

    sp: dict[str, Any] = {
        "positions": pos,
        "color": color,
        "color_readout": color_readout,
        "baseline": baseline,
        "covariances": cov,
    }

    if scale_um is not None:
        sx, sy, sz = float(scale_um[0]), float(scale_um[1]), float(scale_um[2])
        if transpose_xy_for_neuropal:
            scale_use = (sy, sx, sz)
        else:
            scale_use = (sx, sy, sz)
        hnsz = _neuropal_hnsz_from_scale_um(scale_use)
    else:
        hnsz = np.asarray([[11.0, 11.0, 3.0]], dtype=np.float64)

    mp_params: dict[str, Any] = {
        "k": np.asarray([[float(n)]], dtype=np.float64),
        "detect_scale": np.asarray([[0.0]], dtype=np.float64),
        "hnsz": hnsz,
        "exclusion_radius": np.asarray([[1.5]], dtype=np.float64),
        "min_eig_thresh": np.asarray([[0.1]], dtype=np.float64),
        "backend": np.array(np.str_("yolov8")),
        "fuse_3d": np.asarray([[int(fuse_3d)]], dtype=np.uint8),
        "fuse_max_dz": np.asarray([[fuse_max_dz]], dtype=np.int64),
        "fuse_dxy_px": np.asarray([[fuse_max_dxy_px]], dtype=np.float64),
        "crop_z0": np.asarray([[int(crop_z_offset)]], dtype=np.int64),
        "summary_path": np.array(np.str_(summary_path_str)),
        "volume_path": np.array(np.str_(volume_path_str)),
        "pos_note": np.array(
            np.str_(
                "1-based MATLAB data indices: Without xy-permute -> [dim1,dim2]=[cy+1,cx+1] OpenCV HW. "
                "With default xy-permute for GUI -> [cx+1,cy+1] matching permute(vol,(1,0,2,3)) save."
            )
        ),
    }
    return sp, mp_params, n_skipped


def _save_neuropal_id_mat(out_path: Path, sp: Mapping[str, Any], mp_params: Mapping[str, Any]) -> None:
    try:
        from scipy.io import savemat  # type: ignore[import-untyped]
    except ImportError as e:
        raise RuntimeError(
            "NeuroPAL ID export needs scipy (`pip install scipy`) for scipy.io.savemat."
        ) from e
    _ensure_writable_parent(out_path, "NeuroPAL _ID.mat output")
    savemat(
        str(out_path),
        {
            "version": np.asarray([[1.0]], dtype=np.float64),
            "sp": dict(sp),
            "mp_params": dict(mp_params),
        },
        do_compression=True,
    )


def export_neuropal_detection_id_mat(
    out_path: Path,
    *,
    draw_rows: list[list[float]],
    volume_shape_row_col_z: tuple[int, int, int],
    crop_z_offset: int,
    summary_path_str: str,
    volume_path_str: str,
    fuse_3d: bool,
    fuse_max_dz: int,
    fuse_max_dxy_px: float,
    volume: np.ndarray | None = None,
    fallback_num_channels: int = 4,
    scale_um: tuple[float, float, float] | None = None,
    transpose_xy_for_neuropal: bool = False,
    log: logging.Logger | None = None,
) -> None:
    """
    Detection-only ``*_ID.mat`` beside an **existing** NeuroPAL ``*.mat`` volume.

    If ``volume`` is set, ``sp.color`` rows match ``size(data,4)`` and are voxel-sampled like the
    Cellpose template (plus ``baseline`` zeros, ``diag(10,10,3)`` covariances).
    """
    ny, nx, nz = (
        int(volume_shape_row_col_z[0]),
        int(volume_shape_row_col_z[1]),
        int(volume_shape_row_col_z[2]),
    )
    sp, mp, _ = build_neuropal_sp_and_mp_params(
        draw_rows,
        ny=ny,
        nx=nx,
        nz=nz,
        crop_z_offset=crop_z_offset,
        volume=volume,
        fallback_num_channels=fallback_num_channels,
        summary_path_str=summary_path_str,
        volume_path_str=volume_path_str,
        fuse_3d=fuse_3d,
        fuse_max_dz=fuse_max_dz,
        fuse_max_dxy_px=fuse_max_dxy_px,
        scale_um=scale_um,
        transpose_xy_for_neuropal=transpose_xy_for_neuropal,
        log=log,
    )
    _save_neuropal_id_mat(out_path, sp, mp)


def export_neuropal_gui_mat_bundle(
    gui_volume_mat_out: Path,
    *,
    volume: np.ndarray,
    draw_rows: list[list[float]],
    crop_z_offset: int,
    summary_path_str: str,
    volume_path_str: str,
    fuse_3d: bool,
    fuse_max_dz: int,
    fuse_max_dxy_px: float,
    scale_um: tuple[float, float, float],
    neuropal_np_version: float,
    neuropal_gamma: float,
    worm_body: str,
    worm_age: str,
    worm_sex: str,
    worm_strain: str,
    worm_notes: str,
    transpose_xy_for_neuropal: bool = True,
    log: logging.Logger | None = None,
    mp_params_extra: Mapping[str, Any] | None = None,
    extra_volume_mat_variables: Mapping[str, Any] | None = None,
) -> tuple[Path, Path]:
    """
    Full visualize_light-openable pair:

    - **Volume** ``*.mat``: ``data``, ``info``, ``prefs``, ``worm``, ``version``, plus optional
      ``yolo_fused_ctr6`` (subpixel table) and ``yolo_fused_xyz1`` (Nx3 MATLAB 1-based indices into
      ``data`` — same frame as ``sp.positions`` in the sidecar) for a single-file volume+centroids workflow.
    - **Sidecar**: ``basename_ID.mat`` with ``version==1``, ``sp``, ``mp_params`` (Neuron objects for GUI).

    ``extra_volume_mat_variables``: optional top-level arrays/structs merged into the main ``savemat`` dict
    (e.g. fused 3D AABB tables from YOLO viz). Keys named ``version`` are ignored so ``neuropal_np_version``
    stays authoritative.
    """
    try:
        from scipy.io import savemat  # type: ignore[import-untyped]
    except ImportError as e:
        raise RuntimeError(
            "NeuroPAL GUI export needs scipy (`pip install scipy`) for scipy.io.savemat."
        ) from e

    if gui_volume_mat_out.suffix.lower() != ".mat":
        raise ValueError("--export-neuropal-gui-mat must end with .mat")

    if volume.ndim != 4:
        raise ValueError("volume must be (row,col,z,nChannels) numpy array")

    ny0, nx0, nz, nc = (int(volume.shape[i]) for i in range(4))
    if nz < 2:
        if log:
            log.warning(
                "NeuroPAL Program.Routines.open treats stacks with nz<2 as non-volumes; "
                "current nz=%d — GUI may refuse to open.",
                nz,
            )

    if transpose_xy_for_neuropal and log:
        log.info(
            "NeuroPAL GUI bundle: XY permute (numpy %d×%d@Z → MATLAB %d×%d@Z horizontal×vertical) · "
            "use --neuropal-keep-numpy-axes to skip.",
            ny0,
            nx0,
            nx0,
            ny0,
        )

    data_u8 = (
        np.transpose(volume, (1, 0, 2, 3)).astype(np.uint8, copy=False)
        if transpose_xy_for_neuropal
        else volume.astype(np.uint8, copy=False)
    )

    info_rgbw_col = np.full((4, 1), np.nan, dtype=np.float64)
    prefs_rgbw_row = np.full((1, 4), np.nan, dtype=np.float64)
    for i in range(min(nc, 4)):
        fv = float(i + 1)
        info_rgbw_col[i, 0] = fv
        prefs_rgbw_row[0, i] = fv

    sx, sy, sz = float(scale_um[0]), float(scale_um[1]), float(scale_um[2])
    if transpose_xy_for_neuropal:
        scale_col = np.asarray([sy, sx, sz], dtype=np.float64).reshape(3, 1)
    else:
        scale_col = np.asarray([sx, sy, sz], dtype=np.float64).reshape(3, 1)

    info: dict[str, Any] = {
        "file": np.array(np.str_(volume_path_str)),
        "scale": scale_col,
        "RGBW": info_rgbw_col,
        "DIC": float("nan"),
        "GFP": float("nan"),
        "gamma": float(neuropal_gamma),
    }
    prefs: dict[str, Any] = {
        "RGBW": prefs_rgbw_row,
        "DIC": float("nan"),
        "GFP": float("nan"),
        "gamma": float(neuropal_gamma),
        "rotate": {
            "horizontal": False,
            "vertical": False,
        },
        "z_center": float(int(np.ceil(nz / 2))),
        "is_Z_LR": True,
        "is_Z_flip": True,
    }
    worm: dict[str, Any] = {
        "body": np.array(np.str_(worm_body)),
        "age": np.array(np.str_(worm_age)),
        "sex": np.array(np.str_(worm_sex)),
        "strain": np.array(np.str_(worm_strain)),
        "notes": np.array(np.str_(worm_notes)),
    }
    vers_main = np.asarray([[float(neuropal_np_version)]], dtype=np.float64)

    sp, mp, _ = build_neuropal_sp_and_mp_params(
        draw_rows,
        ny=ny0,
        nx=nx0,
        nz=nz,
        crop_z_offset=crop_z_offset,
        volume=volume,
        fallback_num_channels=max(nc, 1),
        summary_path_str=summary_path_str,
        volume_path_str=volume_path_str,
        fuse_3d=fuse_3d,
        fuse_max_dz=fuse_max_dz,
        fuse_max_dxy_px=fuse_max_dxy_px,
        scale_um=scale_um,
        transpose_xy_for_neuropal=transpose_xy_for_neuropal,
        log=log,
    )
    if mp_params_extra:
        mp = dict(mp)
        for _k, _v in mp_params_extra.items():
            if isinstance(_v, str):
                mp[_k] = np.array(np.str_(_v))
            elif isinstance(_v, (bool, np.bool_)):
                mp[_k] = np.asarray([[int(bool(_v))]], dtype=np.uint8)
            elif isinstance(_v, (int, np.integer)):
                mp[_k] = np.asarray([[int(_v)]], dtype=np.int64)
            elif isinstance(_v, (float, np.floating)):
                mp[_k] = np.asarray([[float(_v)]], dtype=np.float64)
            else:
                mp[_k] = _v

    n_ctr = len(draw_rows)
    if n_ctr:
        ctr6 = np.zeros((n_ctr, 6), dtype=np.float64)
        for i, row in enumerate(draw_rows):
            zf, xf, yf, cf, nm = row
            ctr6[i, :] = (float(i + 1), float(zf), float(xf), float(yf), float(cf), float(nm))
        pos_xyz1 = np.asarray(sp["positions"], dtype=np.float64).reshape(n_ctr, 3)
    else:
        ctr6 = np.zeros((0, 6), dtype=np.float64)
        pos_xyz1 = np.zeros((0, 3), dtype=np.float64)

    _ensure_writable_parent(gui_volume_mat_out, "--export-neuropal-gui-mat volume .mat")

    ctr_note = (
        "yolo_fused_ctr6: cols id,z,cx_sub,cy_sub,conf,n_merged (numpy/OpenCV row=cy col=cx). "
        "yolo_fused_xyz1: Nx3 double, MATLAB 1-based [dim1,dim2,dim3] into saved data (same as sp.positions). "
        "Marker colour in MIP PNG is red (255,0,0) by default; draw in MATLAB with scatter3/plot3 from yolo_fused_xyz1."
    )
    vol_mat: dict[str, Any] = {
        "version": vers_main,
        "data": data_u8,
        "info": info,
        "prefs": prefs,
        "worm": worm,
        "yolo_fused_ctr6": ctr6,
        "yolo_fused_xyz1": pos_xyz1,
        "yolo_ctr_note": np.array(np.str_(ctr_note)),
    }
    if extra_volume_mat_variables:
        for _ek, _ev in dict(extra_volume_mat_variables).items():
            if _ek == "version":
                continue
            vol_mat[_ek] = _ev
        _bnote = extra_volume_mat_variables.get("yolo_fused_boxes_note")
        if _bnote is not None:
            try:
                btxt = str(np.asarray(_bnote).item())
            except (ValueError, TypeError):
                btxt = str(_bnote)
            vol_mat["yolo_ctr_note"] = np.array(np.str_(ctr_note + " | FUSED_3D_BOXES: " + btxt))

    savemat(str(gui_volume_mat_out), vol_mat, do_compression=True)

    sidecar = neuropal_id_mat_path_for_volume_mat(gui_volume_mat_out)
    _save_neuropal_id_mat(sidecar, sp, mp)
    if log:
        log.info(
            "Volume .mat includes yolo_fused_ctr6 (%d×6) and yolo_fused_xyz1 (%d×3); read yolo_ctr_note for column meanings.",
            n_ctr,
            n_ctr,
        )
    return gui_volume_mat_out, sidecar


def z_to_bgr(z: int, z_max: int) -> tuple[int, int, int]:
    """Map slice index to BGR for drawing (green->red along z)."""
    if z_max <= 0:
        t = 0.0
    else:
        t = float(z) / float(z_max)
    # HSV-like: hue 120 (green) -> 0 (red)
    r = int(255 * t)
    g = int(255 * (1.0 - t))
    b = 40
    return (b, g, r)


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Z-MIP + centroid overlay from predictions_summary.json + volume .npy"
    )
    ap.add_argument("--summary", type=Path, required=True, help="predictions_summary.json")
    ap.add_argument(
        "--volume",
        type=Path,
        default=None,
        help="Override volume .npy path (default: read from summary['volume'])",
    )
    ap.add_argument("--out_png", type=Path, required=True, help="Output visualization PNG")
    ap.add_argument(
        "--stretch_mip",
        action="store_true",
        help="Apply p_lo/p_hi percentile stretch to the MIP (recommended for microscopy)",
    )
    ap.add_argument(
        "--mip_mode",
        choices=("rgb", "gray"),
        default="rgb",
        help="rgb: Z-max per colour channel (matches slice PNGs); gray: mean RGB then Z-max (B/W).",
    )
    ap.add_argument("--p_lo", type=float, default=2.0)
    ap.add_argument("--p_hi", type=float, default=98.0)
    ap.add_argument("--radius", type=int, default=2, help="Centroid marker radius in px (MIP fused layer)")
    ap.add_argument(
        "--mip-markers",
        choices=("fused", "raw", "both"),
        default="both",
        help="MIP dots: fused=merged 3D centroids only (fewest dots); raw=every slice box centre; "
        "both=cyan raw underlay then fused on top when --fuse-3d (recommended if dots look missing).",
    )
    ap.add_argument(
        "--centroid_rgb",
        type=int,
        nargs=3,
        metavar=("R", "G", "B"),
        default=list(DEFAULT_CENTROID_RGB),
        help="RGB for all centroid markers when not --colour_centroids_by_z (default: 255 0 0 red; "
        "use 0 255 255 for cyan like predicted_boxes_cyan).",
    )
    ap.add_argument(
        "--colour_centroids_by_z",
        action="store_true",
        help="Colour each marker by its slice index (green→red with depth). Overrides --centroid_rgb.",
    )
    ap.add_argument(
        "--line_width_centroid",
        type=int,
        default=-1,
        help="Circle line width (-1 = filled disks)",
    )
    ap.add_argument(
        "--export_csv",
        type=Path,
        default=None,
        help="Optional path: fused 3D centroids CSV (z,cx,cy,conf_max,x_pixel,y_pixel,n_merged); "
        "with --no-fuse-3d, n_merged is always 1.",
    )
    ap.add_argument(
        "--export-mat",
        type=Path,
        default=None,
        help="Optional path: custom analysis .mat (label volume + centroid table). "
        "Missing NeuroPAL top-level data/info/prefs — use --export-neuropal-gui-mat for visualize_light.",
    )
    ap.add_argument(
        "--export-neuropal-id-mat",
        type=Path,
        default=None,
        help="Optional *_ID.mat only (version=1, struct sp): use beside an existing lab volume *.mat "
        "(same basename). Colors sampled from loaded volume unless --volume is mismatched.",
    )
    ap.add_argument(
        "--export-neuropal-gui-mat",
        type=Path,
        default=None,
        help="Full NeuroPAL pair for visualize_light: writes OUT.mat (data,info,prefs,worm,version) "
        "and OUT_ID.mat (detections). Open OUT.mat in the GUI (not --export-mat).",
    )
    ap.add_argument(
        "--neuropal-scale-um",
        type=float,
        nargs=3,
        metavar=("SX", "SY", "SZ"),
        default=[1.0, 1.0, 1.0],
        help="Voxel size in µm (x,y,z) for info.scale and mp.hnsz (GUI + ID export).",
    )
    ap.add_argument(
        "--neuropal-gamma",
        type=float,
        default=0.8,
        help="Gamma written to info/prefs on --export-neuropal-gui-mat.",
    )
    ap.add_argument(
        "--neuropal-volume-version",
        type=float,
        default=2.0,
        help="Numeric top-level `version` on the main NeuroPAL .mat from --export-neuropal-gui-mat.",
    )
    ap.add_argument(
        "--worm-body",
        type=str,
        default="Head",
        help="worm.body for GUI export (must match NeuroPAL dropdown, e.g. Head, Whole Worm, …).",
    )
    ap.add_argument("--worm-age", type=str, default="Adult")
    ap.add_argument("--worm-sex", type=str, default="XX")
    ap.add_argument("--worm-strain", type=str, default="")
    ap.add_argument("--worm-notes", type=str, default="")
    ap.add_argument(
        "--neuropal-keep-numpy-axes",
        action="store_true",
        help="Skip XY permute when writing NeuroPAL mats: keep numpy (H,W,...) as MATLAB data dim1×dim2 "
        "exactly. Default (off) permutes with transpose(1,0,2,3) so MATLAB horizontal size(data,2) "
        "matches the long worm axis from OpenCV slices.",
    )
    ap.add_argument(
        "--label-radius-xy",
        type=int,
        default=2,
        help="Half-width in plane (integer voxels) when painting label_vol (disk in x–y).",
    )
    ap.add_argument(
        "--label-radius-z",
        type=int,
        default=1,
        help="Half-extent along z (integer slices) when painting each centroid into label_vol.",
    )
    fuse_g = ap.add_mutually_exclusive_group()
    fuse_g.add_argument(
        "--fuse-3d",
        dest="fuse_3d",
        action="store_true",
        help="Merge slice-wise YOLO boxes across z into 3D centroids (single-linkage heuristic). Default on.",
    )
    fuse_g.add_argument(
        "--no-fuse-3d",
        dest="fuse_3d",
        action="store_false",
        help="Keep every 2D box as its own point (no cross-z merging).",
    )
    ap.set_defaults(fuse_3d=True)
    ap.add_argument(
        "--fuse-max-dz",
        type=int,
        default=1,
        help="Link two detections only if |Δz| ≤ this (integer slice index).",
    )
    ap.add_argument(
        "--fuse-max-dxy-px",
        type=float,
        default=12.0,
        help="Link two detections (different z only) if √(Δx²+Δy²) ≤ this. "
        "Larger values chain single-link clusters; try 8–15 for worms.",
    )
    ap.add_argument(
        "--timing_json",
        type=Path,
        default=None,
        help="Wall-clock breakdown JSON (default: next to --out_png, stem + '_mip_centroids_timing.json')",
    )
    ap.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="DEBUG logging (per-step timing also always printed at INFO).",
    )
    ap.add_argument(
        "--device",
        choices=("cpu", "gpu"),
        default="cpu",
        help="Where to compute the Z-MIP (gpu = PyTorch CUDA on the full volume tensor; "
        "still loads the .npy on CPU first). Default: cpu (NumPy).",
    )
    ap.add_argument(
        "--crop-z-to-summary",
        action="store_true",
        help="Before the MIP, crop volume Z to [min(z), max(z)] over slices listed in the "
        "summary JSON (faster when inference only covered a small Z band in a deep stack).",
    )
    args = ap.parse_args()

    centroid_rgb = tuple(int(np.clip(int(c), 0, 255)) for c in args.centroid_rgb)
    centroid_bgr = (centroid_rgb[2], centroid_rgb[1], centroid_rgb[0])

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s [mip_centroids] %(message)s",
    )
    log = logging.getLogger("mip_centroids")

    t_wall0 = time.perf_counter()
    timings: dict[str, float | int | list[int] | str | None] = {}

    timings["centroid_rgb"] = list(centroid_rgb)
    timings["colour_centroids_by_z"] = args.colour_centroids_by_z
    log.info(
        "--- Step 1/9: CLI OK | out_png=%s stretch_mip=%s radius=%s fuse_3d=%s fuse_dz=%s fuse_dxy=%s ---",
        args.out_png.resolve(),
        args.stretch_mip,
        args.radius,
        args.fuse_3d,
        args.fuse_max_dz,
        args.fuse_max_dxy_px,
    )
    log.info("--- Step 2/9: Reading predictions_summary.json ---")
    log.info("summary path: %s", args.summary.resolve())

    t0 = time.perf_counter()
    sj = json.loads(Path(args.summary).read_text(encoding="utf-8"))
    timings["seconds_read_summary_json"] = round(time.perf_counter() - t0, 6)
    log.info("read JSON in %.4fs", timings["seconds_read_summary_json"])

    inferred = sj.get("num_slices"), sj.get("total_predictions"), sj.get("conf"), sj.get("imgsz")
    log.info(
        "summary meta: num_slices=%r total_predictions=%r conf=%r imgsz=%r stretch_slices=%r",
        *inferred,
        sj.get("stretch_slices"),
    )
    vol_path = Path(args.volume) if args.volume is not None else Path(sj["volume"])
    timings["volume_path"] = str(vol_path.resolve())
    timings["summary_path"] = str(Path(args.summary).resolve())

    log.info("--- Step 3/9: Resolve volume ---")
    log.info("volume path (from %s): %s", "CLI" if args.volume else "JSON", vol_path.resolve())
    if not vol_path.is_file():
        raise FileNotFoundError(f"volume not found: {vol_path}")

    log.info("--- Step 4/9: Load volume .npy ---")
    log.info(
        "expected volume_shape from summary (X,Y,Z,C): %s",
        sj.get("volume_shape"),
    )
    t0 = time.perf_counter()
    volume = load_volume(vol_path)
    timings["seconds_load_numpy_volume"] = round(time.perf_counter() - t0, 6)
    log.info(
        "loaded ndarray: dtype=%s shape=%s in %.4fs",
        volume.dtype,
        volume.shape,
        timings["seconds_load_numpy_volume"],
    )
    if sj.get("volume_shape") is not None:
        doc_shape = tuple(int(x) for x in sj["volume_shape"])
        if tuple(volume.shape) != doc_shape:
            log.warning(
                "volume shape mismatch: file %s vs summary %s — using file shape",
                volume.shape,
                doc_shape,
            )

    volume_full_shape_xyz = (
        int(volume.shape[0]),
        int(volume.shape[1]),
        int(volume.shape[2]),
    )
    crop_z_offset = 0

    # For z→colour gradient, use full volume depth (box z indices are absolute planes).
    full_z_max_coord = max(0, volume_full_shape_xyz[2] - 1)
    timings["volume_z_depth_full"] = volume_full_shape_xyz[2]

    z_win = _summary_z_window(sj.get("slices") or [])
    timings["summary_z_min_max_inclusive"] = list(z_win) if z_win else None
    if args.crop_z_to_summary:
        if z_win is None:
            log.warning("--crop-z-to-summary set but no slice z values in summary; using full Z")
        else:
            z0, z1 = z_win
            nz = volume.shape[2]
            if z0 < 0 or z1 >= nz or z0 > z1:
                raise ValueError(
                    f"summary z range [{z0},{z1}] incompatible with volume Z={nz}"
                )
            t_crop = time.perf_counter()
            crop_z_offset = int(z0)
            volume = volume[:, :, z0 : z1 + 1, :]
            timings["seconds_crop_z_to_summary"] = round(time.perf_counter() - t_crop, 6)
            log.info(
                "cropped Z to summary window [%d,%d] → %d planes (was %d) in %.4fs",
                z0,
                z1,
                volume.shape[2],
                nz,
                timings["seconds_crop_z_to_summary"],
            )

    log.info("--- Step 5/9: Build Z-MIP ---")
    n_ch = int(volume.shape[-1])
    mip_mode: str = args.mip_mode
    if mip_mode == "rgb" and n_ch < 3:
        log.warning(
            "mip_mode=rgb needs ≥3 channels; volume has %d — falling back to gray MIP",
            n_ch,
        )
        mip_mode = "gray"

    z_extent = volume.shape[2]
    timings["mip_mode"] = mip_mode
    log.info(
        "Z extent (%d planes) | mip_mode=%s | stretch_mip=%s | device=%s",
        z_extent,
        mip_mode,
        args.stretch_mip,
        args.device.upper(),
    )

    t0 = time.perf_counter()
    if mip_mode == "rgb":
        if args.device == "gpu":
            canvas = mip_rgb_bgr_torch_cuda(
                volume,
                percentile_stretch=args.stretch_mip,
                p_lo=args.p_lo,
                p_hi=args.p_hi,
                log=log,
            )
        else:
            canvas = mip_rgb_bgr(
                volume,
                percentile_stretch=args.stretch_mip,
                p_lo=args.p_lo,
                p_hi=args.p_hi,
                log=log,
            )
    elif args.device == "gpu":
        mip_u8, _ = mip_xy_gray_torch_cuda(
            volume,
            percentile_stretch=args.stretch_mip,
            p_lo=args.p_lo,
            p_hi=args.p_hi,
            log=log,
        )
        canvas = cv2.cvtColor(mip_u8, cv2.COLOR_GRAY2BGR)
    else:
        mip_u8, _ = mip_xy_gray(
            volume,
            percentile_stretch=args.stretch_mip,
            p_lo=args.p_lo,
            p_hi=args.p_hi,
            log=log,
        )
        canvas = cv2.cvtColor(mip_u8, cv2.COLOR_GRAY2BGR)

    timings["seconds_build_z_mip"] = round(time.perf_counter() - t0, 6)
    h_m, w_m = int(canvas.shape[0]), int(canvas.shape[1])
    log.info(
        "Z-MIP done in %.4fs (mode=%s · BGR canvas %d×%d)",
        timings["seconds_build_z_mip"],
        mip_mode,
        h_m,
        w_m,
    )

    log.info("BGR canvas ready for centroid overlays")
    z_max_coord = full_z_max_coord

    log.info("--- Step 6/9: Collect centroids from boxes_xyxy_conf ---")
    t0 = time.perf_counter()
    rows: list[list[float]] = []
    short_records = 0
    nz_sl = 0
    n_slices_doc = len(sj.get("slices", []))
    counts_per_slice: list[int] = []
    for block in sj.get("slices", []):
        zi = int(block["z"])
        recs = block.get("boxes_xyxy_conf", [])
        zb = len(recs)
        counts_per_slice.append(zb)
        if zb > 0:
            nz_sl += 1
        for rec in recs:
            if len(rec) < 5:
                short_records += 1
                continue
            x1, y1, x2, y2, conf = rec[:5]
            cx = float(x1 + x2) / 2.0
            cy = float(y1 + y2) / 2.0
            rows.append([zi, cx, cy, float(conf)])
    timings["seconds_collect_xyxy_centroids"] = round(time.perf_counter() - t0, 6)
    timings["num_slices_in_summary"] = n_slices_doc
    timings["num_detections"] = len(rows)
    timings["mip_shape_hw"] = [h_m, w_m]
    log.info(
        "centroids: %d from %d slice rows in %.4fs | slices with ≥1 box: %d | empty slice rows: %d",
        len(rows),
        n_slices_doc,
        timings["seconds_collect_xyxy_centroids"],
        nz_sl,
        n_slices_doc - nz_sl,
    )
    if short_records:
        log.warning("skipped %d box records with <5 fields", short_records)
    if len(rows) == 0:
        log.warning("no detections — output MIP will have no centroid markers")
    if counts_per_slice:
        log.debug("per-slice box count min=%s max=%s", min(counts_per_slice), max(counts_per_slice))

    timings["fuse_3d"] = args.fuse_3d
    timings["fuse_max_dz"] = args.fuse_max_dz
    timings["fuse_max_dxy_px"] = args.fuse_max_dxy_px
    timings["mip_markers"] = args.mip_markers

    log.info("--- Step 6b/9: Heuristic 3D fusion ---")
    t_fuse = time.perf_counter()
    if args.fuse_3d:
        draw_rows, fuse_stats = fuse_slice_detections_to_3d_centroids(
            rows,
            max_dz=args.fuse_max_dz,
            max_dxy_px=args.fuse_max_dxy_px,
            log=log,
        )
        timings["num_raw_detections"] = int(fuse_stats.get("num_raw", 0))
        timings["num_fused_3d"] = int(fuse_stats.get("num_fused", 0))
        timings["fuse_max_merge_size"] = int(fuse_stats.get("max_merge_size", 1))
    else:
        draw_rows = [[float(z), cx, cy, conf, 1.0] for z, cx, cy, conf in rows]
        timings["num_raw_detections"] = len(rows)
        timings["num_fused_3d"] = len(draw_rows)
        timings["fuse_max_merge_size"] = 1
        log.info("--no-fuse-3d: %d per-slice centres (no cross-z merging)", len(draw_rows))
    timings["seconds_fuse_3d"] = round(time.perf_counter() - t_fuse, 6)

    log.info(
        "--- Step 6c/9: MIP marker plan | slice-box=%d post-fuse=%d | mip-markers=%s ---",
        len(rows),
        len(draw_rows),
        args.mip_markers,
    )
    if args.fuse_3d and len(draw_rows) * 4 < len(rows) and args.mip_markers == "fused":
        log.warning(
            "Only %d fused markers for %d slice boxes — MIP can look sparse. "
            "Try --mip-markers both (default) or raw; or --fuse-max-dxy-px 8; or lower YOLO --conf.",
            len(draw_rows),
            len(rows),
        )

    # Cyan BGR matches infer_volume_slices_yolo predicted_boxes_cyan.
    raw_underlay_bgr = (255, 255, 0)
    r_raw = max(2, int(args.radius) - 1) if int(args.radius) > 1 else 2

    log.info(
        "--- Step 7/9: Draw MIP | mip-markers=%s | line_width=%s | colour=%s ---",
        args.mip_markers,
        args.line_width_centroid,
        "z→gradient" if args.colour_centroids_by_z else f"RGB{centroid_rgb}",
    )
    t0 = time.perf_counter()
    n_clipped = 0
    n_drawn = 0

    def _draw_one(cx: float, cy: float, z_for_colour: float, clr: tuple[int, int, int], rad: int) -> None:
        nonlocal n_clipped, n_drawn
        col_raw = int(round(cx))
        row_raw = int(round(cy))
        col = min(max(col_raw, 0), w_m - 1)
        row = min(max(row_raw, 0), h_m - 1)
        if col_raw != col or row_raw != row:
            n_clipped += 1
        zi = int(round(z_for_colour))
        if args.colour_centroids_by_z:
            clr = z_to_bgr(zi, z_max_coord)
        cv2.circle(
            canvas,
            (col, row),
            rad,
            clr,
            thickness=args.line_width_centroid,
            lineType=cv2.LINE_AA,
        )
        n_drawn += 1

    mm = args.mip_markers
    if mm in ("raw", "both"):
        # Raw = every 2D box centre (what YOLO gave on each slice).
        for zi, cx, cy, _cf in rows:
            if mm == "both" and args.fuse_3d:
                _draw_one(cx, cy, float(zi), raw_underlay_bgr, r_raw)
            else:
                _draw_one(cx, cy, float(zi), centroid_bgr, int(args.radius))

    # Fused dots only once; skip second layer when both + no-fuse-3d (same as raw).
    if mm == "fused" or (mm == "both" and args.fuse_3d):
        for zf, cx, cy, _conf, _nm in draw_rows:
            _draw_one(cx, cy, zf, centroid_bgr, int(args.radius))

    timings["seconds_draw_centroids_opencv"] = round(time.perf_counter() - t0, 6)
    log.info(
        "drew %d circles in %.4fs (%d clipped to MIP bounds)",
        n_drawn,
        timings["seconds_draw_centroids_opencv"],
        n_clipped,
    )

    log.info("--- Step 8/9: Write PNG ---")
    args.out_png.parent.mkdir(parents=True, exist_ok=True)
    log.info("ensure parent dir exists: %s", args.out_png.parent.resolve())
    t0 = time.perf_counter()
    cv2.imwrite(str(args.out_png), canvas)
    timings["seconds_cv2_imwrite_png"] = round(time.perf_counter() - t0, 6)
    log.info(
        "wrote PNG %s in %.4fs",
        args.out_png.resolve(),
        timings["seconds_cv2_imwrite_png"],
    )

    timings["seconds_export_csv"] = None
    if args.export_csv is not None:
        log.info("--- Step 9a: Export CSV ---")
        lines = ["z,cx,cy,conf_max,x_pixel,y_pixel,n_merged"]
        for zf, cx, cy, cf, nm in draw_rows:
            col = min(max(int(round(cx)), 0), w_m - 1)
            row = min(max(int(round(cy)), 0), h_m - 1)
            lines.append(
                f"{zf:.6f},{cx:.6f},{cy:.6f},{cf:.6f},{col},{row},{int(nm)}"
            )
        t0 = time.perf_counter()
        args.export_csv.parent.mkdir(parents=True, exist_ok=True)
        args.export_csv.write_text("\n".join(lines) + "\n", encoding="utf-8")
        timings["seconds_export_csv"] = round(time.perf_counter() - t0, 6)
        log.info(
            "wrote %d rows (%s bytes) → %s in %.4fs",
            len(lines),
            args.export_csv.stat().st_size,
            args.export_csv.resolve(),
            timings["seconds_export_csv"],
        )
    else:
        log.info("--- Step 9a: skip CSV (--export_csv not set) ---")

    timings["seconds_export_mat"] = None
    if args.export_mat is not None:
        log.info("--- Step 9b: Export MATLAB .mat ---")
        t0 = time.perf_counter()
        label_vol = paint_label_volume_uint16(
            (int(volume.shape[0]), int(volume.shape[1]), int(volume.shape[2])),
            draw_rows,
            crop_z_offset=crop_z_offset,
            radius_xy=max(0, int(args.label_radius_xy)),
            radius_z=max(0, int(args.label_radius_z)),
            log=log,
        )
        export_centroids_mat(
            args.export_mat,
            label_vol=label_vol,
            draw_rows=draw_rows,
            volume_full_shape_pre_crop=volume_full_shape_xyz,
            volume_shape_numpy=(
                int(volume.shape[0]),
                int(volume.shape[1]),
                int(volume.shape[2]),
            ),
            crop_z_offset=crop_z_offset,
            summary_path_str=str(Path(args.summary).resolve()),
            volume_path_str=str(vol_path.resolve()),
            fuse_3d=bool(args.fuse_3d),
            fuse_max_dz=int(args.fuse_max_dz),
            fuse_max_dxy_px=float(args.fuse_max_dxy_px),
            label_radius_xy=max(0, int(args.label_radius_xy)),
            label_radius_z=max(0, int(args.label_radius_z)),
        )
        timings["seconds_export_mat"] = round(time.perf_counter() - t0, 6)
        timings["export_mat_path"] = str(args.export_mat.resolve())
        log.info(
            "wrote MAT %s (%d bytes) in %.4fs",
            args.export_mat.resolve(),
            args.export_mat.stat().st_size,
            timings["seconds_export_mat"],
        )
    else:
        log.info("--- Step 9b: skip MATLAB .mat (--export-mat not set) ---")

    scale_um = (
        float(args.neuropal_scale_um[0]),
        float(args.neuropal_scale_um[1]),
        float(args.neuropal_scale_um[2]),
    )
    neuropal_transpose_xy = not bool(args.neuropal_keep_numpy_axes)

    timings["seconds_export_neuropal_gui_mat"] = None
    if args.export_neuropal_gui_mat is not None:
        log.info("--- Step 9d: NeuroPAL GUI bundle (volume .mat + _ID.mat) ---")
        t0 = time.perf_counter()
        vol_out, id_out = export_neuropal_gui_mat_bundle(
            args.export_neuropal_gui_mat,
            volume=volume,
            draw_rows=draw_rows,
            crop_z_offset=crop_z_offset,
            summary_path_str=str(Path(args.summary).resolve()),
            volume_path_str=str(vol_path.resolve()),
            fuse_3d=bool(args.fuse_3d),
            fuse_max_dz=int(args.fuse_max_dz),
            fuse_max_dxy_px=float(args.fuse_max_dxy_px),
            scale_um=scale_um,
            neuropal_np_version=float(args.neuropal_volume_version),
            neuropal_gamma=float(args.neuropal_gamma),
            worm_body=str(args.worm_body),
            worm_age=str(args.worm_age),
            worm_sex=str(args.worm_sex),
            worm_strain=str(args.worm_strain),
            worm_notes=str(args.worm_notes),
            transpose_xy_for_neuropal=neuropal_transpose_xy,
            log=log,
        )
        timings["seconds_export_neuropal_gui_mat"] = round(time.perf_counter() - t0, 6)
        timings["export_neuropal_gui_volume_mat"] = str(vol_out.resolve())
        timings["export_neuropal_gui_id_mat"] = str(id_out.resolve())
        log.info(
            "NeuroPAL GUI: open THIS file in visualize_light (not *_ID.mat alone): %s (%d bytes)",
            vol_out.resolve(),
            vol_out.stat().st_size,
        )
        log.info(
            "NeuroPAL GUI sidecar (auto): %s (%d bytes) · wrote both in %.4fs",
            id_out.resolve(),
            id_out.stat().st_size,
            timings["seconds_export_neuropal_gui_mat"],
        )
    else:
        log.info("--- Step 9d: skip NeuroPAL GUI bundle (--export-neuropal-gui-mat not set) ---")

    skip_duplicate_id = False
    if args.export_neuropal_gui_mat is not None and args.export_neuropal_id_mat is not None:
        if args.export_neuropal_id_mat.resolve() == neuropal_id_mat_path_for_volume_mat(
            args.export_neuropal_gui_mat
        ).resolve():
            skip_duplicate_id = True
            log.info("--export-neuropal-id-mat path matches GUI sidecar; skipping duplicate write.")

    timings["seconds_export_neuropal_id_mat"] = None
    if args.export_neuropal_id_mat is not None and not skip_duplicate_id:
        log.info("--- Step 9c: Export NeuroPAL detection _ID.mat (standalone sidecar) ---")
        t0 = time.perf_counter()
        export_neuropal_detection_id_mat(
            args.export_neuropal_id_mat,
            draw_rows=draw_rows,
            volume_shape_row_col_z=(
                int(volume.shape[0]),
                int(volume.shape[1]),
                int(volume.shape[2]),
            ),
            crop_z_offset=crop_z_offset,
            summary_path_str=str(Path(args.summary).resolve()),
            volume_path_str=str(vol_path.resolve()),
            fuse_3d=bool(args.fuse_3d),
            fuse_max_dz=int(args.fuse_max_dz),
            fuse_max_dxy_px=float(args.fuse_max_dxy_px),
            volume=volume,
            scale_um=scale_um,
            transpose_xy_for_neuropal=neuropal_transpose_xy,
            log=log,
        )
        timings["seconds_export_neuropal_id_mat"] = round(time.perf_counter() - t0, 6)
        tid = args.export_neuropal_id_mat.resolve()
        log.info(
            "wrote NeuroPAL ID MAT %s (%d bytes) in %.4fs — beside an existing NP volume *.mat, open that volume.",
            tid,
            args.export_neuropal_id_mat.stat().st_size,
            timings["seconds_export_neuropal_id_mat"],
        )
    else:
        log.info(
            "--- Step 9c: skip standalone NeuroPAL _ID.mat (--export-neuropal-id-mat unset or gui bundle owns path) ---"
        )

    wall_total = time.perf_counter() - t_wall0
    timings["seconds_wall_total_script"] = round(wall_total, 6)

    timing_path = args.timing_json
    if timing_path is None:
        timing_path = args.out_png.parent / f"{args.out_png.stem}_mip_centroids_timing.json"

    accounted = (
        float(timings["seconds_read_summary_json"])
        + float(timings["seconds_load_numpy_volume"])
        + float(timings.get("seconds_crop_z_to_summary") or 0.0)
        + float(timings["seconds_build_z_mip"])
        + float(timings["seconds_collect_xyxy_centroids"])
        + float(timings.get("seconds_fuse_3d") or 0.0)
        + float(timings["seconds_draw_centroids_opencv"])
        + float(timings["seconds_cv2_imwrite_png"])
        + float(timings["seconds_export_csv"] or 0.0)
        + float(timings["seconds_export_mat"] or 0.0)
        + float(timings.get("seconds_export_neuropal_id_mat") or 0.0)
        + float(timings.get("seconds_export_neuropal_gui_mat") or 0.0)
    )
    timings["seconds_unattributed_approx"] = round(max(0.0, wall_total - accounted), 6)

    log.info(
        "--- Step 9e: Write timing JSON ---\ntarget=%s accounted≈%.4fs wall=%.4fs unattributed≈%.4fs",
        timing_path.resolve(),
        accounted,
        wall_total,
        timings["seconds_unattributed_approx"],
    )
    timing_path.parent.mkdir(parents=True, exist_ok=True)
    timing_path.write_text(json.dumps(timings, indent=2), encoding="utf-8")
    log.info("timing JSON saved (%d keys)", len(timings))

    log.info(
        "SUMMARY wall_total=%.4fs mip=%s draw=%s png=%s",
        wall_total,
        timings["seconds_build_z_mip"],
        timings["seconds_draw_centroids_opencv"],
        timings["seconds_cv2_imwrite_png"],
    )

    summary_line = (
        f"[ok] raw {len(rows)} → fused {len(draw_rows)} centroids · wall {wall_total:.4f}s "
        f"(mip {timings['seconds_build_z_mip']}s · fuse {timings.get('seconds_fuse_3d', 0)}s · draw {timings['seconds_draw_centroids_opencv']}s) · {args.out_png}"
    )
    log.info(summary_line)
    print(summary_line)


if __name__ == "__main__":
    main()
