#!/usr/bin/env python3
"""Bridge NeuroPAL_ID MATLAB volumes to Swetha YOLO centroid inference."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/neuropal_matplotlib")
os.environ.setdefault("YOLO_CONFIG_DIR", "/private/tmp/neuropal_ultralytics")
os.environ.setdefault("XDG_CONFIG_HOME", "/private/tmp/neuropal_config")

import numpy as np
from scipy.io import loadmat


def progress(message: str) -> None:
    print(f"NEUROPAL_PROGRESS: {message}", flush=True)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--request", required=True)
    p.add_argument("--response", required=True)
    return p.parse_args()


def run(cmd: list[str]) -> str:
    progress("Running: " + " ".join(cmd[:3]) + " ...")
    env = os.environ.copy()
    env.setdefault("MPLCONFIGDIR", "/private/tmp/neuropal_matplotlib")
    env.setdefault("YOLO_CONFIG_DIR", "/private/tmp/neuropal_ultralytics")
    env.setdefault("XDG_CONFIG_HOME", "/private/tmp/neuropal_config")
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    if proc.returncode:
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stdout}")
    return proc.stdout


def filter_yolo_summary(summary_path: Path, *, score_min: float, box_min_px: float, box_max_px: float) -> tuple[int, int]:
    box_min_px = max(0.0, float(box_min_px))
    box_max_px = max(box_min_px, float(box_max_px))
    score_min = min(max(float(score_min), 0.0), 1.0)
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    raw_count = 0
    kept_count = 0
    for slice_rec in summary.get("slices", []):
        filtered = []
        for box in slice_rec.get("boxes_xyxy_conf", []):
            if len(box) < 5:
                continue
            x1, y1, x2, y2, score = [float(v) for v in box[:5]]
            raw_count += 1
            box_side_px = max(abs(x2 - x1), abs(y2 - y1))
            if score < score_min:
                continue
            if box_side_px < box_min_px:
                continue
            if box_side_px > box_max_px:
                continue
            filtered.append(box)
        slice_rec["boxes_xyxy_conf"] = filtered
        slice_rec["n_predictions"] = len(filtered)
        kept_count += len(filtered)
    summary["total_predictions_raw"] = int(raw_count)
    summary["total_predictions"] = int(kept_count)
    summary["post_filter"] = {
        "score_min": float(score_min),
        "box_min_px": float(box_min_px),
        "box_max_px": float(box_max_px),
        "box_metric": "max(width_px, height_px)",
    }
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return raw_count, kept_count


def main() -> None:
    args = parse_args()
    req = json.loads(Path(args.request).read_text(encoding="utf-8"))
    out_dir = Path(req["output_dir"]).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    progress("Loading MATLAB volume...")
    mat = loadmat(req["volume_mat"], squeeze_me=False)
    volume = np.asarray(mat["volume"])
    if volume.ndim == 3:
        volume = volume[..., None]
    if volume.ndim != 4:
        raise ValueError(f"Expected 4D volume, got {volume.shape}")

    volume_npy = out_dir / "neuropal_yolo_volume.npy"
    try:
        np.save(volume_npy, volume)
    except OSError as exc:
        try:
            volume_npy.unlink(missing_ok=True)
        except Exception:
            pass
        raise OSError(
            f"Could not write YOLO temporary volume {volume_npy}. "
            "The output disk is likely full; clear old artifacts or choose a different output directory."
        ) from exc

    infer_script = Path(req["infer_script"]).resolve()
    fuse_script = Path(req["fuse_script"]).resolve()
    weights = Path(req["weights"]).resolve()
    summary_dir = out_dir / "yolo_infer"
    fused_png = out_dir / "yolo_fused_mip.png"
    fused_csv = out_dir / "yolo_fused_centroids.csv"

    progress("Running YOLO slice inference...")
    infer_cmd = [
        sys.executable,
        str(infer_script),
        "--volume",
        str(volume_npy),
        "--weights",
        str(weights),
        "--out_dir",
        str(summary_dir),
        "--conf",
        str(req["conf"]),
        "--imgsz",
        str(req["imgsz"]),
        "--line_width",
        str(req["line_width"]),
    ]
    if req.get("device"):
        infer_cmd.extend(["--device", str(req["device"])])
    if req.get("stretch_slices", True):
        infer_cmd.extend(["--stretch_slices", "--p_lo", str(req["p_lo"]), "--p_hi", str(req["p_hi"])])
    run(infer_cmd)

    progress("Fusing YOLO detections across z...")
    summary_path = summary_dir / "predictions_summary.json"
    raw_boxes, kept_boxes = filter_yolo_summary(
        summary_path,
        score_min=float(req["conf"]),
        box_min_px=float(req["box_min_px"]),
        box_max_px=float(req["box_max_px"]),
    )
    progress(f"Filtered YOLO boxes: {kept_boxes}/{raw_boxes} kept.")
    fuse_cmd = [
        sys.executable,
        str(fuse_script),
        "--summary",
        str(summary_path),
        "--volume",
        str(volume_npy),
        "--out_png",
        str(fused_png),
        "--export_csv",
        str(fused_csv),
        "--fuse-max-dz",
        str(req["fuse_max_dz"]),
        "--iou-min",
        str(req["iou_min"]),
        "--color-dot-min",
        str(req["color_dot_min"]),
        "--voxel-spacing-um",
        *[str(x) for x in req["scale_um_xyz"]],
        "--depth-sanity-ratio-cap",
        str(req["depth_sanity_ratio_cap"]),
        "--radius",
        str(req["radius"]),
    ]
    if not req.get("color_match", True):
        fuse_cmd.append("--no-color-match")
    if not req.get("depth_sanity", True):
        fuse_cmd.append("--no-depth-sanity")
    if req.get("stretch_mip", True):
        fuse_cmd.extend(["--stretch_mip", "--p_lo", str(req["p_lo"]), "--p_hi", str(req["p_hi"])])
    run(fuse_cmd)

    rows = []
    if fused_csv.exists():
        with fused_csv.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                z = float(row["z"]) + 1.0
                col = float(row["cx"])
                row_y = float(row["cy"])
                rows.append([row_y, col, z, float(row["conf_max"]), float(row["n_merged"])])

    response = {
        "backend": "yolo",
        "centroids_yxz": rows,
        "num_centroids": len(rows),
        "raw_boxes": raw_boxes,
        "filtered_boxes": kept_boxes,
        "box_min_px": float(req["box_min_px"]),
        "box_max_px": float(req["box_max_px"]),
        "volume_npy": str(volume_npy),
        "summary_path": str(summary_path),
        "fused_csv": str(fused_csv),
        "fused_png": str(fused_png),
        "weights": str(weights),
        "infer_script": str(infer_script),
        "fuse_script": str(fuse_script),
    }
    Path(args.response).write_text(json.dumps(response, indent=2), encoding="utf-8")
    progress(f"YOLO finished: {len(rows)} fused centroids.")


if __name__ == "__main__":
    main()
