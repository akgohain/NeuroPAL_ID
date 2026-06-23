#!/usr/bin/env python3
"""
XY | XZ | YZ Maximum-Intensity projections with **merged** 2D YOLO boxes in **yellow**.

**TA / spec alignment (same script):**

- **MIPs come from the volume only** — max projections over the orthogonal axis (RGB per channel).
  Overlays never change the mip pixels.
- **3D merge** (when ``--fuse-3d``): choose ``--fuse-mode euclidean`` (default) = centroid distance
  like ``mip_centroids_from_predictions_summary`` (|Δz|≤``--fuse-max-dz``, √(Δx²+Δy²)≤``--fuse-max-dxy-px``),
  or ``--fuse-mode iou-color`` = **same as** ``mip_centroids_iou_color_fuse`` (IoU≥``--iou-min``, |Δz|≤``--fuse-max-dz``,
  optional RGB cosine on box crops via ``--color-dot-min`` unless ``--no-color-match``), then optional
  depth sanity filter in µm (``--depth-sanity-ratio-cap`` / ``--no-depth-sanity``).
- **One fused object per cluster** after grouping.
  **Default** ``--fused-box-style envelope``: XY rectangle = axis-aligned hull of **every** merged slice box
  X/Y extent; side panels span **[min(x₁),max(x₂)]** on XZ, **[min(y₁),max(y₂)]** on YZ with **z** span
  **[z_min,z_max]** — all linked detections stay inside the outline. Legacy ``centroid-maxwh``: conf-weighted
  centre ± ``max(width)×max(height)`` (slice-box corners can fall outside).
- **Panel captions** are intentionally tiny: just **XY / XZ / YZ** on a **narrow** top strip so the
  worm stays visible (fuse stats always print to stdout + timing JSON). Add ``--fusion-proof`` if you
  also want brief stats on the XY panel and `#id` chips on boxes.
- Optional ``--show-fused-centroids``: filled disks at XY ``(cx,cy)``, XZ ``(cx,z_mean)``, YZ ``(cy,z_mean)``
  (see ``--centroid-bgr`` / radii). Add ``--centroids-separate-panels`` to write **centroid-only** MIPs as extra
  PNGs (no yellow boxes) instead of overlaying dots on the box figures. Zoomed ``*_centroids_only_view_*``
  disks use ``--centroids-only-split-radius`` (default smaller than ``--split-centroid-radius``).

**Triptych layout:** default ``--side-panels match-xy-frame`` letterboxes XZ & YZ to ``ny×nx`` beside XY.

**Split exports:** ``--save-split-views`` writes three full PNGs next to ``--out_png``; XZ/YZ use
uniform ``--split-view-zoom`` and extra vertical ``--split-view-z-stretch`` (display-only, not metric).
``--split-view-label-gap`` (default 10) inserts blank rows between the plane title and the MIP so the bar
does not cover the top of the projection; use ``0`` for legacy flush layout.
**Per-Z XY PNGs:** ``--export-fused-xy-slices-dir DIR`` writes ``slice_{z:05d}_xy_merged_yellow.png`` for each
plane in the (possibly cropped) volume — same yellow XY rectangles as the triptych (``--fuse-mode iou-color``
or euclidean; ``--fused-box-style`` / ``--line-thickness``). Optional ``--stretch-fused-slices`` uses
``--p_lo`` / ``--p_hi`` per slice like a 2D percentile stretch. Standalone ``viz_iou_fused_yellow_per_slice.py``
remains available for IoU-only runs without building MIPs.
**Fused 3D .mat:** ``--export-fused-3d-mat OUT.mat`` writes **tables only** (not visualize_light-openable).
For NeuroPAL GUI use ``--export-neuropal-gui-mat OUT.mat`` (full ``data``/``info``/… bundle + centroids +
optional fused AABB extras). ``--export-fused-3d-mat-label-vol`` adds a uint16 label stack for MATLAB.
Yellow outlines on split XZ/YZ are drawn **after** upscale (``--split-view-line-thickness``, default 1) so
nearest-neighbor zoom does not turn 1-pixel strokes into thick bands. Shallow ``nz`` stacks get
``--split-min-native-side-pixels`` (minimum native box width/height) plus optional
``--split-view-fill-alpha`` translucent tint so rectangles are not just two ruling lines.

XZ/YZ default stretch with ``--stretch_mip`` uses **percentiles 0.25–99.75**, stronger **CLAHE**
(clip≈3), then a light **unsharp** (``--side-mip-sharpen``≈0.42) for shallow-``nz`` stacks.

Default **yellow** outline: ``--line-thickness 1`` (``LINE_8``).

BGR yellow = `(0, 255, 255)`.

Thin ``nz`` XZ/YZ mips upscaled heavily with **cubic** resize look smoky; split exports default to
``--split-view-interp nearest`` (blocky pixels, much clearer structure).

Usage (from ``yolov8-cell``):
  python viz_mip_merged_yellow_boxes.py \\
    --summary results/.../predictions_summary.json \\
    --out_png results/.../triptych_merged_yellow.png \\
    --stretch_mip \\
    --fuse-max-dz 1 --fuse-max-dxy-px 6

  # Also write ``*_view_*.png``; nearest enlarge avoids cubic blur on thin-``nz`` stacks:
  python viz_mip_merged_yellow_boxes.py \\
    ... --save-split-views --split-view-zoom 4 --split-view-z-stretch 3 \\
    --split-view-interp nearest --split-view-post-sharpen 0.35

  # IoU + RGB cosine fusion (same logic as mip_centroids_iou_color_fuse.py):
  python viz_mip_merged_yellow_boxes.py \\
    --fuse-mode iou-color --iou-min 0.9 --fuse-max-dz 1 \\
    ... --summary ... --out_png ... --stretch_mip

  # Same IoU fuse + one yellow-overlay PNG per Z (XY plane), matching triptych boxes:
  python viz_mip_merged_yellow_boxes.py \\
    --fuse-mode iou-color --iou-min 0.9 --fuse-max-dz 1 \\
    ... --summary ... --out_png .../triptych_merged_yellow.png \\
    --export-fused-xy-slices-dir .../yellow_xy_per_z --stretch-fused-slices
"""

from __future__ import annotations

import argparse
import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

import cv2
import numpy as np

from mip_centroids_iou_color_fuse import (
    Detection,
    crop_box_rgb,
    depth_sanity_ok,
    feature_percentiles,
    fuse_components,
    kde_peak_per_channel,
)
from mip_centroids_from_predictions_summary import (
    _DSU,
    _linked_2d_slice_pair,
    _summary_z_window,
    export_neuropal_gui_mat_bundle,
    load_volume,
    mip_rgb_bgr,
    mip_rgb_bgr_torch_cuda,
)

YELLOW_BGR = (0, 255, 255)
# LINE_8 keeps 1-pixel stroked boxes visually thin; LINE_AA anti-aliases and widens edges.
_LINE_YELLOW = cv2.LINE_8


def _stretch_rgb_plane_to_bgr(mip_rgb: np.ndarray, *, pct: bool, p_lo: float, p_hi: float) -> np.ndarray:
    """mip_rgb: float HWC RGB after max projection; optional percentile stretch; return uint8 BGR."""
    mip = np.asarray(mip_rgb, dtype=np.float32)
    out = np.empty_like(mip, dtype=np.float32)
    if pct:
        for c in range(3):
            ch = mip[..., c]
            lo, hi = np.percentile(ch, [p_lo, p_hi])
            if hi <= lo + 1e-6:
                lo, hi = float(np.nanmin(ch)), float(np.nanmax(ch)) + 1e-6
            out[..., c] = np.clip((ch - lo) / (hi - lo) * 255.0, 0, 255)
    else:
        for c in range(3):
            mx = float(np.nanmax(mip[..., c])) + 1e-9
            out[..., c] = np.clip(mip[..., c] / mx * 255.0, 0, 255)
    rgb_u8 = out.astype(np.uint8)
    return cv2.cvtColor(rgb_u8, cv2.COLOR_RGB2BGR)


