#!/usr/bin/env python3
"""
Post-filter fused 3D neurons by XY footprint L/W (µm) after 3D fusion.

Use when slice-level area filtering is too early (end-Z boxes look smaller).
Re-runs the same 3D fuse as viz/mip on predictions_summary.json, then drops
clusters whose axis-aligned XY envelope fails 1st-order length bounds; optional
L×W (µm²) band.

Typical workflow:
  infer → [filter_predictions_box_area.py] → fuse (viz / mip_centroids_*) →
  filter_fused_neurons_lw_um.py → viz / mip on --out-summary

Does not filter Z depth (use fusion depth sanity) or re-run YOLO.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import logging
from dataclasses import asdict
from pathlib import Path
from typing import Any, Sequence

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
_LOG = "filter_fused_lw_um"


def _load_module(name: str, filename: str) -> Any:
    import sys

    path = SCRIPT_DIR / filename
    spec = importlib.util.spec_from_file_location(name, str(path))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


viz = _load_module("viz_mip_yellow", "viz_mip_merged_yellow_boxes.py")
iou_fuse = _load_module("mip_iou_color", "mip_centroids_iou_color_fuse.py")

RawBox = viz.RawBox
FusedMergeBox = viz.FusedMergeBox
_collect_raw_boxes = viz._collect_raw_boxes
fuse_boxes_into_groups = viz.fuse_boxes_into_groups
_groups_to_fused_merges = viz._groups_to_fused_merges
Detection = iou_fuse.Detection
fuse_components = iou_fuse.fuse_components
depth_sanity_ok = iou_fuse.depth_sanity_ok
crop_box_rgb = iou_fuse.crop_box_rgb
feature_percentiles = iou_fuse.feature_percentiles
kde_peak_per_channel = iou_fuse.kde_peak_per_channel


def load_volume(path: Path) -> np.ndarray:
    vol = np.load(path, allow_pickle=True)
    if vol.dtype == object:
        raise ValueError("Expected one dense volume, got an object array.")
    vol = np.asarray(vol)
    if vol.ndim == 3:
        vol = vol[..., np.newaxis]
    if vol.ndim != 4:
        raise ValueError(f"Expected volume shape (X,Y,Z,C), got {vol.shape}")
    return vol


def summary_z_window(summary: dict[str, Any]) -> tuple[int, int] | None:
    zs: list[int] = []
    for block in summary.get("slices") or []:
        if "z" in block:
            zs.append(int(block["z"]))
    if not zs:
        return None
    return min(zs), max(zs)


def raw_in_crop_indexed(
    boxes: list[RawBox],
    crop_z_offset: int,
    nz: int,
) -> tuple[list[RawBox], list[int]]:
    """Return cropped boxes for fusion and flat indices into ``boxes``."""
    out: list[RawBox] = []
    flat_idx: list[int] = []
    for fi, b in enumerate(boxes):
        zi = b.z - crop_z_offset
        if 0 <= zi < nz:
            out.append(
                RawBox(
                    z=zi,
                    x1=b.x1,
                    y1=b.y1,
                    x2=b.x2,
                    y2=b.y2,
                    cx=b.cx,
                    cy=b.cy,
                    conf=b.conf,
                )
            )
            flat_idx.append(fi)
    return out, flat_idx


def raw_in_z_window_indexed(
    boxes: list[RawBox],
    z0: int,
    z1: int,
) -> tuple[list[RawBox], list[int]]:
    out: list[RawBox] = []
    flat_idx: list[int] = []
    for fi, b in enumerate(boxes):
        if z0 <= b.z <= z1:
            out.append(b)
            flat_idx.append(fi)
    return out, flat_idx


def fuse_with_groups(
    raw_use: list[RawBox],
    volume: np.ndarray | None,
    *,
    fuse_mode: str,
    fuse_max_dz: int,
    fuse_max_dxy_px: float,
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
) -> tuple[list[tuple[FusedMergeBox, list[int]]], dict[str, Any]]:
    if fuse_mode == "euclidean":
        groups, gst = fuse_boxes_into_groups(
            raw_use,
            max_dz=int(fuse_max_dz),
            max_dxy_px=float(fuse_max_dxy_px),
            log=log,
        )
        fused = _groups_to_fused_merges(raw_use, groups)
        gst["fuse_mode"] = "euclidean"
        return list(zip(fused, groups)), gst

    if volume is None:
        raise ValueError("iou-color fusion requires --volume or summary['volume']")

    dets = [Detection(b.z, b.x1, b.y1, b.x2, b.y2, b.conf) for b in raw_use]
    feats: list[np.ndarray] | None = None
    if require_color:
        feats = []
        for d in dets:
            px = crop_box_rgb(volume, int(d.z), d.x1, d.y1, d.x2, d.y2)
            if px.size == 0:
                feats.append(
                    np.zeros((9 if color_feature == "percentiles" else 3), dtype=np.float64)
                )
                continue
            if color_feature == "percentiles":
                feats.append(feature_percentiles(px, color_percentiles))
            else:
                feats.append(
                    kde_peak_per_channel(
                        px,
                        nbins_floor=int(kde_bin_count_min),
                        bandwidth_bins=float(kde_bandwidth_bins),
                    )
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
    kept: list[tuple[FusedMergeBox, list[int]]] = []
    n_reject = 0
    for g in groups:
        sub = [dets[i] for i in g]
        if not no_depth_sanity and not depth_sanity_ok(
            sub, sx_um, sy_um, sz_um, float(depth_sanity_ratio_cap), log=None
        ):
            n_reject += 1
            continue
        fb = _groups_to_fused_merges(raw_use, [g])[0]
        kept.append((fb, g))

    gst = dict(fuse_stats)
    gst["depth_sanity_rejected_components"] = int(n_reject)
    gst["num_groups_after_depth_sanity"] = len(kept)
    gst["fuse_mode"] = "iou-color"
    gst["iou_min"] = float(iou_min)
    gst["require_color"] = bool(require_color)
    gst["color_dot_min"] = float(color_dot_min)
    return kept, gst


def envelope_lw_um(
    fb: FusedMergeBox,
    sx_um: float,
    sy_um: float,
) -> tuple[float, float, float]:
    """L = X extent, W = Y extent (µm); LW2 = L×W (µm²) from fused XY envelope."""
    l_px = max(float(fb.x2u) - float(fb.x1u), 0.0)
    w_px = max(float(fb.y2u) - float(fb.y1u), 0.0)
    l_um = l_px * sx_um
    w_um = w_px * sy_um
    return l_um, w_um, l_um * w_um


def lw_percentile_limits(
    l_all: np.ndarray,
    w_all: np.ndarray,
    *,
    p_lo: float,
    p_hi: float,
) -> tuple[float, float, float, float, dict[str, Any]]:
    """Per-dimension percentile bands on fused envelope L and W (µm)."""
    l_lo = float(np.percentile(l_all, p_lo)) if l_all.size else 0.0
    l_hi = float(np.percentile(l_all, p_hi)) if l_all.size else np.inf
    w_lo = float(np.percentile(w_all, p_lo)) if w_all.size else 0.0
    w_hi = float(np.percentile(w_all, p_hi)) if w_all.size else np.inf
    return l_lo, l_hi, w_lo, w_hi, {
        "filter_mode": "percentile",
        "lw_p_lo": float(p_lo),
        "lw_p_hi": float(p_hi),
        "L_um_lo": l_lo,
        "L_um_hi": l_hi,
        "W_um_lo": w_lo,
        "W_um_hi": w_hi,
    }


def lw_passes(
    l_um: float,
    w_um: float,
    lw2_um: float,
    *,
    min_l_um: float,
    max_l_um: float,
    min_w_um: float,
    max_w_um: float,
    check_lw2: bool,
    min_lw2_um: float | None,
    max_lw2_um: float | None,
) -> tuple[bool, str | None]:
    if l_um < min_l_um - 1e-9:
        return False, f"L_um={l_um:.4f}<{min_l_um}"
    if l_um > max_l_um + 1e-9:
        return False, f"L_um={l_um:.4f}>{max_l_um}"
    if w_um < min_w_um - 1e-9:
        return False, f"W_um={w_um:.4f}<{min_w_um}"
    if w_um > max_w_um + 1e-9:
        return False, f"W_um={w_um:.4f}>{max_w_um}"
    if check_lw2:
        lo2 = float(min_lw2_um if min_lw2_um is not None else 0.0)
        hi2 = float(max_lw2_um if max_lw2_um is not None else np.inf)
        if lw2_um < lo2 - 1e-9:
            return False, f"LW2_um={lw2_um:.4f}<{lo2}"
        if lw2_um > hi2 + 1e-9:
            return False, f"LW2_um={lw2_um:.4f}>{hi2}"
    return True, None


def fused_record(
    fb: FusedMergeBox,
    members: list[int],
    l_um: float,
    w_um: float,
    lw2_um: float,
) -> dict[str, Any]:
    d = asdict(fb)
    d["member_indices"] = [int(i) for i in members]
    d["L_um"] = float(l_um)
    d["W_um"] = float(w_um)
    d["LW2_um"] = float(lw2_um)
    return d


def filter_summary_by_members_fast(
    summary: dict[str, Any],
    raw_boxes: list[RawBox],
    keep_idx: set[int],
) -> tuple[dict[str, Any], int, int]:
    n_before = 0
    n_after = 0
    out_slices = []
    flat_i = 0
    for block in summary.get("slices") or []:
        boxes = list(block.get("boxes_xyxy_conf") or [])
        n_before += len(boxes)
        kept = []
        for b in boxes:
            if flat_i in keep_idx and flat_i < len(raw_boxes):
                kept.append(b)
            flat_i += 1
        n_after += len(kept)
        nb = dict(block)
        nb["boxes_xyxy_conf"] = kept
        nb["n_predictions"] = len(kept)
        out_slices.append(nb)

    out = dict(summary)
    out["slices"] = out_slices
    out["total_predictions"] = int(n_after)
    return out, n_before, n_after


def compute_fused_lw_arrays(
    summary: dict[str, Any],
    *,
    volume_path: Path | None = None,
    fuse_mode: str = "iou-color",
    fuse_max_dz: int = 1,
    fuse_max_dxy_px: float = 6.0,
    iou_min: float = 0.5,
    require_color: bool = False,
    color_feature: str = "percentiles",
    color_percentiles: Sequence[float] = (50.0, 75.0, 90.0),
    color_dot_min: float = 0.8,
    kde_bin_count_min: int = 8,
    kde_bandwidth_bins: float = 3.0,
    depth_sanity_ratio_cap: float = 1.5,
    no_depth_sanity: bool = False,
    voxel_spacing_um: tuple[float, float, float] = (0.4, 0.4, 1.5),
    crop_z_to_summary: bool = True,
    log: logging.Logger | None = None,
) -> tuple[np.ndarray, np.ndarray, int, dict[str, Any]]:
    """Fuse summary detections; return per-cluster L_um, W_um arrays and fuse_stats."""
    log = log or logging.getLogger(_LOG)
    raw_boxes, _short = _collect_raw_boxes(summary)
    volume: np.ndarray | None = None
    crop_z_offset = 0
    raw_use: list[RawBox]
    use_to_flat: list[int]

    if fuse_mode == "iou-color":
        vol_path = volume_path or Path(str(summary["volume"]))
        if not vol_path.is_file():
            raise FileNotFoundError(f"volume not found: {vol_path}")
        volume = load_volume(vol_path)
        nz = int(volume.shape[2])
        if crop_z_to_summary:
            z_win = summary_z_window(summary)
            if z_win is not None:
                z0, z1 = z_win
                volume = volume[:, :, z0 : z1 + 1, :]
                crop_z_offset = int(z0)
                nz = int(volume.shape[2])
        raw_use, use_to_flat = raw_in_crop_indexed(raw_boxes, crop_z_offset, nz)
    else:
        z_win = summary_z_window(summary) if crop_z_to_summary else None
        if z_win is not None:
            z0, z1 = z_win
            raw_use, use_to_flat = raw_in_z_window_indexed(raw_boxes, z0, z1)
        else:
            raw_use = list(raw_boxes)
            use_to_flat = list(range(len(raw_boxes)))

    spacing = tuple(float(x) for x in voxel_spacing_um)
    sx_um, sy_um = spacing[0], spacing[1]
    pairs, fuse_stats = fuse_with_groups(
        raw_use,
        volume,
        fuse_mode=str(fuse_mode),
        fuse_max_dz=int(fuse_max_dz),
        fuse_max_dxy_px=float(fuse_max_dxy_px),
        iou_min=float(iou_min),
        require_color=bool(require_color),
        color_feature=str(color_feature),
        color_percentiles=color_percentiles,
        color_dot_min=float(color_dot_min),
        kde_bin_count_min=int(kde_bin_count_min),
        kde_bandwidth_bins=float(kde_bandwidth_bins),
        voxel_spacing_um=spacing,
        depth_sanity_ratio_cap=float(depth_sanity_ratio_cap),
        no_depth_sanity=bool(no_depth_sanity),
        log=log,
    )
    l_list: list[float] = []
    w_list: list[float] = []
    for fb, _members in pairs:
        l_um, w_um, _ = envelope_lw_um(fb, sx_um, sy_um)
        l_list.append(l_um)
        w_list.append(w_um)
    fuse_stats["n_slice_boxes_in_summary"] = len(raw_boxes)
    fuse_stats["n_slice_boxes_in_fuse_crop"] = len(raw_use)
    return (
        np.asarray(l_list, dtype=np.float64),
        np.asarray(w_list, dtype=np.float64),
        len(pairs),
        fuse_stats,
    )


def count_lw_rejected(
    l_um: np.ndarray,
    w_um: np.ndarray,
    *,
    min_l_um: float,
    max_l_um: float,
    min_w_um: float,
    max_w_um: float,
) -> int:
    n = 0
    for i in range(l_um.size):
        ok, _ = lw_passes(
            float(l_um[i]),
            float(w_um[i]),
            float(l_um[i]) * float(w_um[i]),
            min_l_um=min_l_um,
            max_l_um=max_l_um,
            min_w_um=min_w_um,
            max_w_um=max_w_um,
            check_lw2=False,
            min_lw2_um=None,
            max_lw2_um=None,
        )
        if not ok:
            n += 1
    return n


def save_lw_histogram(
    l_um: np.ndarray,
    w_um: np.ndarray,
    path: Path,
    *,
    min_l: float,
    max_l: float,
    min_w: float,
    max_w: float,
    title: str,
    show_cutoffs: bool = True,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    path.parent.mkdir(parents=True, exist_ok=True)
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    for ax, vals, lo, hi, xlab in (
        (axes[0], l_um, min_l, max_l, "L (µm, X extent)"),
        (axes[1], w_um, min_w, max_w, "W (µm, Y extent)"),
    ):
        if vals.size:
            ax.hist(vals, bins=min(50, max(10, vals.size // 4)), color="#4a90d9", edgecolor="white")
            if show_cutoffs:
                ax.axvline(lo, color="orange", ls="--", lw=2, label=f"min={lo:.2f}")
                ax.axvline(hi, color="red", ls="--", lw=2, label=f"max={hi:.2f}")
        ax.set_xlabel(xlab)
        ax.set_ylabel("Count")
        if show_cutoffs:
            ax.legend(loc="upper right", fontsize=8)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def save_lw_compare_histogram(
    l_um: np.ndarray,
    w_um: np.ndarray,
    path: Path,
    *,
    sample_label: str,
    min_l: float,
    max_l: float,
    min_w: float,
    max_w: float,
    n_removed: int,
) -> None:
    """2×2: L/W without cutoffs (top) vs with min/max bands (bottom)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    path.parent.mkdir(parents=True, exist_ok=True)
    n = int(l_um.size)
    fig, axes = plt.subplots(2, 2, figsize=(11, 7))
    panels = (
        (axes[0, 0], l_um, "L (µm, X extent)", "No size exclusion"),
        (axes[0, 1], w_um, "W (µm, Y extent)", "No size exclusion"),
        (axes[1, 0], l_um, "L (µm, X extent)", f"min/max L,W = [{min_l:.1f}, {max_l:.1f}] µm"),
        (axes[1, 1], w_um, "W (µm, Y extent)", f"min/max L,W = [{min_l:.1f}, {max_l:.1f}] µm"),
    )
    for ax, vals, xlab, subtitle in panels:
        if vals.size:
            ax.hist(vals, bins=min(50, max(10, vals.size // 4)), color="#4a90d9", edgecolor="white")
        ax.set_xlabel(xlab)
        ax.set_ylabel("Count")
        ax.set_title(subtitle, fontsize=10)
        if "min/max" in subtitle:
            lo = min_l if "L (" in xlab else min_w
            hi = max_l if "L (" in xlab else max_w
            ax.axvline(lo, color="orange", ls="--", lw=2, label=f"min={lo:.1f}")
            ax.axvline(hi, color="red", ls="--", lw=2, label=f"max={hi:.1f}")
            ax.legend(loc="upper right", fontsize=7)

    kept = n - n_removed
    fig.suptitle(
        f"{sample_label} | fused n={n} | [{min_l:.0f},{max_l:.0f}] µm would remove "
        f"{n_removed} → keep {kept}",
        fontsize=11,
    )
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def filter_mat_rows(mat_path: Path, out_path: Path, keep_ids: set[int], log: logging.Logger) -> None:
    try:
        from scipy.io import loadmat, savemat  # type: ignore[import-untyped]
    except ImportError as e:
        raise RuntimeError("filtering .mat needs scipy (`pip install scipy`)") from e

    blob = loadmat(str(mat_path), squeeze_me=False, struct_as_record=False)
    key = "centroids_nby6_id_z_xy_conf_nm"
    if key not in blob:
        raise KeyError(f"{mat_path} missing variable {key!r}")
    table = np.asarray(blob[key], dtype=np.float64)
    if table.ndim != 2 or table.shape[1] < 6:
        raise ValueError(f"unexpected centroid table shape {table.shape}")

    rows = []
    for i in range(table.shape[0]):
        nid = int(round(float(table[i, 0])))
        if nid in keep_ids:
            rows.append(table[i])
    out_table = np.vstack(rows) if rows else np.zeros((0, 6), dtype=np.float64)

    out_blob = {k: blob[k] for k in blob if not k.startswith("__")}
    out_blob[key] = out_table
    if "mp_params" in out_blob:
        try:
            mp = out_blob["mp_params"]
            mp[0, 0]["n_centroids"] = np.asarray([[out_table.shape[0]]], dtype=np.int64)
        except Exception:
            pass
    out_path.parent.mkdir(parents=True, exist_ok=True)
    savemat(str(out_path), out_blob, do_compression=True)
    log.info("filtered .mat %d → %d rows → %s", table.shape[0], out_table.shape[0], out_path.resolve())


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Filter fused 3D neurons by XY envelope L/W (µm) after fusion."
    )
    ap.add_argument("--summary", type=Path, required=True)
    ap.add_argument("--out-summary", type=Path, required=True)
    ap.add_argument("--out-fused-json", type=Path, default=None, help="Kept/rejected fused neuron records.")
    ap.add_argument("--volume", type=Path, default=None, help="Required for iou-color (default summary volume).")
    ap.add_argument(
        "--fuse-mode",
        choices=("iou-color", "euclidean"),
        default="iou-color",
        help="Must match the fusion run you are filtering.",
    )
    ap.add_argument("--fuse-max-dz", type=int, default=1)
    ap.add_argument("--fuse-max-dxy-px", type=float, default=6.0, help="euclidean only.")
    ap.add_argument("--iou-min", type=float, default=0.5, help="iou-color only.")
    ap.add_argument("--no-color-match", action="store_true", help="iou-color: IoU only.")
    ap.add_argument("--color-feature", choices=("percentiles", "kde"), default="percentiles")
    ap.add_argument("--color-percentiles", type=float, nargs="+", default=[50.0, 75.0, 90.0])
    ap.add_argument("--color-dot-min", type=float, default=0.8)
    ap.add_argument("--kde-bin-count-min", type=int, default=8)
    ap.add_argument("--kde-bandwidth-bins", type=float, default=3.0)
    ap.add_argument("--depth-sanity-ratio-cap", type=float, default=1.5)
    ap.add_argument("--no-depth-sanity", action="store_true")
    ap.add_argument(
        "--voxel-spacing-um",
        type=float,
        nargs=3,
        metavar=("SX", "SY", "SZ"),
        default=[0.4, 0.4, 1.5],
    )
    ap.add_argument("--crop-z-to-summary", action="store_true")
    ap.add_argument(
        "--filter-mode",
        choices=("fixed", "percentile"),
        default="fixed",
        help="fixed: use min/max µm below; percentile: tail cutoffs on fused L and W separately.",
    )
    ap.add_argument("--min-l-um", type=float, default=1.5, help="fixed mode: discard if envelope L < this (µm).")
    ap.add_argument("--max-l-um", type=float, default=5.0, help="fixed mode: discard if envelope L > this (µm).")
    ap.add_argument("--min-w-um", type=float, default=1.5, help="fixed mode: discard if envelope W < this (µm).")
    ap.add_argument("--max-w-um", type=float, default=5.0, help="fixed mode: discard if envelope W > this (µm).")
    ap.add_argument("--lw-p-lo", type=float, default=5.0, help="percentile mode: lower percentile for L and W (default 5).")
    ap.add_argument("--lw-p-hi", type=float, default=95.0, help="percentile mode: upper percentile for L and W (default 95).")
    ap.add_argument(
        "--check-lw2",
        action="store_true",
        help="Also require min_l_um*min_w_um <= L×W <= max_l_um*max_w_um (µm²).",
    )
    ap.add_argument("--min-lw2-um", type=float, default=None, help="Explicit L×W lower bound (µm²).")
    ap.add_argument("--max-lw2-um", type=float, default=None, help="Explicit L×W upper bound (µm²).")
    ap.add_argument("--hist-png", type=Path, default=None, help="L and W histograms with cutoffs.")
    ap.add_argument("--stats-json", type=Path, default=None)
    ap.add_argument("--mat-in", type=Path, default=None, help="Optional fused .mat from mip export.")
    ap.add_argument("--mat-out", type=Path, default=None, help="Filtered .mat (requires --mat-in).")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s [%(name)s] %(message)s",
    )
    log = logging.getLogger(_LOG)

    summary = json.loads(args.summary.read_text(encoding="utf-8"))
    raw_boxes, _short = _collect_raw_boxes(summary)

    volume: np.ndarray | None = None
    crop_z_offset = 0
    raw_use: list[RawBox]
    use_to_flat: list[int]

    if args.fuse_mode == "iou-color":
        vol_path = Path(args.volume) if args.volume is not None else Path(str(summary["volume"]))
        if not vol_path.is_file():
            raise FileNotFoundError(f"volume not found: {vol_path}")
        volume = load_volume(vol_path)
        nz = int(volume.shape[2])
        if args.crop_z_to_summary:
            z_win = summary_z_window(summary)
            if z_win is not None:
                z0, z1 = z_win
                volume = volume[:, :, z0 : z1 + 1, :]
                crop_z_offset = int(z0)
                nz = int(volume.shape[2])
                log.info("cropped Z to summary [%d,%d] offset=%d", z0, z1, crop_z_offset)
        raw_use, use_to_flat = raw_in_crop_indexed(raw_boxes, crop_z_offset, nz)
    else:
        z_win = summary_z_window(summary) if args.crop_z_to_summary else None
        if z_win is not None:
            z0, z1 = z_win
            raw_use, use_to_flat = raw_in_z_window_indexed(raw_boxes, z0, z1)
            log.info("euclidean: Z window [%d,%d] → %d boxes", z0, z1, len(raw_use))
        else:
            raw_use = list(raw_boxes)
            use_to_flat = list(range(len(raw_boxes)))
    if len(raw_use) < len(raw_boxes):
        log.info(
            "%d detections outside cropped Z (using %d in crop)",
            len(raw_boxes) - len(raw_use),
            len(raw_use),
        )

    spacing = (float(args.voxel_spacing_um[0]), float(args.voxel_spacing_um[1]), float(args.voxel_spacing_um[2]))
    sx_um, sy_um = spacing[0], spacing[1]

    pairs, fuse_stats = fuse_with_groups(
        raw_use,
        volume,
        fuse_mode=str(args.fuse_mode),
        fuse_max_dz=int(args.fuse_max_dz),
        fuse_max_dxy_px=float(args.fuse_max_dxy_px),
        iou_min=float(args.iou_min),
        require_color=not bool(args.no_color_match),
        color_feature=str(args.color_feature),
        color_percentiles=tuple(float(x) for x in args.color_percentiles),
        color_dot_min=float(args.color_dot_min),
        kde_bin_count_min=int(args.kde_bin_count_min),
        kde_bandwidth_bins=float(args.kde_bandwidth_bins),
        voxel_spacing_um=spacing,
        depth_sanity_ratio_cap=float(args.depth_sanity_ratio_cap),
        no_depth_sanity=bool(args.no_depth_sanity),
        log=log,
    )

    check_lw2 = bool(args.check_lw2)
    min_lw2 = args.min_lw2_um
    max_lw2 = args.max_lw2_um

    l_vals = np.asarray(
        [envelope_lw_um(fb, sx_um, sy_um)[0] for fb, _ in pairs], dtype=np.float64
    )
    w_vals = np.asarray(
        [envelope_lw_um(fb, sx_um, sy_um)[1] for fb, _ in pairs], dtype=np.float64
    )

    if str(args.filter_mode) == "percentile":
        min_l_um, max_l_um, min_w_um, max_w_um, mode_meta = lw_percentile_limits(
            l_vals, w_vals, p_lo=float(args.lw_p_lo), p_hi=float(args.lw_p_hi)
        )
        if check_lw2 and min_lw2 is None and max_lw2 is None:
            min_lw2 = min_l_um * min_w_um
            max_lw2 = max_l_um * max_w_um
    else:
        min_l_um = float(args.min_l_um)
        max_l_um = float(args.max_l_um)
        min_w_um = float(args.min_w_um)
        max_w_um = float(args.max_w_um)
        mode_meta = {
            "filter_mode": "fixed",
            "min_l_um": min_l_um,
            "max_l_um": max_l_um,
            "min_w_um": min_w_um,
            "max_w_um": max_w_um,
        }
        if check_lw2 and min_lw2 is None and max_lw2 is None:
            min_lw2 = min_l_um * min_w_um
            max_lw2 = max_l_um * max_w_um

    kept_pairs: list[tuple[FusedMergeBox, list[int]]] = []
    rejected: list[dict[str, Any]] = []
    kept_cluster_ids: set[int] = set()

    for cluster_id, (fb, members) in enumerate(pairs, start=1):
        l_um, w_um, lw2_um = envelope_lw_um(fb, sx_um, sy_um)
        ok, reason = lw_passes(
            l_um,
            w_um,
            lw2_um,
            min_l_um=min_l_um,
            max_l_um=max_l_um,
            min_w_um=min_w_um,
            max_w_um=max_w_um,
            check_lw2=check_lw2,
            min_lw2_um=min_lw2,
            max_lw2_um=max_lw2,
        )
        rec = fused_record(fb, members, l_um, w_um, lw2_um)
        rec["cluster_id"] = int(cluster_id)
        if ok:
            kept_pairs.append((fb, members))
            kept_cluster_ids.add(int(cluster_id))
        else:
            rec["reject_reason"] = reason
            rejected.append(rec)

    keep_idx: set[int] = set()
    for _, members in kept_pairs:
        for ui in members:
            if 0 <= int(ui) < len(use_to_flat):
                keep_idx.add(int(use_to_flat[int(ui)]))

    filtered_summary, n_slice_before, n_slice_after = filter_summary_by_members_fast(
        summary, raw_boxes, keep_idx
    )

    n_fused_before = len(pairs)
    n_fused_after = len(kept_pairs)
    filter_meta = {
        "filter_script": "filter_fused_neurons_lw_um.py",
        "fuse_mode": str(args.fuse_mode),
        "voxel_spacing_um": list(spacing),
        "check_lw2": check_lw2,
        "min_lw2_um": float(min_lw2) if min_lw2 is not None else None,
        "max_lw2_um": float(max_lw2) if max_lw2 is not None else None,
        "n_fused_before": int(n_fused_before),
        "n_fused_after": int(n_fused_after),
        "n_fused_removed": int(n_fused_before - n_fused_after),
        "n_slice_boxes_before": int(n_slice_before),
        "n_slice_boxes_after": int(n_slice_after),
        "n_slice_boxes_removed": int(n_slice_before - n_slice_after),
        "fuse_stats": fuse_stats,
        **mode_meta,
    }
    filtered_summary["fused_lw_um_filter"] = filter_meta

    args.out_summary.parent.mkdir(parents=True, exist_ok=True)
    args.out_summary.write_text(json.dumps(filtered_summary, indent=2), encoding="utf-8")
    log.info("filtered summary → %s", args.out_summary.resolve())
    log.info(
        "L/W filter [%s]: L∈[%.2f,%.2f] W∈[%.2f,%.2f] µm | fused %d→%d | slice boxes %d→%d",
        str(args.filter_mode),
        min_l_um,
        max_l_um,
        min_w_um,
        max_w_um,
        n_fused_before,
        n_fused_after,
        n_slice_before,
        n_slice_after,
    )

    if args.out_fused_json:
        payload = {
            "summary": str(args.summary.resolve()),
            "lw_um_filter": filter_meta,
            "kept": [
                fused_record(fb, members, *envelope_lw_um(fb, sx_um, sy_um))
                for fb, members in kept_pairs
            ],
            "rejected": rejected,
        }
        args.out_fused_json.parent.mkdir(parents=True, exist_ok=True)
        args.out_fused_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        log.info("fused records → %s", args.out_fused_json.resolve())

    stats: dict[str, Any] = {
        "lw_um_filter": filter_meta,
        "L_um_percentiles": {
            str(p): float(np.percentile(l_vals, p)) if l_vals.size else None
            for p in (1, 5, 25, 50, 75, 95, 99)
        },
        "W_um_percentiles": {
            str(p): float(np.percentile(w_vals, p)) if w_vals.size else None
            for p in (1, 5, 25, 50, 75, 95, 99)
        },
    }
    if args.stats_json:
        args.stats_json.parent.mkdir(parents=True, exist_ok=True)
        args.stats_json.write_text(json.dumps(stats, indent=2), encoding="utf-8")
        log.info("stats → %s", args.stats_json.resolve())

    if args.hist_png:
        title_band = (
            f"Fused L/W n={len(pairs)} | percentile p{args.lw_p_lo:.0f}-p{args.lw_p_hi:.0f}"
            if str(args.filter_mode) == "percentile"
            else f"Fused L/W n={len(pairs)} | fixed [{min_l_um:.1f},{max_l_um:.1f}] µm"
        )
        save_lw_histogram(
            l_vals,
            w_vals,
            args.hist_png,
            min_l=float(min_l_um),
            max_l=float(max_l_um),
            min_w=float(min_w_um),
            max_w=float(max_w_um),
            title=title_band,
        )
        log.info("histogram → %s", args.hist_png.resolve())

    if args.mat_in is not None:
        mat_out = args.mat_out or args.mat_in.with_name(args.mat_in.stem + "_lw_filtered.mat")
        filter_mat_rows(args.mat_in, mat_out, kept_cluster_ids, log)


if __name__ == "__main__":
    main()
