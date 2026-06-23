#!/usr/bin/env python3
"""
Explore 3D fusion: IoU overlap + RGB appearance (percentiles or KDE peaks) across slices.

- Adjacent-layer candidates: |Δz| ≤ fuse_max_dz (default 1 → neighbor slices).
- Link if IoU(xyxy projected to same plane) ≥ --iou-min and (optional) normalized dot product
  similarity on per-box feature vectors ≥ --color-dot-min.

Post-check (optional): drop fused clusters whose 3D axis-alignedbbox is too elongated in µm:

  z_phys <= depth_ratio_cap * max(x_phys, y_phys)

with x_phys,y_phys,z_phys = voxel_extent(axis) × spacing µm/voxel.

Reuses mip drawing / NeuroPAL export helpers from mip_centroids_from_predictions_summary.py.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import logging
import math
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

import cv2
import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent


def _load_mip() -> Any:
    p = SCRIPT_DIR / "mip_centroids_from_predictions_summary.py"
    spec = importlib.util.spec_from_file_location("mip_centroids_base", str(p))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mip = _load_mip()
_DSU: Any = mip._DSU  # disjoint-set + union-find (same linkage as Euclidean fuse script)


def _np_str(val: str) -> Any:
    return np.array(np.str_(val))


@dataclass
class Detection:
    z: int
    x1: float
    y1: float
    x2: float
    y2: float
    conf: float


def bbox_iou(a: Detection, b: Detection) -> float:
    xa1, ya1, xa2, ya2 = a.x1, a.y1, a.x2, a.y2
    xb1, yb1, xb2, yb2 = b.x1, b.y1, b.x2, b.y2
    xa1_, xa2_ = min(xa1, xa2), max(xa1, xa2)
    ya1_, ya2_ = min(ya1, ya2), max(ya1, ya2)
    xb1_, xb2_ = min(xb1, xb2), max(xb1, xb2)
    yb1_, yb2_ = min(yb1, yb2), max(yb1, yb2)
    ix1 = max(xa1_, xb1_)
    iy1 = max(ya1_, yb1_)
    ix2 = min(xa2_, xb2_)
    iy2 = min(ya2_, yb2_)
    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    inter = iw * ih
    aw = max(0.0, xa2_ - xa1_) * max(0.0, ya2_ - ya1_)
    bw = max(0.0, xb2_ - xb1_) * max(0.0, yb2_ - yb1_)
    denom = aw + bw - inter + 1e-9
    return float(inter / denom)


def crop_box_rgb(
    vol: np.ndarray,
    zi: int,
    x1: float,
    y1: float,
    x2: float,
    y2: float,
) -> np.ndarray:
    """ROI on slice zi: vol is (ny,nx,Z,C); OpenCV-style x=columns (axis 1), y=rows (axis 0)."""
    ny, nx = int(vol.shape[0]), int(vol.shape[1])
    xi1 = int(np.clip(round(min(x1, x2)), 0, nx - 1))
    xi2 = int(np.clip(round(max(x1, x2)), 0, nx - 1))
    yi1 = int(np.clip(round(min(y1, y2)), 0, ny - 1))
    yi2 = int(np.clip(round(max(y1, y2)), 0, ny - 1))
    if yi2 < yi1 or xi2 < xi1 or zi < 0 or zi >= vol.shape[2]:
        return np.zeros((0, 3), dtype=np.float32)
    patch = vol[yi1 : yi2 + 1, xi1 : xi2 + 1, zi, :].astype(np.float32, copy=False)
    nc = patch.shape[-1]
    if nc == 0:
        return patch.reshape(-1, 0)
    if nc >= 3:
        return patch[..., :3].reshape(-1, 3)
    q = patch[..., :1].reshape(-1, 1)
    return np.concatenate([q, q, q], axis=1)


def feature_percentiles(
    patch_pixels: np.ndarray,
    pct: Sequence[float],
) -> np.ndarray:
    """Flatten RGB samples → stacked per-channel quantiles."""
    feat: list[float] = []
    for c in range(3):
        col = patch_pixels[:, c] if patch_pixels.shape[1] > c else patch_pixels[:, 0]
        if col.size == 0:
            feat.extend([0.0 for _ in pct])
            continue
        for p in pct:
            feat.append(float(np.percentile(col, p)))
    return np.asarray(feat, dtype=np.float64)


def kde_peak_per_channel(patch_pixels: np.ndarray, nbins_floor: int, bandwidth_bins: float) -> np.ndarray:
    """1D KDE argmax peak per RGB channel."""
    try:
        from scipy.ndimage import gaussian_filter1d  # type: ignore[import-untyped]
    except ImportError as e:
        raise RuntimeError(
            "KDE color mode requires scipy (`pip install scipy`) for scipy.ndimage.gaussian_filter1d."
        ) from e
    feats: list[float] = []
    for c in range(3):
        col = patch_pixels[:, min(c, patch_pixels.shape[1] - 1)] if patch_pixels.size else np.zeros((0,))
        if col.size < 4:
            feats.append(float(np.median(col)) if col.size else 0.0)
            continue
        n_bins = max(nbins_floor, int(round(math.sqrt(float(col.size)))))
        vmin, vmax = float(col.min()), float(col.max())
        if vmax <= vmin + 1e-9:
            feats.append(vmin)
            continue
        h, edges = np.histogram(col, bins=n_bins, range=(vmin, vmax))
        centers = (edges[:-1] + edges[1:]) / 2.0
        sm = gaussian_filter1d(h.astype(np.float64), sigma=max(0.01, bandwidth_bins))
        feats.append(float(centers[int(np.argmax(sm))]))
    return np.asarray(feats, dtype=np.float64)


def dot_similarity_normalized(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, dtype=np.float64).ravel()
    b = np.asarray(b, dtype=np.float64).ravel()
    if a.size != b.size or a.size == 0:
        return 0.0
    na = float(np.linalg.norm(a))
    nb = float(np.linalg.norm(b))
    if na < 1e-12 or nb < 1e-12:
        return 0.0
    return float(np.dot(a / na, b / nb))


def depth_sanity_ok(
    dets: Sequence[Detection],
    sx_um: float,
    sy_um: float,
    sz_um: float,
    ratio_cap: float,
    log: logging.Logger | None = None,
) -> bool:
    if not dets:
        return False
    zmin = min(d.z for d in dets)
    zmax = max(d.z for d in dets)
    xmin = min(min(d.x1, d.x2) for d in dets)
    xmax = max(max(d.x1, d.x2) for d in dets)
    ymin = min(min(d.y1, d.y2) for d in dets)
    ymax = max(max(d.y1, d.y2) for d in dets)
    x_ext = xmax - xmin + 1e-9
    y_ext = ymax - ymin + 1e-9
    z_ext = float(zmax - zmin + 1)
    x_phys = x_ext * sx_um
    y_phys = y_ext * sy_um
    z_phys = z_ext * sz_um
    cap = ratio_cap * max(x_phys, y_phys)
    ok = bool(z_phys <= cap + 1e-12)
    if log and log.isEnabledFor(logging.DEBUG):
        log.debug(
            "depth sanity: z_phys=%.4g xm=%.4g ym=%.4g cap(%.4g*max(xy))=%.4g ok=%s",
            z_phys,
            x_phys,
            y_phys,
            ratio_cap,
            cap,
            ok,
        )
    return ok


def fuse_components(
    detections: list[Detection],
    feats: list[np.ndarray] | None,
    *,
    max_dz: int,
    iou_min: float,
    require_color: bool,
    color_dot_min: float,
    log: logging.Logger | None = None,
) -> tuple[list[list[int]], dict[str, Any]]:
    n = len(detections)
    dsu = _DSU(n)
    n_edges = 0
    for i in range(n):
        zi, Ai = detections[i].z, detections[i]
        for j in range(i + 1, n):
            zj = detections[j].z
            if zi == zj:
                continue
            if abs(zi - zj) > max_dz:
                continue
            if bbox_iou(Ai, detections[j]) < iou_min - 1e-12:
                continue
            if require_color and feats is not None:
                sim = dot_similarity_normalized(feats[i], feats[j])
                if sim < color_dot_min - 1e-12:
                    continue
            dsu.union(i, j)
            n_edges += 1
    grp: dict[int, list[int]] = {}
    for i in range(n):
        r = dsu.find(i)
        grp.setdefault(r, []).append(i)
    members = sorted(grp.values(), key=lambda ms: ms[0])
    stats = {
        "num_raw": n,
        "num_components_before_sanity": len(members),
        "num_pairwise_edges_accepted": n_edges,
    }
    if log:
        log.info(
            "IoU/color fuse: %d dets · %d components · %d accepted edges · max_dz=%d IoU≥%.4g%s",
            n,
            len(members),
            n_edges,
            max_dz,
            float(iou_min),
            ""
            if not require_color
            else f" · color cosine≥{color_dot_min:.4g}",
        )
    return members, stats


def component_to_centroid(indices: Iterable[int], dets: list[Detection]) -> list[float]:
    """Return [zf, xf, yf, conf_max, n_merged] weighted by detection conf."""
    idxs = list(indices)
    zs = []
    xs = []
    ys = []
    confs = []
    for i in idxs:
        d = dets[i]
        cx = float(d.x1 + d.x2) / 2.0
        cy = float(d.y1 + d.y2) / 2.0
        zs.append(float(d.z))
        xs.append(cx)
        ys.append(cy)
        confs.append(float(d.conf))
    cf = np.array(confs, dtype=np.float64)
    ws = cf / cf.sum() if cf.sum() > 1e-12 else np.ones_like(cf) / cf.size
    zf = float(np.dot(np.asarray(zs, dtype=np.float64), ws))
    xf = float(np.dot(np.asarray(xs, dtype=np.float64), ws))
    yf = float(np.dot(np.asarray(ys, dtype=np.float64), ws))
    return [zf, xf, yf, float(np.max(cf)), float(len(idxs))]


def parse_detections(summary: Mapping[str, Any]) -> list[Detection]:
    out: list[Detection] = []
    for block in summary.get("slices") or []:
        zi = int(block["z"])
        for rec in block.get("boxes_xyxy_conf", []):
            if len(rec) < 5:
                continue
            x1, y1, x2, y2, conf = rec[:5]
            out.append(
                Detection(
                    zi,
                    float(x1),
                    float(y1),
                    float(x2),
                    float(y2),
                    float(conf),
                )
            )
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="IoU + RGB centroid fusion explorer (MIP PNG + MATLAB exports)")
    ap.add_argument("--summary", type=Path, required=True)
    ap.add_argument("--volume", type=Path, default=None)
    ap.add_argument("--out_png", type=Path, required=True)
    ap.add_argument("--stretch_mip", action="store_true")
    ap.add_argument("--p_lo", type=float, default=2.0)
    ap.add_argument("--p_hi", type=float, default=98.0)
    ap.add_argument("--mip_mode", choices=("rgb", "gray"), default="rgb")
    ap.add_argument("--device", choices=("cpu", "gpu"), default="cpu")
    ap.add_argument("--fuse-max-dz", type=int, default=1)
    ap.add_argument("--iou-min", type=float, default=0.50)
    ap.add_argument(
        "--no-color-match",
        action="store_true",
        help="IoU + dz only (skip RGB feature gate; faster, no voxel crops for appearance).",
    )
    ap.add_argument("--color-feature", choices=("percentiles", "kde"), default="percentiles")
    ap.add_argument(
        "--color-percentiles",
        type=float,
        nargs="+",
        default=[50.0, 75.0, 90.0],
    )
    ap.add_argument("--color-dot-min", type=float, default=0.8)
    ap.add_argument("--kde-bin-count-min", type=int, default=8)
    ap.add_argument("--kde-bandwidth-bins", type=float, default=3.0)
    ap.add_argument("--crop-z-to-summary", action="store_true")
    ap.add_argument("--depth-sanity-ratio-cap", type=float, default=1.5)
    ap.add_argument(
        "--voxel-spacing-um",
        type=float,
        nargs=3,
        metavar=("SX", "SY", "SZ"),
        default=[0.4, 0.4, 1.5],
    )
    ap.add_argument("--no-depth-sanity", action="store_true")
    ap.add_argument("--radius", type=int, default=2)
    ap.add_argument("--line_width_centroid", type=int, default=-1)
    ap.add_argument("--centroid_rgb", type=int, nargs=3, default=[255, 0, 0])
    ap.add_argument("--colour_centroids_by_z", action="store_true")
    ap.add_argument(
        "--no-centroids",
        action="store_true",
        help="Build identical MIP pipeline but skip drawing centroid markers.",
    )
    ap.add_argument("--label-radius-xy", type=int, default=2)
    ap.add_argument("--label-radius-z", type=int, default=1)
    ap.add_argument("--export_csv", type=Path, default=None)
    ap.add_argument("--export-mat", type=Path, default=None)
    ap.add_argument("--export-neuropal-gui-mat", type=Path, default=None)
    ap.add_argument("--export-neuropal-id-mat", type=Path, default=None)
    ap.add_argument("--neuropal-scale-um", type=float, nargs=3, default=[1.0, 1.0, 1.0])
    ap.add_argument("--neuropal-gamma", type=float, default=0.8)
    ap.add_argument("--neuropal-volume-version", type=float, default=2.0)
    ap.add_argument("--worm-body", type=str, default="Head")
    ap.add_argument("--worm-age", type=str, default="Adult")
    ap.add_argument("--worm-sex", type=str, default="XX")
    ap.add_argument("--worm-strain", type=str, default="")
    ap.add_argument("--worm-notes", type=str, default="")
    ap.add_argument("--neuropal-keep-numpy-axes", action="store_true")
    ap.add_argument("--timing-json", type=Path, default=None)
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    log = logging.getLogger("iou_color_fuse")
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s [iou_color_fuse] %(message)s",
    )

    t_wall0 = time.perf_counter()
    timings: dict[str, Any] = {}

    sj = json.loads(Path(args.summary).read_text(encoding="utf-8"))
    vol_path = Path(args.volume) if args.volume else Path(str(sj["volume"]))
    dets = parse_detections(sj)
    if not dets:
        log.warning("no detections in summary")
        return

    t0 = time.perf_counter()
    volume_full = mip.load_volume(vol_path)
    timings["seconds_load_numpy_volume"] = round(time.perf_counter() - t0, 6)
    vf = tuple(int(volume_full.shape[i]) for i in range(3))

    crop_z_offset = 0
    z_win = mip._summary_z_window(sj.get("slices") or [])
    if args.crop_z_to_summary and z_win is not None:
        z0, z1 = z_win
        crop_z_offset = int(z0)
        volume_full = volume_full[:, :, z0 : z1 + 1, :].copy()

    volume = volume_full
    require_color_match = not bool(args.no_color_match)

    centroid_rgb = tuple(int(np.clip(c, 0, 255)) for c in args.centroid_rgb)
    centroid_bgr = (centroid_rgb[2], centroid_rgb[1], centroid_rgb[0])

    t0 = time.perf_counter()
    n_ch = int(volume.shape[-1])
    mip_mode = args.mip_mode
    if mip_mode == "rgb" and n_ch < 3:
        mip_mode = "gray"
    if mip_mode == "rgb":
        if args.device == "gpu":
            canvas = mip.mip_rgb_bgr_torch_cuda(
                volume,
                percentile_stretch=args.stretch_mip,
                p_lo=args.p_lo,
                p_hi=args.p_hi,
                log=log,
            )
        else:
            canvas = mip.mip_rgb_bgr(
                volume,
                percentile_stretch=args.stretch_mip,
                p_lo=args.p_lo,
                p_hi=args.p_hi,
                log=log,
            )
    else:
        if args.device == "gpu":
            mip_u8, _ = mip.mip_xy_gray_torch_cuda(
                volume,
                percentile_stretch=args.stretch_mip,
                p_lo=args.p_lo,
                p_hi=args.p_hi,
                log=log,
            )
        else:
            mip_u8, _ = mip.mip_xy_gray(
                volume,
                percentile_stretch=args.stretch_mip,
                p_lo=args.p_lo,
                p_hi=args.p_hi,
                log=log,
            )
        canvas = cv2.cvtColor(mip_u8, cv2.COLOR_GRAY2BGR)
    timings["seconds_build_z_mip"] = round(time.perf_counter() - t0, 6)
    h_m, w_m = int(canvas.shape[0]), int(canvas.shape[1])
    z_max_coord = max(0, vf[2] - 1)

    feats: list[np.ndarray] | None = None
    t_feat0 = time.perf_counter()
    if require_color_match:
        feats = []
        for d in dets:
            zi_loc = int(d.z - crop_z_offset)
            px = crop_box_rgb(volume, zi_loc, d.x1, d.y1, d.x2, d.y2)
            if px.size == 0:
                feats.append(np.zeros((9 if args.color_feature == "percentiles" else 3), dtype=np.float64))
                continue
            if args.color_feature == "percentiles":
                v = feature_percentiles(px, args.color_percentiles)
                assert v.shape[0] == 9
                feats.append(v)
            else:
                v = kde_peak_per_channel(
                    px,
                    nbins_floor=int(args.kde_bin_count_min),
                    bandwidth_bins=float(args.kde_bandwidth_bins),
                )
                feats.append(v)
        timings["seconds_color_features"] = round(time.perf_counter() - t_feat0, 6)
        log.info("built color features (%s) for %d boxes in %.4fs", args.color_feature, len(dets), timings["seconds_color_features"])
    else:
        feats = None
        timings["seconds_color_features"] = 0.0

    t_fuse = time.perf_counter()
    groups, fused_stats = fuse_components(
        dets,
        feats,
        max_dz=int(args.fuse_max_dz),
        iou_min=float(args.iou_min),
        require_color=bool(require_color_match),
        color_dot_min=float(args.color_dot_min),
        log=log,
    )
    timings.update({f"fuse_{k}": v for k, v in fused_stats.items()})

    sx_um, sy_um, sz_um = (float(args.voxel_spacing_um[i]) for i in range(3))
    draw_rows_raw: list[list[float]] = []
    n_kept = 0
    n_reject = 0
    t_depth = time.perf_counter()
    for g in groups:
        sub = [dets[i] for i in g]
        if not args.no_depth_sanity and not depth_sanity_ok(
            sub, sx_um, sy_um, sz_um, float(args.depth_sanity_ratio_cap), log=log if args.verbose else None
        ):
            n_reject += 1
            continue
        draw_rows_raw.append(component_to_centroid(g, dets))
        n_kept += 1
    timings["seconds_depth_sanity"] = round(time.perf_counter() - t_depth, 6)
    timings["depth_sanity_rejected_components"] = n_reject
    timings["fuse_components_after_depth_sanity"] = n_kept
    timings["seconds_iou_color_fuse_core"] = round(time.perf_counter() - t_fuse - timings["seconds_depth_sanity"], 6)

    draw_rows_raw.sort(key=lambda r: (r[0], r[1], r[2]))
    timings["num_raw_boxes"] = len(dets)

    def _draw_one(cx: float, cy: float, z_col: float, clr: tuple[int, int, int], rad: int) -> None:
        col_raw = int(round(cx))
        row_raw = int(round(cy))
        col = min(max(col_raw, 0), w_m - 1)
        row = min(max(row_raw, 0), h_m - 1)
        zi = int(round(z_col))
        if args.colour_centroids_by_z:
            clr = mip.z_to_bgr(zi, z_max_coord)
        cv2.circle(
            canvas,
            (col, row),
            rad,
            clr,
            thickness=args.line_width_centroid,
            lineType=cv2.LINE_AA,
        )

    if args.no_centroids:
        log.info(
            "--- Draw MIP skipped (--no-centroids) | fused=%d components retained for exports ---",
            len(draw_rows_raw),
        )
        timings["seconds_draw_centroids_opencv"] = 0.0
    else:
        log.info(
            "--- Draw MIP (fused only) | fused=%d (after depth sanity) | markers red=%s ---",
            len(draw_rows_raw),
            centroid_rgb,
        )
        t_draw = time.perf_counter()
        for zf, cx, cy, _cf, _nm in draw_rows_raw:
            _draw_one(cx, cy, zf, centroid_bgr, max(2, int(args.radius)))
        timings["seconds_draw_centroids_opencv"] = round(time.perf_counter() - t_draw, 6)

    args.out_png.parent.mkdir(parents=True, exist_ok=True)
    t_png = time.perf_counter()
    cv2.imwrite(str(args.out_png), canvas)
    timings["seconds_cv2_imwrite_png"] = round(time.perf_counter() - t_png, 6)

    if args.export_csv is not None:
        lines = ["z,cx,cy,conf_max,x_pixel,y_pixel,n_merged"]
        for zf, cx, cy, cf, nm in draw_rows_raw:
            col = min(max(int(round(cx)), 0), w_m - 1)
            row = min(max(int(round(cy)), 0), h_m - 1)
            lines.append(f"{zf:.6f},{cx:.6f},{cy:.6f},{cf:.6f},{col},{row},{int(nm)}")
        args.export_csv.write_text("\n".join(lines) + "\n", encoding="utf-8")

    timings["fuse_max_dz"] = int(args.fuse_max_dz)
    timings["iou_min"] = float(args.iou_min)
    timings["require_color_match"] = bool(require_color_match)
    timings["color_feature"] = args.color_feature
    timings["color_dot_min"] = float(args.color_dot_min)
    timings["depth_sanity_ratio_cap"] = float(args.depth_sanity_ratio_cap)
    timings["depth_sanity_enabled"] = not bool(args.no_depth_sanity)
    timings["voxel_spacing_um"] = [float(args.voxel_spacing_um[i]) for i in range(3)]

    extra_mat_note: dict[str, Any] = {
        "fusion_export_note": _np_str("IoU/color fusion from mip_centroids_iou_color_fuse.py"),
        "iou_min": np.asarray([[float(args.iou_min)]], dtype=np.float64),
        "fuse_max_dz_cli": np.asarray([[int(args.fuse_max_dz)]], dtype=np.int64),
        "color_dot_threshold": np.asarray([[float(args.color_dot_min)]], dtype=np.float64),
        "require_color": np.asarray([[int(bool(require_color_match))]], dtype=np.uint8),
        "depth_sanity_ratio_cap": np.asarray([[float(args.depth_sanity_ratio_cap)]], dtype=np.float64),
        "voxel_spacing_um_row": np.asarray(args.voxel_spacing_um, dtype=np.float64).reshape(1, 3),
        "sanity_components_rejected_count": np.asarray([[int(n_reject)]], dtype=np.int64),
    }

    if args.export_mat is not None:
        label_vol = mip.paint_label_volume_uint16(
            (int(volume.shape[0]), int(volume.shape[1]), int(volume.shape[2])),
            draw_rows_raw,
            crop_z_offset=crop_z_offset,
            radius_xy=max(0, int(args.label_radius_xy)),
            radius_z=max(0, int(args.label_radius_z)),
            log=log,
        )
        mip.export_centroids_mat(
            args.export_mat,
            label_vol=label_vol,
            draw_rows=draw_rows_raw,
            volume_full_shape_pre_crop=vf,
            volume_shape_numpy=(
                int(volume.shape[0]),
                int(volume.shape[1]),
                int(volume.shape[2]),
            ),
            crop_z_offset=crop_z_offset,
            summary_path_str=str(Path(args.summary).resolve()),
            volume_path_str=str(vol_path.resolve()),
            fuse_3d=True,
            fuse_max_dz=int(args.fuse_max_dz),
            fuse_max_dxy_px=-1.0,
            label_radius_xy=int(args.label_radius_xy),
            label_radius_z=int(args.label_radius_z),
            extra_savemat_variables=extra_mat_note,
            pipeline_note="mip_centroids_iou_color_fuse.py",
        )

    mp_extra = {
        "fusion_backend": "iou_color_optional_depth_sanity",
        "iou_min": float(args.iou_min),
        "color_cosine_gate": float(args.color_dot_min if require_color_match else -1.0),
        "fuse_max_dz": int(args.fuse_max_dz),
        "sanity_components_rejected": int(n_reject),
    }

    scale_um = tuple(float(args.neuropal_scale_um[i]) for i in range(3))
    neuropal_transpose = not bool(args.neuropal_keep_numpy_axes)

    if args.export_neuropal_gui_mat is not None:
        mip.export_neuropal_gui_mat_bundle(
            args.export_neuropal_gui_mat,
            volume=volume,
            draw_rows=draw_rows_raw,
            crop_z_offset=crop_z_offset,
            summary_path_str=str(Path(args.summary).resolve()),
            volume_path_str=str(vol_path.resolve()),
            fuse_3d=True,
            fuse_max_dz=int(args.fuse_max_dz),
            fuse_max_dxy_px=-1.0,
            scale_um=scale_um,
            neuropal_np_version=float(args.neuropal_volume_version),
            neuropal_gamma=float(args.neuropal_gamma),
            worm_body=args.worm_body,
            worm_age=args.worm_age,
            worm_sex=args.worm_sex,
            worm_strain=args.worm_strain,
            worm_notes=args.worm_notes,
            transpose_xy_for_neuropal=neuropal_transpose,
            log=log,
            mp_params_extra=mp_extra,
        )

    skip_duplicate_id = False
    id_side = mip.neuropal_id_mat_path_for_volume_mat(args.export_neuropal_gui_mat) if args.export_neuropal_gui_mat else None
    if args.export_neuropal_gui_mat and args.export_neuropal_id_mat and id_side:
        if Path(args.export_neuropal_id_mat).resolve() == id_side.resolve():
            skip_duplicate_id = True

    if args.export_neuropal_id_mat is not None and not skip_duplicate_id:
        mip.export_neuropal_detection_id_mat(
            args.export_neuropal_id_mat,
            draw_rows=draw_rows_raw,
            volume_shape_row_col_z=(
                int(volume.shape[0]),
                int(volume.shape[1]),
                int(volume.shape[2]),
            ),
            crop_z_offset=crop_z_offset,
            summary_path_str=str(Path(args.summary).resolve()),
            volume_path_str=str(vol_path.resolve()),
            fuse_3d=True,
            fuse_max_dz=int(args.fuse_max_dz),
            fuse_max_dxy_px=-1.0,
            volume=volume,
            scale_um=scale_um,
            transpose_xy_for_neuropal=neuropal_transpose,
            log=log,
        )

    wall = time.perf_counter() - t_wall0
    timings["seconds_wall_total_script"] = round(wall, 6)
    tpath = args.timing_json
    if tpath is None:
        tpath = args.out_png.parent / f"{args.out_png.stem}_iou_color_fuse_timing.json"
    tpath.parent.mkdir(parents=True, exist_ok=True)
    tpath.write_text(json.dumps(timings, indent=2), encoding="utf-8")

    summary_line = (
        f"[ok] iou/color fuse · raw_boxes={len(dets)} → clusters_kept={len(draw_rows_raw)} "
        f"(depth_reject_components={n_reject}) · wall {wall:.4f}s · {args.out_png}"
    )
    log.info(summary_line)
    print(summary_line)


if __name__ == "__main__":
    main()