def _side_mip_lab_clahe(bgr: np.ndarray, *, clip_limit: float = 3.0) -> np.ndarray:
    """Boost local contrast on XZ/YZ (orthogonal max-MIPs tend to look flat vs XY Z-max)."""
    if bgr.size == 0:
        return bgr
    h, w = int(bgr.shape[0]), int(bgr.shape[1])
    # Smaller tiles when nz is shallow so contrast adapts along the short Z axis.
    if h <= 36:
        th = max(3, min(8, h // 2))
        tw = max(4, min(20, max(8, w // 6)))
    else:
        tw = int(np.clip(w // 12, 4, min(24, w)))
        th = int(np.clip(max(4, h // 4), 4, min(16, h)))
    tw = max(2, min(tw, w))
    th = max(2, min(th, h))
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    l_ch, a_ch, b_ch = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=float(clip_limit), tileGridSize=(tw, th))
    l2 = clahe.apply(l_ch)
    out = cv2.cvtColor(cv2.merge((l2, a_ch, b_ch)), cv2.COLOR_LAB2BGR)
    return np.asarray(out, dtype=np.uint8)


def _side_mip_unsharp_bgr(bgr: np.ndarray, *, amount: float, sigma: float = 0.95) -> np.ndarray:
    """Mild high-frequency boost after upscaling thin Z mips (reduces watercolor mush)."""
    if bgr.size == 0 or amount <= 1e-6:
        return bgr
    amt = float(np.clip(amount, 0.0, 3.0))
    sig = float(max(0.25, sigma))
    blur = cv2.GaussianBlur(bgr, (0, 0), sigmaX=sig, sigmaY=sig)
    out = cv2.addWeighted(bgr.astype(np.float32), 1.0 + amt, blur.astype(np.float32), -amt, 0.0)
    return np.asarray(np.clip(out, 0, 255), dtype=np.uint8)


def mip_xz_rgb_bgr(
    volume: np.ndarray,
    *,
    percentile_stretch: bool,
    p_lo: float,
    p_hi: float,
) -> np.ndarray:
    """Volume (ny,nx,nz,c); max over y → RGB (nz,nx) rows=z cols=x."""
    if volume.shape[-1] < 3:
        raise ValueError("Need ≥3 channels for RGB MIPs")
    v = volume.astype(np.float32)[..., :3]
    mip_nxnz = np.max(v, axis=0).transpose(1, 0, 2)  # (nz, nx, 3)
    return _stretch_rgb_plane_to_bgr(mip_nxnz, pct=percentile_stretch, p_lo=p_lo, p_hi=p_hi)


def mip_yz_rgb_bgr(
    volume: np.ndarray,
    *,
    percentile_stretch: bool,
    p_lo: float,
    p_hi: float,
) -> np.ndarray:
    """Volume (ny,nx,nz,c); max over x → RGB (nz,ny) rows=z cols=y."""
    if volume.shape[-1] < 3:
        raise ValueError("Need ≥3 channels for RGB MIPs")
    v = volume.astype(np.float32)[..., :3]
    mip_nynz = np.max(v, axis=1).transpose(1, 0, 2)  # (nz, ny, 3)
    return _stretch_rgb_plane_to_bgr(mip_nynz, pct=percentile_stretch, p_lo=p_lo, p_hi=p_hi)


@dataclass
class RawBox:
    z: int
    x1: float
    y1: float
    x2: float
    y2: float
    cx: float
    cy: float
    conf: float


def _collect_raw_boxes(summary: dict[str, Any]) -> tuple[list[RawBox], int]:
    short_records = 0
    boxes: list[RawBox] = []
    for block in summary.get("slices") or []:
        zi = int(block["z"])
        for rec in block.get("boxes_xyxy_conf") or []:
            if len(rec) < 5:
                short_records += 1
                continue
            x1, y1, x2, y2, conf = float(rec[0]), float(rec[1]), float(rec[2]), float(rec[3]), float(rec[4])
            boxes.append(
                RawBox(z=zi, x1=x1, y1=y1, x2=x2, y2=y2, cx=(x1 + x2) / 2.0, cy=(y1 + y2) / 2.0, conf=conf)
            )
    return boxes, short_records


def fuse_boxes_into_groups(
    raw: Sequence[RawBox],
    *,
    max_dz: int,
    max_dxy_px: float,
    log: logging.Logger | None = None,
) -> tuple[list[list[int]], dict[str, Any]]:
    """Return disjoint member index lists via same DSU as centroid fuse (uses box centres per row)."""
    stats: dict[str, Any] = {"num_raw": len(raw)}
    if not raw:
        stats["num_groups"] = 0
        return [], stats

    rows = [[float(b.z), b.cx, b.cy, b.conf] for b in raw]
    n = len(rows)
    dsu = _DSU(n)
    for i in range(n):
        zi, xi, yi, _ = rows[i]
        for j in range(i + 1, n):
            zj, xj, yj, _ = rows[j]
            if _linked_2d_slice_pair(zi, xi, yi, zj, xj, yj, max_dz=max_dz, max_dxy_px=max_dxy_px):
                dsu.union(i, j)

    groups_map: dict[int, list[int]] = {}
    for i in range(n):
        groups_map.setdefault(dsu.find(i), []).append(i)

    groups = list(groups_map.values())
    stats["num_groups"] = len(groups)
    stats["max_merge_size"] = max((len(g) for g in groups), default=1)
    if log:
        log.info(
            "box fuse (same rules as centroid): %d boxes → %d groups (max_dz=%s max_dxy=%s largest=%d)",
            n,
            len(groups),
            max_dz,
            max_dxy_px,
            stats["max_merge_size"],
        )
    return groups, stats


@dataclass
class FusedMergeBox:
    cx: float
    cy: float
    z_mean: float
    z_min: int
    z_max: int
    w_max: float
    h_max: float
    conf_max: float
    n_merge: int
    #: Axis-aligned hull of member boxes in XY (used by ``--fused-box-style envelope``).
    x1u: float
    y1u: float
    x2u: float
    y2u: float


def _groups_to_fused_merges(raw: list[RawBox], groups: list[list[int]]) -> list[FusedMergeBox]:
    out: list[FusedMergeBox] = []
    for members in groups:
        ws = [max(0.0, raw[i].x2 - raw[i].x1) for i in members]
        hs = [max(0.0, raw[i].y2 - raw[i].y1) for i in members]
        zs_int = [raw[i].z for i in members]
        confs = np.array([raw[i].conf for i in members], dtype=np.float64)
        wsum = float(confs.sum())
        if wsum <= 0:
            ww = np.ones(len(members), dtype=np.float64) / len(members)
        else:
            ww = confs / wsum

        zs_f = np.array([float(raw[i].z) for i in members], dtype=np.float64)
        xs = np.array([raw[i].cx for i in members], dtype=np.float64)
        ys = np.array([raw[i].cy for i in members], dtype=np.float64)

        x1_lo = float(min(min(raw[i].x1, raw[i].x2) for i in members))
        y1_lo = float(min(min(raw[i].y1, raw[i].y2) for i in members))
        x2_hi = float(max(max(raw[i].x1, raw[i].x2) for i in members))
        y2_hi = float(max(max(raw[i].y1, raw[i].y2) for i in members))

        out.append(
            FusedMergeBox(
                cx=float(np.dot(xs, ww)),
                cy=float(np.dot(ys, ww)),
                z_mean=float(np.dot(zs_f, ww)),
                z_min=int(min(zs_int)),
                z_max=int(max(zs_int)),
                w_max=float(max(ws)),
                h_max=float(max(hs)),
                conf_max=float(np.max(confs)),
                n_merge=len(members),
                x1u=x1_lo,
                y1u=y1_lo,
                x2u=x2_hi,
                y2u=y2_hi,
            )
        )
    out.sort(key=lambda b: (b.z_mean, b.cy, b.cx))
    return out


def _fuse_iou_color_into_fused(
    raw_use: list[RawBox],
    volume: np.ndarray,
    *,
    fuse_max_dz: int,
    iou_min: float,
    require_color: bool,
    color_feature: str,
    color_percentiles: Sequence[float],
    color_dot_min: float,
    kde_bin_count_min: int,
    kde_bandwidth_bins: float,
    voxel_spacing_um: tuple[float, float, float],
    depth_sanity_ratio_cap: float,
    no_depth_sanity: bool,
    log: logging.Logger,
    verbose: bool,
) -> tuple[list[FusedMergeBox], dict[str, Any]]:
    """
    Same pipeline as ``mip_centroids_iou_color_fuse.main`` fuse + depth filter; returns
    ``FusedMergeBox`` list for yellow rectangles (indices align with ``raw_use``).
    """
    dets = [Detection(b.z, b.x1, b.y1, b.x2, b.y2, b.conf) for b in raw_use]
    feats: list[np.ndarray] | None = None
    if require_color:
        feats = []
        for d in dets:
            zi_loc = int(d.z)
            px = crop_box_rgb(volume, zi_loc, d.x1, d.y1, d.x2, d.y2)
            if px.size == 0:
                feats.append(
                    np.zeros((9 if color_feature == "percentiles" else 3), dtype=np.float64)
                )
                continue
            if color_feature == "percentiles":
                v = feature_percentiles(px, color_percentiles)
                feats.append(v)
            else:
                v = kde_peak_per_channel(
                    px,
                    nbins_floor=int(kde_bin_count_min),
                    bandwidth_bins=float(kde_bandwidth_bins),
                )
                feats.append(v)
        log.info(
            "iou-color: built %s features for %d boxes",
            color_feature,
            len(dets),
        )

    groups, fuse_stats = fuse_components(
        dets,
        feats,
        max_dz=int(fuse_max_dz),
        iou_min=float(iou_min),
        require_color=bool(require_color),
        color_dot_min=float(color_dot_min),
        log=log,
    )

    sx_um, sy_um, sz_um = (float(voxel_spacing_um[i]) for i in range(3))
    kept_groups: list[list[int]] = []
    n_reject = 0
    dbg_log = log if verbose else None
    for g in groups:
        sub = [dets[i] for i in g]
        if not no_depth_sanity and not depth_sanity_ok(
            sub, sx_um, sy_um, sz_um, float(depth_sanity_ratio_cap), log=dbg_log
        ):
            n_reject += 1
            continue
        kept_groups.append(g)

    fused = _groups_to_fused_merges(raw_use, kept_groups)
    gst: dict[str, Any] = dict(fuse_stats)
    gst["depth_sanity_rejected_components"] = int(n_reject)
    gst["num_groups_after_depth_sanity"] = len(kept_groups)
    gst["fuse_mode"] = "iou-color"
    gst["iou_min"] = float(iou_min)
    gst["require_color"] = bool(require_color)
    gst["color_dot_min"] = float(color_dot_min)
    max_sz = max((len(g) for g in kept_groups), default=1)
    gst["max_merge_size"] = int(max_sz)
    log.info(
        "iou-color: %d raw → %d components → %d after depth sanity (max merge %d)",
        len(raw_use),
        len(groups),
        len(kept_groups),
        max_sz,
    )
    return fused, gst


def _xy_rect_from_centre(hw_b: FusedMergeBox, ny: int, nx: int) -> tuple[int, int, int, int]:
    half_w = hw_b.w_max / 2.0
    half_h = hw_b.h_max / 2.0
    x1 = int(np.floor(hw_b.cx - half_w))
    y1 = int(np.floor(hw_b.cy - half_h))
    x2 = int(np.ceil(hw_b.cx + half_w))
    y2 = int(np.ceil(hw_b.cy + half_h))
    x1 = int(np.clip(x1, 0, nx - 1))
    x2 = int(np.clip(x2, 0, nx - 1))
    y1 = int(np.clip(y1, 0, ny - 1))
    y2 = int(np.clip(y2, 0, ny - 1))
    if x2 < x1:
        x1, x2 = x2, x1
    if y2 < y1:
        y1, y2 = y2, y1
    return x1, y1, x2, y2


def _xy_rect_envelope(fb: FusedMergeBox, ny: int, nx: int) -> tuple[int, int, int, int]:
    """XY hull spanning all fused slice rectangles (clips to image bounds)."""
    x1 = int(np.floor(min(fb.x1u, fb.x2u)))
    y1 = int(np.floor(min(fb.y1u, fb.y2u)))
    x2 = int(np.ceil(max(fb.x1u, fb.x2u)))
    y2 = int(np.ceil(max(fb.y1u, fb.y2u)))
    x1 = int(np.clip(x1, 0, nx - 1))
    x2 = int(np.clip(x2, 0, nx - 1))
    y1 = int(np.clip(y1, 0, ny - 1))
    y2 = int(np.clip(y2, 0, ny - 1))
    if x2 < x1:
        x1, x2 = x2, x1
    if y2 < y1:
        y1, y2 = y2, y1
    return x1, y1, x2, y2


def _xz_rect(fb: FusedMergeBox, nz: int, nx: int) -> tuple[int, int, int, int]:
    """OpenCV (col=x, row=z)."""
    half_w = fb.w_max / 2.0
    xc1 = int(np.floor(fb.cx - half_w))
    xc2 = int(np.ceil(fb.cx + half_w))
    xr1 = int(np.clip(min(fb.z_min, fb.z_max), 0, nz - 1))
    xr2 = int(np.clip(max(fb.z_min, fb.z_max), 0, nz - 1))
    xc1 = int(np.clip(xc1, 0, nx - 1))
    xc2 = int(np.clip(xc2, 0, nx - 1))
    if xc2 < xc1:
        xc1, xc2 = xc2, xc1
    if xr2 < xr1:
        xr1, xr2 = xr2, xr1
    return xc1, xr1, xc2, xr2


def _yz_rect(fb: FusedMergeBox, nz: int, ny: int) -> tuple[int, int, int, int]:
    """OpenCV (col=y-row, row=z). Same row index convention as XY (y grows down)."""
    half_h = fb.h_max / 2.0
    yc1 = int(np.floor(fb.cy - half_h))
    yc2 = int(np.ceil(fb.cy + half_h))
    zr1 = int(np.clip(min(fb.z_min, fb.z_max), 0, nz - 1))
    zr2 = int(np.clip(max(fb.z_min, fb.z_max), 0, nz - 1))
    yc1 = int(np.clip(yc1, 0, ny - 1))
    yc2 = int(np.clip(yc2, 0, ny - 1))
    if yc2 < yc1:
        yc1, yc2 = yc2, yc1
    if zr2 < zr1:
        zr1, zr2 = zr2, zr1
    return yc1, zr1, yc2, zr2


def _xz_rect_envelope(fb: FusedMergeBox, nz: int, nx: int) -> tuple[int, int, int, int]:
    """OpenCV (col=x, row=z): span ``x`` from hull, ``z`` from cluster extent."""
    xa = float(min(fb.x1u, fb.x2u))
    xb = float(max(fb.x1u, fb.x2u))
    xc1 = int(np.floor(xa))
    xc2 = int(np.ceil(xb))
    xr1 = int(np.clip(min(fb.z_min, fb.z_max), 0, nz - 1))
    xr2 = int(np.clip(max(fb.z_min, fb.z_max), 0, nz - 1))
    xc1 = int(np.clip(xc1, 0, nx - 1))
    xc2 = int(np.clip(xc2, 0, nx - 1))
    if xc2 < xc1:
        xc1, xc2 = xc2, xc1
    if xr2 < xr1:
        xr1, xr2 = xr2, xr1
    return xc1, xr1, xc2, xr2


def _yz_rect_envelope(fb: FusedMergeBox, nz: int, ny: int) -> tuple[int, int, int, int]:
    """Hull span in ``y`` × ``z_min..z_max``."""
    ya = float(min(fb.y1u, fb.y2u))
    yb = float(max(fb.y1u, fb.y2u))
    yc1 = int(np.floor(ya))
    yc2 = int(np.ceil(yb))
    zr1 = int(np.clip(min(fb.z_min, fb.z_max), 0, nz - 1))
    zr2 = int(np.clip(max(fb.z_min, fb.z_max), 0, nz - 1))
    yc1 = int(np.clip(yc1, 0, ny - 1))
    yc2 = int(np.clip(yc2, 0, ny - 1))
    if yc2 < yc1:
        yc1, yc2 = yc2, yc1
    if zr2 < zr1:
        zr1, zr2 = zr2, zr1
    return yc1, zr1, yc2, zr2


def _fused_placeholder_from_slice(b: RawBox) -> FusedMergeBox:
    """One raw YOLO box as a degenerate fused record (same hull as the slice rectangle)."""
    xa, xb = float(min(b.x1, b.x2)), float(max(b.x1, b.x2))
    ya, yb = float(min(b.y1, b.y2)), float(max(b.y1, b.y2))
    return FusedMergeBox(
        cx=b.cx,
        cy=b.cy,
        z_mean=float(b.z),
        z_min=b.z,
        z_max=b.z,
        w_max=max(0.0, xb - xa),
        h_max=max(0.0, yb - ya),
        conf_max=b.conf,
        n_merge=1,
        x1u=xa,
        y1u=ya,
        x2u=xb,
        y2u=yb,
    )


def _draw_raw_boxes_xy(canvas: np.ndarray, raw: list[RawBox], ny: int, nx: int, thickness: int) -> None:
    for b in raw:
        x1 = int(np.clip(round(b.x1), 0, nx - 1))
        y1 = int(np.clip(round(b.y1), 0, ny - 1))
        x2 = int(np.clip(round(b.x2), 0, nx - 1))
        y2 = int(np.clip(round(b.y2), 0, ny - 1))
        if x2 < x1:
            x1, x2 = x2, x1
        if y2 < y1:
            y1, y2 = y2, y1
        cv2.rectangle(canvas, (x1, y1), (x2, y2), YELLOW_BGR, thickness, lineType=_LINE_YELLOW)


def _draw_raw_boxes_xz(canvas: np.ndarray, raw: list[RawBox], nz: int, nx: int, thickness: int) -> None:
    for b in raw:
        xc1, zr1, xc2, zr2 = _xz_rect_envelope(_fused_placeholder_from_slice(b), nz, nx)
        cv2.rectangle(canvas, (xc1, zr1), (xc2, zr2), YELLOW_BGR, thickness, lineType=_LINE_YELLOW)


def _draw_raw_boxes_yz(canvas: np.ndarray, raw: list[RawBox], nz: int, ny: int, thickness: int) -> None:
    for b in raw:
        yc1, zr1, yc2, zr2 = _yz_rect_envelope(_fused_placeholder_from_slice(b), nz, ny)
        cv2.rectangle(canvas, (yc1, zr1), (yc2, zr2), YELLOW_BGR, thickness, lineType=_LINE_YELLOW)


def _uniform_resize_hw(img: np.ndarray, *, target_h: int) -> tuple[np.ndarray, float]:
    """Resize (h,w) → (target_h, round(w*target_h/h)); return scale factor = target_h/h."""
    h, w = img.shape[:2]
    if h <= 0:
        return img, 1.0
    s = float(target_h) / float(h)
    new_w = max(1, int(round(w * s)))
    interp = cv2.INTER_CUBIC if target_h > h else cv2.INTER_AREA
    out = cv2.resize(img, (new_w, target_h), interpolation=interp)
    return out, s


def _letterbox_to(
    img: np.ndarray,
    *,
    out_h: int,
    out_w: int,
    fill: tuple[int, int, int] = (0, 0, 0),
) -> tuple[np.ndarray, float, int, int]:
    """
    Uniformly scale ``img`` to fit inside ``out_h × out_w``, center, pad with ``fill``.
    Returns (canvas, scale, x0, y0) where pixel (col,row) in source maps to
    (x0 + col*s, y0 + row*s) on the canvas (OpenCV x=col, y=row).
    """
    h, w = int(img.shape[0]), int(img.shape[1])
    if h <= 0 or w <= 0:
        raise ValueError("letterbox: empty image")
    s = min(float(out_h) / float(h), float(out_w) / float(w))
    nh = max(1, int(round(h * s)))
    nw = max(1, int(round(w * s)))
    # Upscaling tiny Z mips (few nz planes) stays softer with LINEAR/CUBIC; prefer CUBIC for big zoom.
    interp = cv2.INTER_CUBIC if nh > h or nw > w else cv2.INTER_AREA
    small = cv2.resize(img, (nw, nh), interpolation=interp)
    canvas = np.full((out_h, out_w, 3), fill, dtype=np.uint8)
    y0 = (out_h - nh) // 2
    x0 = (out_w - nw) // 2
    canvas[y0 : y0 + nh, x0 : x0 + nw] = small
    return canvas, float(s), int(x0), int(y0)


def _scale_rect_inplace(
    coords: tuple[int, int, int, int],
    *,
    sx: float,
    sy: float,
) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = coords
    return (
        int(round(x1 * sx)),
        int(round(y1 * sy)),
        int(round(x2 * sx)),
        int(round(y2 * sy)),
    )


def _map_rect_letterbox(
    col1: int,
    row1: int,
    col2: int,
    row2: int,
    *,
    s: float,
    x0: int,
    y0: int,
) -> tuple[int, int, int, int]:
    """Native (col=x, row=z-or-y) → canvas OpenCV coords after letterbox paste."""
    c1 = int(round(x0 + col1 * s))
    r1 = int(round(y0 + row1 * s))
    c2 = int(round(x0 + col2 * s))
    r2 = int(round(y0 + row2 * s))
    return c1, r1, c2, r2


def _map_point_letterbox(col: int, row: int, *, s: float, x0: int, y0: int) -> tuple[int, int]:
    """Single native (col, row) → letterboxed canvas (x, y) OpenCV coords."""
    return int(round(x0 + col * s)), int(round(y0 + row * s))


def _draw_fused_centroids_triptych(
    *,
    xy_bgr: np.ndarray,
    xz_rs: np.ndarray,
    yz_rs: np.ndarray,
    fused: list[FusedMergeBox],
    ny: int,
    nx: int,
    nz: int,
    side_panels: str,
    sxz: float,
    syz: float,
    x0xz: int,
    y0xz: int,
    x0yz: int,
    y0yz: int,
    radius: int,
    bgr: tuple[int, int, int],
) -> None:
    """Conf-weighted XY centres with ``z_mean`` on orthogonal mips (drawn on top of yellow boxes)."""
    r = max(1, int(radius))
    lt = cv2.LINE_AA
    for fb in fused:
        px = int(np.clip(int(round(fb.cx)), 0, nx - 1))
        py = int(np.clip(int(round(fb.cy)), 0, ny - 1))
        cv2.circle(xy_bgr, (px, py), r, bgr, thickness=-1, lineType=lt)

        xc_n = int(np.clip(int(round(fb.cx)), 0, nx - 1))
        z_n = int(np.clip(int(round(fb.z_mean)), 0, nz - 1))
        if side_panels == "match-xy-frame":
            xc, zc = _map_point_letterbox(xc_n, z_n, s=sxz, x0=x0xz, y0=y0xz)
        else:
            xc = int(round(xc_n * sxz))
            zc = int(round(z_n * sxz))
        xc = int(np.clip(xc, 0, xz_rs.shape[1] - 1))
        zc = int(np.clip(zc, 0, xz_rs.shape[0] - 1))
        cv2.circle(xz_rs, (xc, zc), r, bgr, thickness=-1, lineType=lt)

        yc_n = int(np.clip(int(round(fb.cy)), 0, ny - 1))
        if side_panels == "match-xy-frame":
            yc, zz = _map_point_letterbox(yc_n, z_n, s=syz, x0=x0yz, y0=y0yz)
        else:
            yc = int(round(yc_n * syz))
            zz = int(round(z_n * syz))
        yc = int(np.clip(yc, 0, yz_rs.shape[1] - 1))
        zz = int(np.clip(zz, 0, yz_rs.shape[0] - 1))
        cv2.circle(yz_rs, (yc, zz), r, bgr, thickness=-1, lineType=lt)


def _draw_raw_centroids_triptych(
    *,
    xy_bgr: np.ndarray,
    xz_rs: np.ndarray,
    yz_rs: np.ndarray,
    raw_use: list[RawBox],
    ny: int,
    nx: int,
    nz: int,
    side_panels: str,
    sxz: float,
    syz: float,
    x0xz: int,
    y0xz: int,
    x0yz: int,
    y0yz: int,
    radius: int,
    bgr: tuple[int, int, int],
) -> None:
    """Per-slice box centres on all three panels."""
    r = max(1, int(radius))
    lt = cv2.LINE_AA
    for b in raw_use:
        px = int(np.clip(int(round(b.cx)), 0, nx - 1))
        py = int(np.clip(int(round(b.cy)), 0, ny - 1))
        cv2.circle(xy_bgr, (px, py), r, bgr, thickness=-1, lineType=lt)

        xc_n = px
        z_n = int(np.clip(int(round(float(b.z))), 0, nz - 1))
        if side_panels == "match-xy-frame":
            xc, zc = _map_point_letterbox(xc_n, z_n, s=sxz, x0=x0xz, y0=y0xz)
        else:
            xc = int(round(xc_n * sxz))
            zc = int(round(z_n * sxz))
        xc = int(np.clip(xc, 0, xz_rs.shape[1] - 1))
        zc = int(np.clip(zc, 0, xz_rs.shape[0] - 1))
        cv2.circle(xz_rs, (xc, zc), r, bgr, thickness=-1, lineType=lt)

        yc_n = py
        if side_panels == "match-xy-frame":
            yc, zz = _map_point_letterbox(yc_n, z_n, s=syz, x0=x0yz, y0=y0yz)
        else:
            yc = int(round(yc_n * syz))
            zz = int(round(z_n * syz))
        yc = int(np.clip(yc, 0, yz_rs.shape[1] - 1))
        zz = int(np.clip(zz, 0, yz_rs.shape[0] - 1))
        cv2.circle(yz_rs, (yc, zz), r, bgr, thickness=-1, lineType=lt)


def _triptych_label_band_h(
    title: str,
    subtitle: str,
    *,
    extra_lines: tuple[str, ...] = (),
    font_scale: float = 0.7,
    thickness: int = 2,
    line_spacing: int = 21,
    max_band_fraction: float = 0.082,
    max_band_px_cap: int = 92,
    min_band_px: int = 34,
    height_ref: int,
) -> int:
    """Pixel height of the title strip (same math as ``_annotate_triptych_label``)."""
    font = cv2.FONT_HERSHEY_SIMPLEX
    titles: list[str] = [title.strip()] if title.strip() else ["?"]
    if subtitle.strip():
        titles.append(subtitle.strip())
    lines = tuple(titles) + tuple(extra_lines)
    pad_top = 6
    th_draw = max(2, min(8, thickness + 1))
    scales = tuple(max(0.48, font_scale * (0.92 if len(lines) <= 2 else 0.84)) for _ in lines)

    ys_baseline: list[int] = []
    cursor_y = float(pad_top + line_spacing // 5)
    for txt, scl in zip(lines, scales):
        (_tw, hgt), baseline = cv2.getTextSize(txt, font, scl, th_draw)
        bas = cursor_y + float(hgt) + float(baseline) * 0.2
        ys_baseline.append(int(bas))
        cursor_y = bas + float(max(14, line_spacing - 15))

    h_img = int(height_ref)
    ideal_h = int(ys_baseline[-1] + pad_top + 6) if ys_baseline else min_band_px + 20
    cap_h = int(min(max_band_px_cap, max(min_band_px, int(h_img * max_band_fraction + 42))))
    return max(min_band_px + 14, min(ideal_h, cap_h))


def _annotate_triptych_label(
    panel: np.ndarray,
    title: str,
    subtitle: str,
    *,
    extra_lines: tuple[str, ...] = (),
    font_scale: float = 0.7,
    thickness: int = 2,
    line_spacing: int = 21,
    max_band_fraction: float = 0.082,
    max_band_px_cap: int = 92,
    min_band_px: int = 34,
    height_ref_for_band_cap: int | None = None,
) -> int:
    """
    Short opaque caption strip — band height is capped (tiny fraction of H) so neurons stay visible.
    Returns band height in pixels.
    """
    hr = int(height_ref_for_band_cap) if height_ref_for_band_cap is not None else int(panel.shape[0])
    band_h = _triptych_label_band_h(
        title,
        subtitle,
        extra_lines=extra_lines,
        font_scale=font_scale,
        thickness=thickness,
        line_spacing=line_spacing,
        max_band_fraction=max_band_fraction,
        max_band_px_cap=max_band_px_cap,
        min_band_px=min_band_px,
        height_ref=hr,
    )
    font = cv2.FONT_HERSHEY_SIMPLEX
    titles: list[str] = [title.strip()] if title.strip() else ["?"]
    if subtitle.strip():
        titles.append(subtitle.strip())
    lines = tuple(titles) + tuple(extra_lines)
    margin_left = 8
    pad_top = 6
    fg = (246, 246, 250)
    th_draw = max(2, min(8, thickness + 1))
    scales = tuple(max(0.48, font_scale * (0.92 if len(lines) <= 2 else 0.84)) for _ in lines)

    ys_baseline: list[int] = []
    cursor_y = float(pad_top + line_spacing // 5)
    for txt, scl in zip(lines, scales):
        (_tw, hgt), baseline = cv2.getTextSize(txt, font, scl, th_draw)
        bas = cursor_y + float(hgt) + float(baseline) * 0.2
        ys_baseline.append(int(bas))
        cursor_y = bas + float(max(14, line_spacing - 15))

    w_img = int(panel.shape[1])
    if band_h > int(panel.shape[0]):
        band_h = int(panel.shape[0])
    cv2.rectangle(panel, (0, 0), (max(1, w_img - 1), band_h), (26, 26, 30), thickness=-1)
    cv2.rectangle(panel, (0, 0), (max(1, w_img - 1), band_h), (118, 118, 126), thickness=1)

    for txt, scl, oy in zip(lines, scales, ys_baseline):
        if oy >= band_h - 6:
            break
        org = (margin_left, int(oy))
        cv2.putText(panel, txt, org, font, scl, (0, 0, 0), th_draw + 2, cv2.LINE_AA)
        cv2.putText(panel, txt, org, font, scl, fg, th_draw, cv2.LINE_AA)
    return band_h


def _fuse_tag_lines(cluster_id: int, fb: FusedMergeBox) -> str:
    """Short id usable on all three mips (same numbering)."""
    zt = f"z{fb.z_min}-{fb.z_max}" if fb.z_min != fb.z_max else f"z{fb.z_min}"
    if fb.n_merge > 1:
        return f"#{cluster_id} x{fb.n_merge} {zt}"
    return f"#{cluster_id} {zt}"


def _draw_fused_proof_tag(
    panel: np.ndarray,
    x1: int,
    y1: int,
    x2: int,
    y2: int,
    *,
    cluster_id: int,
    fb: FusedMergeBox,
    font_scale: float,
    line_spacing: int = 20,
) -> None:
    """Dense tag inside yellow box corner: opaque label chip + stroked glyphs for readability."""
    if x2 <= x1 + 4 or y2 <= y1 + 8:
        return
    txt = _fuse_tag_lines(cluster_id, fb)
    font = cv2.FONT_HERSHEY_SIMPLEX
    fs = float(np.clip(font_scale * 0.48, 0.30, 0.65))
    th = max(1, min(6, int(round(fs * 2.2))))
    pad = 4
    oy = min(max(y1 + int(16 + 8 * fs), y1 + 14), panel.shape[0] - 2)
    ox = int(max(4, min(x1 + 4, panel.shape[1] - 8)))
    if oy < y1 + 10:
        oy = min(y1 + max(16, line_spacing), y2 - 4, panel.shape[0] - 3)
    (tw, tex_h), baseline = cv2.getTextSize(txt, font, fs, th)
    if ox + tw + 2 * pad >= panel.shape[1]:
        ox = max(2, int(panel.shape[1]) - tw - 2 * pad - 2)
    chip_x1 = max(0, ox - pad)
    chip_y1 = max(int(y1), oy - tex_h - pad)
    chip_x2 = min(int(panel.shape[1]) - 1, ox + tw + pad)
    chip_y2 = min(int(panel.shape[0]) - 1, oy + baseline + pad)
    if chip_y2 > y2 + 12:
        shift = chip_y2 - (y2 + 12)
        chip_y1 -= shift
        chip_y2 -= shift
        oy -= shift
    if chip_x2 <= chip_x1 + 8 or chip_y2 <= chip_y1 + 4:
        return
    cv2.rectangle(panel, (chip_x1, chip_y1), (chip_x2, chip_y2), (8, 8, 14), thickness=-1)
    cv2.rectangle(panel, (chip_x1, chip_y1), (chip_x2, chip_y2), (90, 90, 96), thickness=1)

    fg = (255, 248, 240)
    cv2.putText(panel, txt, (ox, oy), font, fs, (0, 0, 0), th + 3, cv2.LINE_AA)
    cv2.putText(panel, txt, (ox, oy), font, fs, fg, th, cv2.LINE_AA)


def _ensure_min_native_span(lo: int, hi: int, bound_lo: int, bound_hi: int, min_px: int) -> tuple[int, int]:
    """Expand inclusive integer range [lo, hi] within [bound_lo, bound_hi] until width >= min_px."""
    lo, hi = sorted((int(lo), int(hi)))
    lo = max(bound_lo, min(lo, bound_hi))
    hi = max(bound_lo, min(hi, bound_hi))
    if hi < lo:
        lo = hi = int(np.clip((bound_lo + bound_hi) // 2, bound_lo, bound_hi))
    axis_len = bound_hi - bound_lo + 1
    mw = int(np.clip(min_px, 1, max(1, axis_len)))
    span = hi - lo + 1
    if span >= mw:
        return lo, hi
    deficit = mw - span
    pad_l = deficit // 2
    pad_r = deficit - pad_l
    lo2 = max(bound_lo, lo - pad_l)
    hi2 = min(bound_hi, hi + pad_r)
    while hi2 - lo2 + 1 < mw:
        moved = False
        if lo2 > bound_lo:
            lo2 -= 1
            moved = True
            if hi2 - lo2 + 1 >= mw:
                break
        if hi2 < bound_hi:
            hi2 += 1
            moved = True
        if not moved:
            break
    return lo2, hi2


def _split_expand_native_xz(
    xc1: int, zr1: int, xc2: int, zr2: int, nx: int, nz: int, min_side_px: int
) -> tuple[int, int, int, int]:
    xa, xb = _ensure_min_native_span(xc1, xc2, 0, nx - 1, min_side_px)
    za, zb = _ensure_min_native_span(zr1, zr2, 0, nz - 1, min_side_px)
    return xa, za, xb, zb


def _split_expand_native_yz(
    yc1: int, zz1: int, yc2: int, zz2: int, ny: int, nz: int, min_side_px: int
) -> tuple[int, int, int, int]:
    ya, yb = _ensure_min_native_span(yc1, yc2, 0, ny - 1, min_side_px)
    za, zb = _ensure_min_native_span(zz1, zz2, 0, nz - 1, min_side_px)
    return ya, za, yb, zb


def _cv_resize_interp(name: str) -> int:
    n = name.strip().lower()
    flags = {
        "nearest": cv2.INTER_NEAREST,
        "linear": cv2.INTER_LINEAR,
        "area": cv2.INTER_AREA,
        "cubic": cv2.INTER_CUBIC,
        "lanczos4": cv2.INTER_LANCZOS4,
    }
    if n not in flags:
        raise ValueError(f"unknown resize interpolation {name!r}; use one of {sorted(flags)}")
    return flags[n]


def _export_zoomed_split_view(
    bgr: np.ndarray,
    out_path: Path,
    plane: str,
    *,
    lbl_fs: float,
    zoom: float,
    z_stretch: float,
    band_kw: dict[str, float | int],
    resize_interp: int,
    post_sharpen: float,
    native_rects_xyxy: Sequence[tuple[int, int, int, int]] | None = None,
    split_line_thickness: int = 1,
    split_fill_alpha: float = 0.0,
    native_centroids_col_row: Sequence[tuple[int, int]] | None = None,
    split_centroid_radius_px: int = 5,
    centroid_mark_bgr: tuple[int, int, int] = (0, 0, 255),
    label_gap_px: int = 0,
) -> None:
    """
    Write one panel: optional anisotropic upscale (``z_stretch`` on height = slice axis on XZ/YZ)
    then a short plane label.
    ``INTER_NEAREST`` avoids smoothing when shallow-``nz`` mips are enlarged many-fold.

    If ``native_rects_xyxy`` is set, yellow boxes are drawn **after** resize so lines stay
    ``split_line_thickness`` pixels wide on disk (upscale no longer turns 1 native px into a fat band).
    Pass the mip **without** those rectangles already drawn.

    When ``label_gap_px`` > 0, prepends title band + blank margin above the mip so the label
    does not paint over the top rows of the projection.
    """
    img = np.asarray(bgr, dtype=np.uint8).copy()
    h0, w0 = int(img.shape[0]), int(img.shape[1])
    sx = sy = 1.0
    if abs(float(zoom) - 1.0) > 1e-6 or abs(float(z_stretch) - 1.0) > 1e-6:
        nw = max(1, int(round(w0 * float(zoom))))
        nh = max(1, int(round(h0 * float(zoom) * float(z_stretch))))
        sx = nw / float(max(w0, 1))
        sy = nh / float(max(h0, 1))
        img = cv2.resize(img, (nw, nh), interpolation=int(resize_interp))
    ps = float(np.clip(post_sharpen, 0.0, 2.5))
    if ps > 1e-6:
        img = _side_mip_unsharp_bgr(np.asarray(img, dtype=np.uint8), amount=ps)

    lt = max(1, int(split_line_thickness))
    hi, wi = int(img.shape[0]), int(img.shape[1])
    scaled_rects: list[tuple[int, int, int, int]] = []
    if native_rects_xyxy:
        for x1, y1, x2, y2 in native_rects_xyxy:
            X1 = int(np.round(x1 * sx))
            Y1 = int(np.round(y1 * sy))
            X2 = int(np.round(x2 * sx))
            Y2 = int(np.round(y2 * sy))
            if X2 < X1:
                X1, X2 = X2, X1
            if Y2 < Y1:
                Y1, Y2 = Y2, Y1
            X1 = int(np.clip(X1, 0, wi - 1))
            X2 = int(np.clip(X2, 0, wi - 1))
            Y1 = int(np.clip(Y1, 0, hi - 1))
            Y2 = int(np.clip(Y2, 0, hi - 1))
            scaled_rects.append((X1, Y1, X2, Y2))

    fa = float(np.clip(split_fill_alpha, 0.0, 0.85))
    if scaled_rects and fa > 1e-6:
        overlay = img.copy()
        for X1, Y1, X2, Y2 in scaled_rects:
            cv2.rectangle(overlay, (X1, Y1), (X2, Y2), YELLOW_BGR, thickness=-1)
        img = cv2.addWeighted(overlay, fa, img, 1.0 - fa, 0.0)

    for X1, Y1, X2, Y2 in scaled_rects:
        cv2.rectangle(img, (X1, Y1), (X2, Y2), YELLOW_BGR, lt, lineType=_LINE_YELLOW)

    if native_centroids_col_row:
        scr = max(1, int(split_centroid_radius_px))
        mk = tuple(int(np.clip(int(c), 0, 255)) for c in centroid_mark_bgr)
        for col, row in native_centroids_col_row:
            X = int(np.round(col * sx))
            Y = int(np.round(row * sy))
            X = int(np.clip(X, 0, wi - 1))
            Y = int(np.clip(Y, 0, hi - 1))
            cv2.circle(img, (X, Y), scr, mk, thickness=-1, lineType=cv2.LINE_AA)

    hi, wi = int(img.shape[0]), int(img.shape[1])
    fs_lbl = float(np.clip(float(lbl_fs) * 1.08, 0.45, 1.0))
    gap = max(0, int(label_gap_px))
    out = img.copy()
    if gap > 0:
        band_h = _triptych_label_band_h(
            plane,
            "",
            font_scale=fs_lbl,
            thickness=2,
            line_spacing=int(band_kw.get("line_spacing", 21)),
            max_band_fraction=float(band_kw.get("max_band_fraction", 0.082)),
            max_band_px_cap=int(band_kw.get("max_band_px_cap", 92)),
            min_band_px=34,
            height_ref=hi,
        )
        canvas = np.empty((band_h + gap + hi, wi, 3), dtype=np.uint8)
        canvas[:] = (26, 26, 30)
        canvas[band_h + gap :, :] = out
        out = canvas

    _annotate_triptych_label(
        out,
        plane,
        "",
        font_scale=fs_lbl,
        thickness=2,
        height_ref_for_band_cap=hi,
        **band_kw,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(out_path), out)


def _gst_jsonable(gst: dict[str, Any] | None) -> str:
    if not gst:
        return ""
    out: dict[str, Any] = {}
    for k, v in gst.items():
        if isinstance(v, (bool, int, float, str)):
            out[k] = v
        elif isinstance(v, (np.integer, np.floating)):
            out[k] = float(v) if isinstance(v, np.floating) else int(v)
        else:
            out[k] = str(v)
    return json.dumps(out, indent=1)


def _rasterize_fused_boxes_label_vol(
    boxes: list[FusedMergeBox],
    *,
    ny: int,
    nx: int,
    nz: int,
    rect_xy: Any,
    transpose_for_neuropal: bool,
) -> np.ndarray:
    """Axis-aligned uint16 labels: id 1..N inside each fused AABB (last id wins on overlap)."""
    if transpose_for_neuropal:
        lab = np.zeros((nx, ny, nz), dtype=np.uint16)
    else:
        lab = np.zeros((ny, nx, nz), dtype=np.uint16)
    for k, fb in enumerate(boxes, start=1):
        x1, y1, x2, y2 = rect_xy(fb, ny, nx)
        xi0 = int(np.clip(np.floor(min(x1, x2)), 0, nx - 1))
        xi1 = int(np.clip(np.ceil(max(x1, x2)), 0, nx - 1))
        yi0 = int(np.clip(np.floor(min(y1, y2)), 0, ny - 1))
        yi1 = int(np.clip(np.ceil(max(y1, y2)), 0, ny - 1))
        zi0 = int(np.clip(min(fb.z_min, fb.z_max), 0, nz - 1))
        zi1 = int(np.clip(max(fb.z_min, fb.z_max), 0, nz - 1))
        if transpose_for_neuropal:
            lab[xi0 : xi1 + 1, yi0 : yi1 + 1, zi0 : zi1 + 1] = np.uint16(k)
        else:
            lab[yi0 : yi1 + 1, xi0 : xi1 + 1, zi0 : zi1 + 1] = np.uint16(k)
    return lab


def build_yolo_fused_aabb_mat_blob(
    boxes: list[FusedMergeBox],
    *,
    ny: int,
    nx: int,
    nz: int,
    crop_z_offset: int,
    rect_xy: Any,
    gst: dict[str, Any] | None,
    fuse_3d: bool,
    fuse_mode: str,
    summary_path: str,
    volume_path: str,
    fused_box_style: str,
    transpose_for_neuropal: bool,
    include_label_vol: bool,
) -> dict[str, Any]:
    """Variables merged into NeuroPAL volume .mat (no top-level version key)."""
    n = len(boxes)
    np10 = np.zeros((max(n, 1), 10), dtype=np.float64)
    ml9 = np.zeros((max(n, 1), 9), dtype=np.float64)
    z_abs = np.zeros((max(n, 1), 2), dtype=np.float64)
    for i, fb in enumerate(boxes):
        x1, y1, x2, y2 = rect_xy(fb, ny, nx)
        z_lo = int(np.clip(min(fb.z_min, fb.z_max), 0, max(nz - 1, 0)))
        z_hi = int(np.clip(max(fb.z_min, fb.z_max), 0, max(nz - 1, 0)))
        kid = float(i + 1)
        np10[i, :] = (
            kid,
            float(x1),
            float(y1),
            float(x2),
            float(y2),
            float(z_lo),
            float(z_hi),
            float(fb.z_mean),
            float(fb.conf_max),
            float(fb.n_merge),
        )
        z_abs[i, 0] = float(z_lo + int(crop_z_offset))
        z_abs[i, 1] = float(z_hi + int(crop_z_offset))
        if transpose_for_neuropal:
            d1_lo = float(min(x1, x2) + 1.0)
            d1_hi = float(max(x1, x2) + 1.0)
            d2_lo = float(min(y1, y2) + 1.0)
            d2_hi = float(max(y1, y2) + 1.0)
        else:
            d1_lo = float(min(y1, y2) + 1.0)
            d1_hi = float(max(y1, y2) + 1.0)
            d2_lo = float(min(x1, x2) + 1.0)
            d2_hi = float(max(x1, x2) + 1.0)
        ml9[i, :] = (
            kid,
            d1_lo,
            d1_hi,
            d2_lo,
            d2_hi,
            float(z_lo + 1),
            float(z_hi + 1),
            float(fb.conf_max),
            float(fb.n_merge),
        )
    note = (
        "yolo_fused_aabb_np10: id,x1,y1,x2,y2,z_lo_crop,z_hi_crop,z_mean,conf_max,n_merge (numpy row=y col=x). "
        "yolo_fused_aabb_matlab1: id,dim1_lo,dim1_hi,dim2_lo,dim2_hi,z_lo,z_hi,conf_max,n_merge (1-based into data). "
        "Optional yolo_fused_box_label_uint16 matches data layout when transpose_xy_for_neuropal=1."
    )
    out: dict[str, Any] = {
        "yolo_fused_aabb_np10": np10 if n else np10[:0, :],
        "yolo_fused_aabb_matlab1": ml9 if n else ml9[:0, :],
        "yolo_fused_z_slice_abs": z_abs if n else z_abs[:0, :],
        "crop_z0": np.asarray([[int(crop_z_offset)]], dtype=np.int64),
        "volume_shape_ny_nx_nz": np.asarray([[ny, nx, nz]], dtype=np.int64),
        "transpose_xy_for_neuropal": np.asarray([[int(bool(transpose_for_neuropal))]], dtype=np.uint8),
        "fuse_3d": np.asarray([[int(bool(fuse_3d))]], dtype=np.uint8),
        "fuse_mode": np.array(np.str_(fuse_mode)),
        "fused_box_style": np.array(np.str_(fused_box_style)),
        "n_fused_boxes": np.asarray([[int(n)]], dtype=np.int64),
        "summary_path": np.array(np.str_(summary_path)),
        "volume_path": np.array(np.str_(volume_path)),
        "yolo_fused_boxes_note": np.array(np.str_(note)),
        "fusion_stats_json": np.array(np.str_(_gst_jsonable(gst))),
    }
    if include_label_vol and n > 0:
        out["yolo_fused_box_label_uint16"] = _rasterize_fused_boxes_label_vol(
            boxes,
            ny=ny,
            nx=nx,
            nz=nz,
            rect_xy=rect_xy,
            transpose_for_neuropal=bool(transpose_for_neuropal),
        )
    return out


def export_fused_3d_boxes_mat(
    out_mat: Path,
    boxes: list[FusedMergeBox],
    *,
    ny: int,
    nx: int,
    nz: int,
    crop_z_offset: int,
    rect_xy: Any,
    gst: dict[str, Any] | None,
    fuse_3d: bool,
    fuse_mode: str,
    summary_path: str,
    volume_path: str,
    fused_box_style: str,
    transpose_for_neuropal: bool,
    include_label_vol: bool,
    log: logging.Logger,
) -> None:
    """
    Write a standalone ``.mat`` for 3D QC: fused axis-aligned boxes (same geometry as yellow overlays).

    Tables use **cropped** volume z indices (0..nz-1) in the numpy columns; ``*_abs`` adds ``crop_z0``.
    ``yolo_fused_aabb_matlab1`` follows the same dim convention as ``export_neuropal_gui_mat_bundle`` /
    ``build_neuropal_sp_and_mp_params`` when ``transpose_for_neuropal`` is true (default): MATLAB
    ``data(dim1, dim2, z, :)`` with dim1 = OpenCV **column x + 1**, dim2 = **row y + 1``.
    """
    """
    Standalone scipy .mat (adds ``version=1``). Not visualize_light — use ``--export-neuropal-gui-mat``.
    """
    try:
        from scipy.io import savemat  # type: ignore[import-untyped]
    except ImportError as e:
        raise RuntimeError("export_fused_3d_boxes_mat needs scipy (`pip install scipy`).") from e

    out_mat = Path(out_mat)
    out_mat.parent.mkdir(parents=True, exist_ok=True)
    n = len(boxes)
    blob = build_yolo_fused_aabb_mat_blob(
        boxes,
        ny=ny,
        nx=nx,
        nz=nz,
        crop_z_offset=crop_z_offset,
        rect_xy=rect_xy,
        gst=gst,
        fuse_3d=fuse_3d,
        fuse_mode=fuse_mode,
        summary_path=summary_path,
        volume_path=volume_path,
        fused_box_style=fused_box_style,
        transpose_for_neuropal=transpose_for_neuropal,
        include_label_vol=include_label_vol,
    )
    blob["version"] = np.asarray([[1.0]], dtype=np.float64)
    savemat(str(out_mat), blob, do_compression=True)
    log.info("wrote fused 3D box .mat → %s (%d boxes, label_vol=%s)", out_mat.resolve(), n, include_label_vol)


def _volume_zslice_xy_bgr(
    volume: np.ndarray,
    z: int,
    *,
    stretch_percentile: bool,
    p_lo: float,
    p_hi: float,
) -> np.ndarray:
    """Single Z plane ``volume[:,:,z,:3]`` → uint8 BGR (same stretch convention as side MIP helper)."""
    plane = np.asarray(volume[:, :, int(z), :3], dtype=np.float32)
    return _stretch_rgb_plane_to_bgr(plane, pct=stretch_percentile, p_lo=p_lo, p_hi=p_hi)


def export_xy_slices_merged_yellow(
    volume: np.ndarray,
    *,
    fuse_3d: bool,
    fused: list[FusedMergeBox],
    raw_use: list[RawBox],
    rect_xy: Any,
    ny: int,
    nx: int,
    out_dir: Path,
    line_thickness: int,
    stretch_percentile: bool,
    p_lo: float,
    p_hi: float,
    log: logging.Logger,
) -> None:
    """
    One BGR PNG per ``z``: ``volume[:,:,z]`` with the **same** yellow XY overlays as ``main``'s triptych
    (fused clusters when ``fuse_3d``, else raw boxes on their slice only).
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    nz = int(volume.shape[2])
    lt = max(1, int(line_thickness))
    for z in range(nz):
        canvas = _volume_zslice_xy_bgr(
            volume, z, stretch_percentile=stretch_percentile, p_lo=p_lo, p_hi=p_hi
        )
        if fuse_3d:
            for fb in fused:
                if z < int(fb.z_min) or z > int(fb.z_max):
                    continue
                xa1, ya1, xa2, ya2 = rect_xy(fb, ny, nx)
                cv2.rectangle(canvas, (xa1, ya1), (xa2, ya2), YELLOW_BGR, lt, lineType=_LINE_YELLOW)
        else:
            for b in raw_use:
                if int(b.z) != z:
                    continue
                ph = _fused_placeholder_from_slice(b)
                xa1, ya1, xa2, ya2 = rect_xy(ph, ny, nx)
                cv2.rectangle(canvas, (xa1, ya1), (xa2, ya2), YELLOW_BGR, lt, lineType=_LINE_YELLOW)
        cv2.imwrite(str(out_dir / f"slice_{z:05d}_xy_merged_yellow.png"), canvas)
    log.info(
        "wrote %d per-Z XY slice PNGs → %s (fuse_3d=%s stretch=%s)",
        nz,
        out_dir.resolve(),
        fuse_3d,
        stretch_percentile,
    )


def main() -> None:
    ap = argparse.ArgumentParser(
        description="XY | XZ | YZ RGB MIPs with merged YOLO boxes in yellow (max w/h per z-cluster)"
    )
    ap.add_argument("--summary", type=Path, required=True, help="predictions_summary.json")
    ap.add_argument("--volume", type=Path, default=None, help="Override .npy path (default: summary['volume'])")
    ap.add_argument("--out_png", type=Path, required=True)
    ap.add_argument(
        "--save-split-views",
        action="store_true",
        help="Also write three full-size PNGs next to --out_png: <stem>_view_xy.png, "
        "<stem>_view_xz.png, <stem>_view_yz.png (XZ/YZ scaled for shallow nz stacks).",
    )
    ap.add_argument(
        "--split-views-dir",
        type=Path,
        default=None,
        help="Output directory for split PNGs (default: same directory as --out_png).",
    )
    ap.add_argument(
        "--split-view-zoom",
        type=float,
        default=3.0,
        help="Uniform upscale factor for split-view XZ & YZ vs native mip (default 3).",
    )
    ap.add_argument(
        "--split-view-z-stretch",
        type=float,
        default=2.0,
        help="Extra multiplier on **vertical** size (slice axis) after zoom for split XZ/YZ only.",
    )
    ap.add_argument(
        "--split-xy-zoom",
        type=float,
        default=1.0,
        help="Optional upscale for split XY (1 = same pixel size as triptych XY column).",
    )
    ap.add_argument(
        "--split-view-interp",
        type=str,
        default="nearest",
        choices=("nearest", "linear", "cubic", "lanczos4", "area"),
        help="OpenCV resize mode for split XZ/YZ (nearest = crisp blocks, no cubic mush; area for downscale).",
    )
    ap.add_argument(
        "--split-view-post-sharpen",
        type=float,
        default=0.0,
        help="Unsharp **after** split XZ/YZ resize (0=off; try 0.25–0.55 if mips still look soft).",
    )
    ap.add_argument(
        "--split-xy-interp",
        type=str,
        default="cubic",
        choices=("nearest", "linear", "cubic", "lanczos4", "area"),
        help="Resize mode when --split-xy-zoom≠1.",
    )
    ap.add_argument(
        "--split-view-line-thickness",
        type=int,
        default=1,
        help="Yellow box stroke width on split-view XZ/YZ **after** upscale (avoids chunky lines with "
        "--split-view-interp nearest). Triptych still uses --line-thickness.",
    )
    ap.add_argument(
        "--split-min-native-side-pixels",
        type=int,
        default=6,
        help="Split XZ/YZ only: expand each native box so width AND height are ≥ this many mip pixels "
        "(thin Z-span envelopes otherwise look like two horizontal lines). Capped by nx/nz or ny/nz.",
    )
    ap.add_argument(
        "--split-view-fill-alpha",
        type=float,
        default=0.12,
        help="Split XZ/YZ only: 0=outline only; 0.05–0.2 = blend translucent yellow fill under outline "
        "for readability when nz is shallow.",
    )
    ap.add_argument(
        "--split-view-label-gap",
        type=int,
        default=10,
        help="Split XZ/YZ exports only: blank rows between title strip and MIP (0 = legacy, label on image).",
    )
    ap.add_argument(
        "--export-fused-3d-mat",
        type=Path,
        default=None,
        help="Write scipy .mat with fused 3D axis-aligned boxes (same AABB as yellow overlays; IoU-color "
        "or euclidean per --fuse-mode). For MATLAB / NeuroPAL-style dim1,dim2 when paired with default transpose.",
    )
    ap.add_argument(
        "--export-fused-3d-mat-label-vol",
        action="store_true",
        help="With --export-fused-3d-mat: also write uint16 yolo_fused_box_label_uint16 (nx×ny×nz if "
        "NeuroPAL transpose; large file).",
    )
    ap.add_argument(
        "--export-fused-3d-mat-neuropal-keep-numpy-axes",
        action="store_true",
        help="With --export-fused-3d-mat: matlab1 columns use dim1=row(y)+1, dim2=col(x)+1 (skip GUI xy permute).",
    )
    ap.add_argument(
        "--export-fused-xy-slices-dir",
        type=Path,
        default=None,
        help="Directory for slice_{z:05d}_xy_merged_yellow.png: each Z plane with the **same** yellow XY "
        "overlays as this run (fused when --fuse-3d per --fuse-mode; else raw slice boxes). Uses "
        "--fused-box-style and --line-thickness. Optional --stretch-fused-slices + --p_lo/--p_hi per slice.",
    )
    ap.add_argument(
        "--stretch-fused-slices",
        action="store_true",
        help="With --export-fused-xy-slices-dir: percentile-stretch each XY slice before drawing boxes.",
    )
    ap.add_argument("--stretch_mip", action="store_true")
    ap.add_argument("--p_lo", type=float, default=2.0)
    ap.add_argument("--p_hi", type=float, default=98.0)
    ap.add_argument(
        "--side-mip-p-lo",
        type=float,
        default=None,
        help="XZ/YZ percentile low (default: 0.25 with --stretch_mip, else same as --p_lo).",
    )
    ap.add_argument(
        "--side-mip-p-hi",
        type=float,
        default=None,
        help="XZ/YZ percentile high (default: 99.75 with --stretch_mip, else same as --p_hi).",
    )
    ap.add_argument(
        "--side-mip-clahe-clip",
        type=float,
        default=3.0,
        help="CLAHE clip on XZ/YZ L-channel (try 2.5–4.8 if side mips stay muddy).",
    )
    ap.add_argument(
        "--side-mip-sharpen",
        type=float,
        default=0.42,
        help="Unsharp on XZ/YZ after CLAHE (0=off; ~0.35–0.65 when nz is shallow).",
    )
    ap.add_argument(
        "--no-side-mip-clahe",
        dest="side_mip_clahe",
        action="store_false",
        help="Disable LAB CLAHE on orthogonal side mips.",
    )
    ap.set_defaults(side_mip_clahe=True)
    ap.add_argument("--line_thickness", type=int, default=1, help="Yellow box outline width (1 = thin).")
    ap.add_argument(
        "--fuse-max-dz",
        type=int,
        default=1,
        help="Link two detections only if 1≤|Δz|≤this (same-z never linked).",
    )
    ap.add_argument(
        "--fuse-max-dxy-px",
        type=float,
        default=12.0,
        help="euclidean fuse only: centroid √(Δx²+Δy²) limit linking across z.",
    )
    ap.add_argument(
        "--fuse-mode",
        choices=("euclidean", "iou-color"),
        default="euclidean",
        help="3D merge when --fuse-3d: euclidean (centroid distance) or iou-color "
        "(mip_centroids_iou_color_fuse: IoU + optional RGB cosine + depth sanity).",
    )
    ap.add_argument(
        "--iou-min",
        type=float,
        default=0.5,
        help="iou-color only: minimum XY bbox IoU for linking across slices (run_infer_data5 uses 0.9).",
    )
    ap.add_argument(
        "--no-color-match",
        action="store_true",
        help="iou-color only: IoU + |dz| only; skip RGB feature / cosine gate.",
    )
    ap.add_argument(
        "--color-feature",
        choices=("percentiles", "kde"),
        default="percentiles",
        help="iou-color only: RGB descriptor inside each box crop.",
    )
    ap.add_argument(
        "--color-percentiles",
        type=float,
        nargs="+",
        default=[50.0, 75.0, 90.0],
        help="iou-color only: per-channel percentiles when --color-feature percentiles.",
    )
    ap.add_argument(
        "--color-dot-min",
        type=float,
        default=0.8,
        help="iou-color only: min normalized cosine between RGB feature vectors.",
    )
    ap.add_argument("--kde-bin-count-min", type=int, default=8, help="iou-color kde feature only.")
    ap.add_argument("--kde-bandwidth-bins", type=float, default=3.0, help="iou-color kde feature only.")
    ap.add_argument(
        "--voxel-spacing-um",
        type=float,
        nargs=3,
        metavar=("SX", "SY", "SZ"),
        default=[0.4, 0.4, 1.5],
        help="iou-color depth sanity: µm per voxel (numpy row, col, z).",
    )
    ap.add_argument(
        "--depth-sanity-ratio-cap",
        type=float,
        default=1.5,
        help="iou-color only: drop clusters with axial bbox too elongated (see mip_centroids_iou_color_fuse).",
    )
    ap.add_argument(
        "--no-depth-sanity",
        action="store_true",
        help="iou-color only: keep all IoU/color components (skip µm elongation filter).",
    )
    fuse_g = ap.add_mutually_exclusive_group()
    fuse_g.add_argument("--fuse-3d", dest="fuse_3d", action="store_true")
    fuse_g.add_argument("--no-fuse-3d", dest="fuse_3d", action="store_false")
    ap.set_defaults(fuse_3d=True)
    ap.add_argument(
        "--fused-box-style",
        choices=("envelope", "centroid-maxwh"),
        default="envelope",
        help="Fused XY/XZ/YZ rectangles: envelope = hull around every slice box in cluster (default); "
        "centroid-maxwh = conf-weighted centre with max(width)×max(height) (legacy).",
    )
    ap.add_argument(
        "--crop-z-to-summary",
        action="store_true",
        help="Crop volume Z to [min,max] slice indices listed in summary before MIPs.",
    )
    ap.add_argument(
        "--side-panels",
        choices=("match-xy-frame", "stretch-height"),
        default="match-xy-frame",
        help="match-xy-frame (default): letterbox XZ/YZ into ny×nx like XY (fixes very wide sides). "
        "stretch-height: scale only vertically to ny like older behavior (xz width ≈ nx*ny/nz).",
    )
    ap.add_argument("--device", choices=("cpu", "gpu"), default="cpu")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument(
        "--timing_json",
        type=Path,
        default=None,
        help="Defaults to stem + '_merged_yellow_mip_timing.json' beside out_png",
    )
    ap.add_argument(
        "--fusion-proof",
        dest="fusion_proof",
        action="store_true",
        help="Overlay fuse stats on XY + per-cluster #id tags on boxes (clutters tissue; "
        "fuse stats are always printed to the console / timing JSON anyway).",
    )
    ap.set_defaults(fusion_proof=False)
    ap.add_argument(
        "--show-fused-centroids",
        action="store_true",
        help="Draw centroid disks on XY / XZ / YZ (fused: XY=(cx,cy), XZ=(cx,z_mean), YZ=(cy,z_mean); "
        "--no-fuse-3d: per-slice centres at that slice's z). Use --centroid-bgr to contrast yellow boxes.",
    )
    ap.add_argument(
        "--centroid-radius",
        type=int,
        default=3,
        help="Triptych panels: filled centroid disk radius (pixels).",
    )
    ap.add_argument(
        "--centroid-bgr",
        type=int,
        nargs=3,
        metavar=("B", "G", "R"),
        default=[0, 0, 255],
        help="Centroid marker BGR (default 0 0 255 = red).",
    )
    ap.add_argument(
        "--split-centroid-radius",
        type=int,
        default=5,
        help="Split-view PNGs: centroid radius in **output** pixels when dots are drawn on box splits "
        "(XZ/YZ; XY too when --split-xy-zoom≠1). Not used on *_centroids_only_view_* (see next flag).",
    )
    ap.add_argument(
        "--centroids-only-split-radius",
        type=int,
        default=2,
        help="With --centroids-separate-panels --save-split-views: disk radius in **output** pixels on "
        "*_centroids_only_view_xy/xz/yz.png only (default 2 — smaller than --split-centroid-radius).",
    )
    ap.add_argument(
        "--centroids-separate-panels",
        action="store_true",
        help="With --show-fused-centroids: write centroid markers on **separate** PNGs (no yellow boxes); "
        "triptych/box panels stay box-only. Emit <stem>_centroids_only_{xy,xz,yz}.png and optional "
        "*_centroids_only_view_*.png when --save-split-views (disk size: --centroids-only-split-radius).",
    )
    args = ap.parse_args()
    if args.centroids_separate_panels and not args.show_fused_centroids:
        raise SystemExit("error: --centroids-separate-panels requires --show-fused-centroids")

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s [viz_merged_yellow] %(message)s",
    )
    log = logging.getLogger("viz_merged_yellow")

    t0 = time.perf_counter()
    sj = json.loads(Path(args.summary).read_text(encoding="utf-8"))
    vol_path = Path(args.volume) if args.volume is not None else Path(sj["volume"])
    if not vol_path.is_file():
        raise FileNotFoundError(f"volume not found: {vol_path}")

    volume = load_volume(vol_path)
    ny, nx, nz0, nc = (int(volume.shape[i]) for i in range(4))
    crop_z_offset = 0
    z_win = _summary_z_window(sj.get("slices") or [])
    if args.crop_z_to_summary and z_win is not None:
        z0, z1 = z_win
        if z0 < 0 or z1 >= nz0 or z0 > z1:
            raise ValueError(f"summary z range [{z0},{z1}] incompatible with volume Z={nz0}")
        crop_z_offset = int(z0)
        volume = volume[:, :, z0 : z1 + 1, :]
        log.info("cropped Z to summary [%d,%d] (offset=%d)", z0, z1, crop_z_offset)

    ny, nx, nz, _ = (int(volume.shape[i]) for i in range(4))
    if nc < 3:
        raise ValueError(f"RGB MIPs require ≥3 channels; got {nc}")

    if args.device == "gpu":
        xy_bgr = mip_rgb_bgr_torch_cuda(
            volume,
            percentile_stretch=args.stretch_mip,
            p_lo=args.p_lo,
            p_hi=args.p_hi,
            log=log,
        )
    else:
        xy_bgr = mip_rgb_bgr(
            volume,
            percentile_stretch=args.stretch_mip,
            p_lo=args.p_lo,
            p_hi=args.p_hi,
            log=log,
        )

    if args.stretch_mip:
        sp_lo = args.side_mip_p_lo if args.side_mip_p_lo is not None else 0.25
        sp_hi = args.side_mip_p_hi if args.side_mip_p_hi is not None else 99.75
    else:
        sp_lo = args.side_mip_p_lo if args.side_mip_p_lo is not None else args.p_lo
        sp_hi = args.side_mip_p_hi if args.side_mip_p_hi is not None else args.p_hi

    xz_bgr = mip_xz_rgb_bgr(volume, percentile_stretch=args.stretch_mip, p_lo=sp_lo, p_hi=sp_hi)
    yz_bgr = mip_yz_rgb_bgr(volume, percentile_stretch=args.stretch_mip, p_lo=sp_lo, p_hi=sp_hi)
    if args.side_mip_clahe and float(args.side_mip_clahe_clip) > 1e-6:
        xz_bgr = _side_mip_lab_clahe(xz_bgr, clip_limit=float(args.side_mip_clahe_clip))
        yz_bgr = _side_mip_lab_clahe(yz_bgr, clip_limit=float(args.side_mip_clahe_clip))
    sx = float(args.side_mip_sharpen)
    if sx > 1e-6:
        xz_bgr = _side_mip_unsharp_bgr(xz_bgr, amount=sx)
        yz_bgr = _side_mip_unsharp_bgr(yz_bgr, amount=sx)
    if nz > 0 and ny > nz * 8:
        log.info(
            "Side MIPs span only nz=%d axial samples (vs XY ny=%d rows) — upscaling ~%.1f× to match "
            "panel height — CLAHE+unsharp help but cannot add true Z resolution; tweak "
            "--side-mip-clahe-clip (now %.2f) / --side-mip-sharpen (now %.2f).",
            nz,
            ny,
            float(ny) / float(nz),
            float(args.side_mip_clahe_clip),
            float(args.side_mip_sharpen),
        )

    raw_boxes, short_n = _collect_raw_boxes(sj)
    if short_n:
        log.warning("skipped %d malformed box rows (<5 fields)", short_n)

    # Adjust absolute summary z indices if volume was cropped — boxes outside cropped stack are skipped.
    def _raw_in_crop(boxes: list[RawBox]) -> list[RawBox]:
        out: list[RawBox] = []
        for b in boxes:
            zi = b.z - crop_z_offset
            if zi < 0 or zi >= nz:
                continue
            out.append(RawBox(z=zi, x1=b.x1, y1=b.y1, x2=b.x2, y2=b.y2, cx=b.cx, cy=b.cy, conf=b.conf))
        return out

    raw_use = _raw_in_crop(raw_boxes)
    if len(raw_use) < len(raw_boxes):
        log.warning(
            "%d detections fell outside cropped Z window (crop_z_offset=%d nz=%d)",
            len(raw_boxes) - len(raw_use),
            crop_z_offset,
            nz,
        )

    thickness = max(1, int(args.line_thickness))
    fs_panel = float(np.clip(ny / 820.0, 0.5, 1.05))
    if args.fused_box_style == "envelope":
        rect_xy = _xy_rect_envelope
        rect_native_xz = _xz_rect_envelope
        rect_native_yz = _yz_rect_envelope
    else:
        rect_xy = _xy_rect_from_centre
        rect_native_xz = _xz_rect
        rect_native_yz = _yz_rect
    gst: dict[str, Any] | None = None
    fused: list[FusedMergeBox] = []

    xy_mip_clean = xy_bgr.copy()
    xz_mip_clean = xz_bgr.copy()
    yz_mip_clean = yz_bgr.copy()

    if args.fuse_3d:
        if args.fuse_mode == "iou-color":
            fused, gst = _fuse_iou_color_into_fused(
                raw_use,
                volume,
                fuse_max_dz=args.fuse_max_dz,
                iou_min=args.iou_min,
                require_color=not bool(args.no_color_match),
                color_feature=str(args.color_feature),
                color_percentiles=tuple(float(x) for x in args.color_percentiles),
                color_dot_min=float(args.color_dot_min),
                kde_bin_count_min=int(args.kde_bin_count_min),
                kde_bandwidth_bins=float(args.kde_bandwidth_bins),
                voxel_spacing_um=(
                    float(args.voxel_spacing_um[0]),
                    float(args.voxel_spacing_um[1]),
                    float(args.voxel_spacing_um[2]),
                ),
                depth_sanity_ratio_cap=float(args.depth_sanity_ratio_cap),
                no_depth_sanity=bool(args.no_depth_sanity),
                log=log,
                verbose=bool(args.verbose),
            )
        else:
            groups, gst0 = fuse_boxes_into_groups(
                raw_use, max_dz=args.fuse_max_dz, max_dxy_px=args.fuse_max_dxy_px, log=log
            )
            fused = _groups_to_fused_merges(raw_use, groups)
            gst = dict(gst0)
            gst["fuse_mode"] = "euclidean"
        log.info("drawing %d fused yellow boxes (from %d raw in crop)", len(fused), len(raw_use))

        for fb in fused:
            xa1, ya1, xa2, ya2 = rect_xy(fb, ny, nx)
            cv2.rectangle(xy_bgr, (xa1, ya1), (xa2, ya2), YELLOW_BGR, thickness, lineType=_LINE_YELLOW)
    else:
        log.info("--no-fuse-3d: drawing %d raw slice boxes in yellow", len(raw_use))
        _draw_raw_boxes_xy(xy_bgr, raw_use, ny, nx, thickness)
        _draw_raw_boxes_xz(xz_bgr, raw_use, nz, nx, thickness)
        _draw_raw_boxes_yz(yz_bgr, raw_use, nz, ny, thickness)

    boxes_for_mat: list[FusedMergeBox] = (
        list(fused) if args.fuse_3d else [_fused_placeholder_from_slice(b) for b in raw_use]
    )
    if args.export_fused_3d_mat is not None:
        fuse_mode_str = str(args.fuse_mode) if args.fuse_3d else "raw_slice_boxes"
        export_fused_3d_boxes_mat(
            Path(args.export_fused_3d_mat),
            boxes_for_mat,
            ny=ny,
            nx=nx,
            nz=nz,
            crop_z_offset=int(crop_z_offset),
            rect_xy=rect_xy,
            gst=gst,
            fuse_3d=bool(args.fuse_3d),
            fuse_mode=fuse_mode_str,
            summary_path=str(Path(args.summary).resolve()),
            volume_path=str(vol_path.resolve()),
            fused_box_style=str(args.fused_box_style),
            transpose_for_neuropal=not bool(args.export_fused_3d_mat_neuropal_keep_numpy_axes),
            include_label_vol=bool(args.export_fused_3d_mat_label_vol),
            log=log,
        )

    if args.export_fused_xy_slices_dir is not None:
        export_xy_slices_merged_yellow(
            volume,
            fuse_3d=bool(args.fuse_3d),
            fused=fused,
            raw_use=raw_use,
            rect_xy=rect_xy,
            ny=ny,
            nx=nx,
            out_dir=Path(args.export_fused_xy_slices_dir),
            line_thickness=thickness,
            stretch_percentile=bool(args.stretch_fused_slices),
            p_lo=float(args.p_lo),
            p_hi=float(args.p_hi),
            log=log,
        )

    # Side-by-side triptych: layout + optional labels (see --side-panels).
    if args.side_panels == "match-xy-frame":
        xz_rs, sxz, x0xz, y0xz = _letterbox_to(xz_bgr, out_h=ny, out_w=nx)
        yz_rs, syz, x0yz, y0yz = _letterbox_to(yz_bgr, out_h=ny, out_w=nx)
        xz_rs_c_only, sxz_c, x0xz_c, y0xz_c = _letterbox_to(xz_mip_clean, out_h=ny, out_w=nx)
        yz_rs_c_only, syz_c, x0yz_c, y0yz_c = _letterbox_to(yz_mip_clean, out_h=ny, out_w=nx)
        if not np.isclose(sxz, syz):
            log.debug("letterbox scales differ (xz=%.6g yz=%.6g) — expected if nx≠ny", sxz, syz)
    else:
        xz_rs, sxz = _uniform_resize_hw(xz_bgr, target_h=ny)
        yz_rs, syz = _uniform_resize_hw(yz_bgr, target_h=ny)
        xz_rs_c_only, sxz_c = _uniform_resize_hw(xz_mip_clean, target_h=ny)
        yz_rs_c_only, syz_c = _uniform_resize_hw(yz_mip_clean, target_h=ny)
        x0xz = y0xz = x0yz = y0yz = 0
        x0xz_c = y0xz_c = x0yz_c = y0yz_c = 0
        if not np.isclose(sxz, syz):
            log.warning(
                "XZ/YZ stretch-height scales differ unexpectedly (xz=%.6g yz=%.6g); check volume shape",
                sxz,
                syz,
            )

    if args.fuse_3d:
        for cid, fb in enumerate(fused, start=1):
            xc1, zr1, xc2, zr2 = rect_native_xz(fb, nz, nx)
            if args.side_panels == "match-xy-frame":
                xc1, zr1, xc2, zr2 = _map_rect_letterbox(
                    xc1, zr1, xc2, zr2, s=sxz, x0=x0xz, y0=y0xz
                )
            else:
                xc1, zr1, xc2, zr2 = _scale_rect_inplace((xc1, zr1, xc2, zr2), sx=sxz, sy=sxz)
            xc1 = int(np.clip(xc1, 0, xz_rs.shape[1] - 1))
            xc2 = int(np.clip(xc2, 0, xz_rs.shape[1] - 1))
            zr1 = int(np.clip(zr1, 0, xz_rs.shape[0] - 1))
            zr2 = int(np.clip(zr2, 0, xz_rs.shape[0] - 1))
            cv2.rectangle(xz_rs, (xc1, zr1), (xc2, zr2), YELLOW_BGR, thickness, lineType=_LINE_YELLOW)

            yc1, zz1, yc2, zz2 = rect_native_yz(fb, nz, ny)
            if args.side_panels == "match-xy-frame":
                yc1, zz1, yc2, zz2 = _map_rect_letterbox(
                    yc1, zz1, yc2, zz2, s=syz, x0=x0yz, y0=y0yz
                )
            else:
                yc1, zz1, yc2, zz2 = _scale_rect_inplace((yc1, zz1, yc2, zz2), sx=syz, sy=syz)
            yc1 = int(np.clip(yc1, 0, yz_rs.shape[1] - 1))
            yc2 = int(np.clip(yc2, 0, yz_rs.shape[1] - 1))
            zz1 = int(np.clip(zz1, 0, yz_rs.shape[0] - 1))
            zz2 = int(np.clip(zz2, 0, yz_rs.shape[0] - 1))
            cv2.rectangle(yz_rs, (yc1, zz1), (yc2, zz2), YELLOW_BGR, thickness, lineType=_LINE_YELLOW)

            if args.fusion_proof:
                xa1, ya1, xa2, ya2 = rect_xy(fb, ny, nx)
                _draw_fused_proof_tag(
                    xy_bgr,
                    xa1,
                    ya1,
                    xa2,
                    ya2,
                    cluster_id=cid,
                    fb=fb,
                    font_scale=fs_panel,
                    line_spacing=18,
                )
                _draw_fused_proof_tag(
                    xz_rs,
                    xc1,
                    zr1,
                    xc2,
                    zr2,
                    cluster_id=cid,
                    fb=fb,
                    font_scale=fs_panel,
                    line_spacing=18,
                )
                _draw_fused_proof_tag(
                    yz_rs,
                    yc1,
                    zz1,
                    yc2,
                    zz2,
                    cluster_id=cid,
                    fb=fb,
                    font_scale=fs_panel,
                    line_spacing=18,
                )

    if args.show_fused_centroids and not args.centroids_separate_panels:
        cb = tuple(int(np.clip(int(x), 0, 255)) for x in args.centroid_bgr)
        cr = max(1, int(args.centroid_radius))
        if args.fuse_3d:
            _draw_fused_centroids_triptych(
                xy_bgr=xy_bgr,
                xz_rs=xz_rs,
                yz_rs=yz_rs,
                fused=fused,
                ny=ny,
                nx=nx,
                nz=nz,
                side_panels=args.side_panels,
                sxz=float(sxz),
                syz=float(syz),
                x0xz=x0xz,
                y0xz=y0xz,
                x0yz=x0yz,
                y0yz=y0yz,
                radius=cr,
                bgr=cb,
            )
        else:
            _draw_raw_centroids_triptych(
                xy_bgr=xy_bgr,
                xz_rs=xz_rs,
                yz_rs=yz_rs,
                raw_use=raw_use,
                ny=ny,
                nx=nx,
                nz=nz,
                side_panels=args.side_panels,
                sxz=float(sxz),
                syz=float(syz),
                x0xz=x0xz,
                y0xz=y0xz,
                x0yz=x0yz,
                y0yz=y0yz,
                radius=cr,
                bgr=cb,
            )

    if args.fuse_3d and gst is not None:
        if args.fuse_mode == "iou-color":
            col_note = " IoU+dz only (--no-color-match)" if args.no_color_match else f" IoU+dz+RGB cos≥{args.color_dot_min}"
            print(
                f"[fuse iou-color] {len(raw_use)} slice-box detections → {len(fused)} fused boxes "
                f"(depth-sanity dropped clusters: {int(gst.get('depth_sanity_rejected_components', 0))}; "
                f"largest merge x{int(gst['max_merge_size'])})\n"
                f"       |Δz|≤{args.fuse_max_dz} IoU≥{args.iou_min}{col_note} · timing JSON",
                flush=True,
            )
        else:
            print(
                f"[fuse] {len(raw_use)} slice-box detections -> {len(fused)} fused groups "
                f"(largest merge x{int(gst['max_merge_size'])})\n"
                f"       link rule: |dz| in 1..{args.fuse_max_dz}, "
                f"sqrt(dx^2+dy^2)<={args.fuse_max_dxy_px} px (details in timing JSON)",
                flush=True,
            )

    extra_xy_lines: tuple[str, ...] = ()
    if args.fusion_proof:
        if args.fuse_3d and gst is not None:
            if args.fuse_mode == "iou-color":
                extra_xy_lines = (
                    f"{len(raw_use)} slice-boxes → {len(fused)} IoU/color fused (#tags)",
                    f"|dz|≤{args.fuse_max_dz} IoU≥{args.iou_min}",
                )
            else:
                extra_xy_lines = (
                    f"{len(raw_use)} slice-boxes -> {len(fused)} fused (max x{int(gst['max_merge_size'])})",
                    f"|dz|<={args.fuse_max_dz} d_xy<={args.fuse_max_dxy_px}px (#tags on boxes)",
                )
        elif not args.fuse_3d:
            extra_xy_lines = ("Per-slice boxes only (--no-fuse-3d).",)

    band_tight: dict[str, float | int] = dict(max_band_px_cap=52, max_band_fraction=0.052, line_spacing=20)
    band_proof: dict[str, float | int] = dict(max_band_px_cap=108, max_band_fraction=0.09, line_spacing=18)
    lbl_fs = float(np.clip(fs_panel * 0.98, 0.52, 0.88))

    def _pane_args(is_xy: bool) -> dict[str, float | int]:
        if extra_xy_lines and is_xy:
            return band_proof
        return band_tight

    centroid_only_paths: list[str] = []

    _annotate_triptych_label(
        xy_bgr,
        "XY",
        "",
        extra_lines=extra_xy_lines,
        font_scale=lbl_fs,
        **_pane_args(True),
    )
    _annotate_triptych_label(xz_rs, "XZ", "", font_scale=lbl_fs, **_pane_args(False))
    _annotate_triptych_label(yz_rs, "YZ", "", font_scale=lbl_fs, **_pane_args(False))

    if args.show_fused_centroids and args.centroids_separate_panels:
        cb = tuple(int(np.clip(int(x), 0, 255)) for x in args.centroid_bgr)
        cr = max(1, int(args.centroid_radius))
        xy_c = xy_mip_clean.copy()
        xz_c = xz_rs_c_only.copy()
        yz_c = yz_rs_c_only.copy()
        if args.fuse_3d:
            _draw_fused_centroids_triptych(
                xy_bgr=xy_c,
                xz_rs=xz_c,
                yz_rs=yz_c,
                fused=fused,
                ny=ny,
                nx=nx,
                nz=nz,
                side_panels=args.side_panels,
                sxz=float(sxz_c),
                syz=float(syz_c),
                x0xz=x0xz_c,
                y0xz=y0xz_c,
                x0yz=x0yz_c,
                y0yz=y0yz_c,
                radius=cr,
                bgr=cb,
            )
        else:
            _draw_raw_centroids_triptych(
                xy_bgr=xy_c,
                xz_rs=xz_c,
                yz_rs=yz_c,
                raw_use=raw_use,
                ny=ny,
                nx=nx,
                nz=nz,
                side_panels=args.side_panels,
                sxz=float(sxz_c),
                syz=float(syz_c),
                x0xz=x0xz_c,
                y0xz=y0xz_c,
                x0yz=x0yz_c,
                y0yz=y0yz_c,
                radius=cr,
                bgr=cb,
            )
        _annotate_triptych_label(xy_c, "XY", "centroids", font_scale=lbl_fs, **band_tight)
        _annotate_triptych_label(xz_c, "XZ", "centroids", font_scale=lbl_fs, **band_tight)
        _annotate_triptych_label(yz_c, "YZ", "centroids", font_scale=lbl_fs, **band_tight)
        stem_c = args.out_png.stem
        suf_c = args.out_png.suffix if args.out_png.suffix else ".png"
        pdir_c = args.out_png.parent
        for plane, arr in (("xy", xy_c), ("xz", xz_c), ("yz", yz_c)):
            outp_c = pdir_c / f"{stem_c}_centroids_only_{plane}{suf_c}"
            cv2.imwrite(str(outp_c), arr)
            centroid_only_paths.append(str(outp_c.resolve()))
        log.info("centroid-only triptych panels → %s", centroid_only_paths)

    triptych = np.hstack([xy_bgr, xz_rs, yz_rs])
    args.out_png.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(args.out_png), triptych)

    split_written: list[str] = []
    if args.save_split_views:
        sdir = args.split_views_dir if args.split_views_dir is not None else args.out_png.parent
        stem = args.out_png.stem
        suf = args.out_png.suffix if args.out_png.suffix else ".png"
        xy_split = sdir / f"{stem}_view_xy{suf}"
        zs = float(np.clip(args.split_xy_zoom, 0.1, 16.0))
        cents_cb = tuple(int(np.clip(int(x), 0, 255)) for x in args.centroid_bgr)
        sr_split = max(1, int(args.split_centroid_radius))
        if abs(zs - 1.0) < 1e-6:
            cv2.imwrite(str(xy_split), xy_bgr)
        else:
            h, w = int(xy_bgr.shape[0]), int(xy_bgr.shape[1])
            xy_it = _cv_resize_interp(args.split_xy_interp)
            rw = max(1, int(round(w * zs)))
            rh = max(1, int(round(h * zs)))
            xy_scaled = cv2.resize(xy_bgr, (rw, rh), interpolation=xy_it)
            if args.show_fused_centroids and not args.centroids_separate_panels:
                if args.fuse_3d:
                    for fb in fused:
                        px = int(np.clip(int(round(fb.cx * zs)), 0, rw - 1))
                        py = int(np.clip(int(round(fb.cy * zs)), 0, rh - 1))
                        cv2.circle(xy_scaled, (px, py), sr_split, cents_cb, -1, cv2.LINE_AA)
                else:
                    for b in raw_use:
                        px = int(np.clip(int(round(b.cx * zs)), 0, rw - 1))
                        py = int(np.clip(int(round(b.cy * zs)), 0, rh - 1))
                        cv2.circle(xy_scaled, (px, py), sr_split, cents_cb, -1, cv2.LINE_AA)
            cv2.imwrite(str(xy_split), xy_scaled)
        split_written.append(str(xy_split.resolve()))

        min_native_side = int(np.clip(int(args.split_min_native_side_pixels), 1, 1024))
        xz_rects_split: list[tuple[int, int, int, int]] = []
        yz_rects_split: list[tuple[int, int, int, int]] = []
        xz_centroids_split: list[tuple[int, int]] = []
        yz_centroids_split: list[tuple[int, int]] = []
        if args.fuse_3d:
            if args.fusion_proof:
                log.info(
                    "--fusion-proof: #id chips are omitted on split XZ/YZ exports "
                    "(still drawn on triptych side panels)."
                )
            for fb in fused:
                xc1, zr1, xc2, zr2 = rect_native_xz(fb, nz, nx)
                xc1, zr1, xc2, zr2 = _split_expand_native_xz(xc1, zr1, xc2, zr2, nx, nz, min_native_side)
                xz_rects_split.append((xc1, zr1, xc2, zr2))
                yc1, zz1, yc2, zz2 = rect_native_yz(fb, nz, ny)
                yc1, zz1, yc2, zz2 = _split_expand_native_yz(yc1, zz1, yc2, zz2, ny, nz, min_native_side)
                yz_rects_split.append((yc1, zz1, yc2, zz2))
                if args.show_fused_centroids:
                    xz_centroids_split.append(
                        (
                            int(np.clip(int(round(fb.cx)), 0, nx - 1)),
                            int(np.clip(int(round(fb.z_mean)), 0, nz - 1)),
                        )
                    )
                    yz_centroids_split.append(
                        (
                            int(np.clip(int(round(fb.cy)), 0, ny - 1)),
                            int(np.clip(int(round(fb.z_mean)), 0, nz - 1)),
                        )
                    )
        else:
            for b in raw_use:
                xc1, zr1, xc2, zr2 = _xz_rect_envelope(_fused_placeholder_from_slice(b), nz, nx)
                xc1, zr1, xc2, zr2 = _split_expand_native_xz(xc1, zr1, xc2, zr2, nx, nz, min_native_side)
                xz_rects_split.append((xc1, zr1, xc2, zr2))
                yc1, zz1, yc2, zz2 = _yz_rect_envelope(_fused_placeholder_from_slice(b), nz, ny)
                yc1, zz1, yc2, zz2 = _split_expand_native_yz(yc1, zz1, yc2, zz2, ny, nz, min_native_side)
                yz_rects_split.append((yc1, zz1, yc2, zz2))
                if args.show_fused_centroids:
                    xz_centroids_split.append(
                        (
                            int(np.clip(int(round(b.cx)), 0, nx - 1)),
                            int(np.clip(int(round(float(b.z))), 0, nz - 1)),
                        )
                    )
                    yz_centroids_split.append(
                        (
                            int(np.clip(int(round(b.cy)), 0, ny - 1)),
                            int(np.clip(int(round(float(b.z))), 0, nz - 1)),
                        )
                    )

        s_lt = max(1, int(args.split_view_line_thickness))
        s_fill = float(np.clip(args.split_view_fill_alpha, 0.0, 0.85))
        xz_p = sdir / f"{stem}_view_xz{suf}"
        yz_p = sdir / f"{stem}_view_yz{suf}"
        split_it = _cv_resize_interp(args.split_view_interp)
        post_xz = float(np.clip(args.split_view_post_sharpen, 0.0, 2.5))
        split_lbl_gap = max(0, int(args.split_view_label_gap))
        _export_zoomed_split_view(
            xz_bgr.copy(),
            xz_p,
            "XZ",
            lbl_fs=lbl_fs,
            zoom=float(np.clip(args.split_view_zoom, 0.25, 32.0)),
            z_stretch=float(np.clip(args.split_view_z_stretch, 0.5, 12.0)),
            band_kw=band_tight,
            resize_interp=split_it,
            post_sharpen=post_xz,
            native_rects_xyxy=xz_rects_split,
            split_line_thickness=s_lt,
            split_fill_alpha=s_fill,
            native_centroids_col_row=(
                xz_centroids_split
                if args.show_fused_centroids and not args.centroids_separate_panels
                else None
            ),
            split_centroid_radius_px=sr_split,
            centroid_mark_bgr=cents_cb,
            label_gap_px=split_lbl_gap,
        )
        _export_zoomed_split_view(
            yz_bgr.copy(),
            yz_p,
            "YZ",
            lbl_fs=lbl_fs,
            zoom=float(np.clip(args.split_view_zoom, 0.25, 32.0)),
            z_stretch=float(np.clip(args.split_view_z_stretch, 0.5, 12.0)),
            band_kw=band_tight,
            resize_interp=split_it,
            post_sharpen=post_xz,
            native_rects_xyxy=yz_rects_split,
            split_line_thickness=s_lt,
            split_fill_alpha=s_fill,
            native_centroids_col_row=(
                yz_centroids_split
                if args.show_fused_centroids and not args.centroids_separate_panels
                else None
            ),
            split_centroid_radius_px=sr_split,
            centroid_mark_bgr=cents_cb,
            label_gap_px=split_lbl_gap,
        )
        split_written.extend([str(xz_p.resolve()), str(yz_p.resolve())])

        if args.show_fused_centroids and args.centroids_separate_panels:
            co_sr = max(1, int(args.centroids_only_split_radius))
            xy_co_p = sdir / f"{stem}_centroids_only_view_xy{suf}"
            h_xy0, w_xy0 = int(xy_mip_clean.shape[0]), int(xy_mip_clean.shape[1])
            if abs(zs - 1.0) < 1e-6:
                xy_co_img = xy_mip_clean.copy()
            else:
                rw_c = max(1, int(round(w_xy0 * zs)))
                rh_c = max(1, int(round(h_xy0 * zs)))
                xy_co_img = cv2.resize(xy_mip_clean.copy(), (rw_c, rh_c), interpolation=xy_it)
            if args.fuse_3d:
                for fb in fused:
                    px = int(np.clip(int(round(fb.cx * zs)), 0, int(xy_co_img.shape[1]) - 1))
                    py = int(np.clip(int(round(fb.cy * zs)), 0, int(xy_co_img.shape[0]) - 1))
                    cv2.circle(xy_co_img, (px, py), co_sr, cents_cb, -1, cv2.LINE_AA)
            else:
                for b in raw_use:
                    px = int(np.clip(int(round(b.cx * zs)), 0, int(xy_co_img.shape[1]) - 1))
                    py = int(np.clip(int(round(b.cy * zs)), 0, int(xy_co_img.shape[0]) - 1))
                    cv2.circle(xy_co_img, (px, py), co_sr, cents_cb, -1, cv2.LINE_AA)
            cv2.imwrite(str(xy_co_p), xy_co_img)
            centroid_only_paths.append(str(xy_co_p.resolve()))

            xz_co_p = sdir / f"{stem}_centroids_only_view_xz{suf}"
            yz_co_p = sdir / f"{stem}_centroids_only_view_yz{suf}"
            _export_zoomed_split_view(
                xz_mip_clean.copy(),
                xz_co_p,
                "XZ",
                lbl_fs=lbl_fs,
                zoom=float(np.clip(args.split_view_zoom, 0.25, 32.0)),
                z_stretch=float(np.clip(args.split_view_z_stretch, 0.5, 12.0)),
                band_kw=band_tight,
                resize_interp=split_it,
                post_sharpen=post_xz,
                native_rects_xyxy=[],
                split_line_thickness=s_lt,
                split_fill_alpha=0.0,
                native_centroids_col_row=xz_centroids_split or None,
                split_centroid_radius_px=co_sr,
                centroid_mark_bgr=cents_cb,
                label_gap_px=split_lbl_gap,
            )
            _export_zoomed_split_view(
                yz_mip_clean.copy(),
                yz_co_p,
                "YZ",
                lbl_fs=lbl_fs,
                zoom=float(np.clip(args.split_view_zoom, 0.25, 32.0)),
                z_stretch=float(np.clip(args.split_view_z_stretch, 0.5, 12.0)),
                band_kw=band_tight,
                resize_interp=split_it,
                post_sharpen=post_xz,
                native_rects_xyxy=[],
                split_line_thickness=s_lt,
                split_fill_alpha=0.0,
                native_centroids_col_row=yz_centroids_split or None,
                split_centroid_radius_px=co_sr,
                centroid_mark_bgr=cents_cb,
                label_gap_px=split_lbl_gap,
            )
            centroid_only_paths.extend([str(xz_co_p.resolve()), str(yz_co_p.resolve())])
            log.info("centroid-only split views → %s", [str(xy_co_p), str(xz_co_p), str(yz_co_p)])

        log.info("split views → %s", split_written)

    wall = time.perf_counter() - t0
    timing = {
        "seconds_wall_total": round(wall, 6),
        "volume_shape_nyxnz": [ny, nx, nz],
        "crop_z_offset": crop_z_offset,
        "num_raw_boxes_summary": len(raw_boxes),
        "num_boxes_in_crop": len(raw_use),
        "fuse_3d": bool(args.fuse_3d),
        "fuse_mode": str(args.fuse_mode),
        "fuse_max_dz": int(args.fuse_max_dz),
        "fuse_max_dxy_px": float(args.fuse_max_dxy_px),
        "iou_min": float(args.iou_min) if args.fuse_mode == "iou-color" else None,
        "iou_no_color_match": bool(args.no_color_match) if args.fuse_mode == "iou-color" else None,
        "iou_color_dot_min": float(args.color_dot_min) if args.fuse_mode == "iou-color" else None,
        "iou_color_feature": str(args.color_feature) if args.fuse_mode == "iou-color" else None,
        "no_depth_sanity": bool(args.no_depth_sanity) if args.fuse_mode == "iou-color" else None,
        "depth_sanity_ratio_cap": float(args.depth_sanity_ratio_cap)
        if args.fuse_mode == "iou-color"
        else None,
        "voxel_spacing_um": list(float(x) for x in args.voxel_spacing_um)
        if args.fuse_mode == "iou-color"
        else None,
        "fuse_stats": gst if args.fuse_3d else None,
        "num_fused": len(boxes_for_mat),
        "export_fused_3d_mat": str(args.export_fused_3d_mat.resolve())
        if args.export_fused_3d_mat is not None
        else None,
        "export_fused_3d_mat_label_vol": bool(args.export_fused_3d_mat_label_vol)
        if args.export_fused_3d_mat is not None
        else None,
        "fused_box_style": str(args.fused_box_style),
        "side_panels": args.side_panels,
        "fusion_proof": bool(args.fusion_proof),
        "show_fused_centroids": bool(args.show_fused_centroids),
        "centroids_separate_panels": bool(args.centroids_separate_panels),
        "centroid_only_paths": centroid_only_paths,
        "centroid_radius": int(args.centroid_radius) if args.show_fused_centroids else None,
        "centroid_bgr": list(int(x) for x in args.centroid_bgr) if args.show_fused_centroids else None,
        "split_centroid_radius": int(args.split_centroid_radius)
        if args.show_fused_centroids and args.save_split_views
        else None,
        "centroids_only_split_radius": int(args.centroids_only_split_radius)
        if args.show_fused_centroids and args.centroids_separate_panels and args.save_split_views
        else None,
        "side_mip_p_lo": sp_lo,
        "side_mip_p_hi": sp_hi,
        "side_mip_clahe": bool(args.side_mip_clahe),
        "side_mip_clahe_clip": float(args.side_mip_clahe_clip),
        "side_mip_sharpen": float(args.side_mip_sharpen),
        "save_split_views": bool(args.save_split_views),
        "split_views_dir": str(args.split_views_dir.resolve())
        if args.save_split_views and args.split_views_dir is not None
        else None,
        "split_view_zoom": float(args.split_view_zoom) if args.save_split_views else None,
        "split_view_z_stretch": float(args.split_view_z_stretch) if args.save_split_views else None,
        "split_xy_zoom": float(args.split_xy_zoom) if args.save_split_views else None,
        "split_view_interp": str(args.split_view_interp) if args.save_split_views else None,
        "split_view_post_sharpen": float(args.split_view_post_sharpen) if args.save_split_views else None,
        "split_view_line_thickness": int(args.split_view_line_thickness)
        if args.save_split_views
        else None,
        "split_min_native_side_pixels": int(args.split_min_native_side_pixels)
        if args.save_split_views
        else None,
        "split_view_fill_alpha": float(args.split_view_fill_alpha) if args.save_split_views else None,
        "split_view_label_gap": int(args.split_view_label_gap) if args.save_split_views else None,
        "split_xy_interp": str(args.split_xy_interp) if args.save_split_views else None,
        "split_view_paths": split_written if args.save_split_views else [],
        "out_png": str(args.out_png.resolve()),
    }
    tpath = args.timing_json or (args.out_png.parent / f"{args.out_png.stem}_merged_yellow_mip_timing.json")
    tpath.write_text(json.dumps(timing, indent=2), encoding="utf-8")

    log.info("[ok] wall %.4fs → %s (triptych %s)", wall, args.out_png.resolve(), triptych.shape)
    print(f"[ok] wall {wall:.4f}s → {args.out_png} · boxes_for_mat={len(boxes_for_mat)} raw_in_crop={len(raw_use)}")
    if args.export_fused_3d_mat is not None:
        print(f"  fused 3D .mat → {args.export_fused_3d_mat.resolve()}")
    if centroid_only_paths:
        print("centroid-only PNGs:")
        for p in centroid_only_paths:
            print(f"  {p}")
    if args.save_split_views:
        print("split PNGs:")
        for p in split_written:
            print(f"  {p}")


if __name__ == "__main__":
    main()
