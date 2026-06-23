#!/usr/bin/env python3
from __future__ import annotations

import argparse
import cProfile
import json
import logging
import pstats
import sys
import time
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO


CYAN_BGR = (255, 255, 0)
SCALE_BAR_BGR = (255, 255, 255)


def _configure_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s | %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stderr,
        force=True,
    )


def to_uint8_image(img: np.ndarray, *, stretch: bool = False, p_lo: float = 2.0, p_hi: float = 98.0) -> np.ndarray:
    arr = np.asarray(img, dtype=np.float32)
    if arr.ndim == 2:
        arr = np.stack([arr, arr, arr], axis=-1)
    if arr.ndim != 3:
        raise ValueError(f"expected 2D or HWC image, got {arr.shape}")
    if arr.shape[-1] > 3:
        arr = arr[..., :3]
    if arr.shape[-1] == 1:
        arr = np.repeat(arr, 3, axis=-1)

    if stretch:
        out = np.zeros_like(arr, dtype=np.float32)
        for c in range(arr.shape[-1]):
            ch = arr[..., c]
            lo, hi = np.percentile(ch, [p_lo, p_hi])
            if hi <= lo + 1e-6:
                lo, hi = float(ch.min()), float(ch.max()) + 1e-6
            out[..., c] = np.clip((ch - lo) / (hi - lo) * 255.0, 0, 255)
        return out.astype(np.uint8)

    if float(np.nanmax(arr)) <= 1.0:
        arr = arr * 255.0
    return np.clip(arr, 0, 255).astype(np.uint8)


def load_volume(path: Path) -> np.ndarray:
    vol = np.load(path, allow_pickle=True)
    if vol.dtype == object:
        raise ValueError("Expected one dense volume, got an object array of slices/volumes.")
    vol = np.asarray(vol)
    if vol.ndim == 3:
        vol = vol[..., np.newaxis]
    if vol.ndim != 4:
        raise ValueError(f"Expected volume shape (X,Y,Z,C) or (X,Y,Z), got {vol.shape}")
    return vol


def iter_cellpose_style_slices(volume: np.ndarray):
    # Same convention as cellpose/scripts/create_2d_slices.py:
    # clean volume is (X, Y, Z, C), each YOLO plane is volume[:, :, z, :].
    for z_idx in range(volume.shape[2]):
        yield z_idx, volume[:, :, z_idx, :]


def slice_signal_values(
    volume: np.ndarray,
    *,
    percentile: float,
) -> np.ndarray:
    percentile = float(np.clip(percentile, 0.0, 100.0))
    values = []
    for _, plane in iter_cellpose_style_slices(volume):
        arr = np.asarray(plane, dtype=np.float32)
        if arr.size == 0:
            values.append(0.0)
        else:
            values.append(float(np.nanpercentile(arr, percentile)))
    return np.asarray(values, dtype=np.float32)


def draw_predictions(
    image_rgb: np.ndarray,
    boxes_xyxy: np.ndarray,
    confs: np.ndarray,
    *,
    line_width: int,
    show_conf: bool,
) -> np.ndarray:
    canvas = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)
    for box, conf in zip(boxes_xyxy, confs):
        x1, y1, x2, y2 = [int(round(v)) for v in box]
        cv2.rectangle(canvas, (x1, y1), (x2, y2), CYAN_BGR, thickness=line_width)
        if show_conf:
            cv2.putText(
                canvas,
                f"{float(conf):.2f}",
                (x1, max(0, y1 - 4)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.4,
                CYAN_BGR,
                1,
                cv2.LINE_AA,
            )
    return canvas


def draw_scale_bar(
    canvas_bgr: np.ndarray,
    *,
    length_um: float,
    col_um_per_px: float,
) -> None:
    if length_um <= 0 or col_um_per_px <= 0 or canvas_bgr.size == 0:
        return
    h, w = int(canvas_bgr.shape[0]), int(canvas_bgr.shape[1])
    margin = max(10, int(round(min(h, w) * 0.025)))
    thick = max(2, int(round(min(h, w) * 0.006)))
    bar_px = int(round(float(length_um) / float(col_um_per_px)))
    if bar_px < 4:
        return
    bar_px = min(bar_px, max(4, w - 2 * margin))
    x1 = margin
    x2 = min(w - 1, x1 + bar_px)
    y = max(0, h - margin)
    if x2 <= x1:
        return
    cv2.line(canvas_bgr, (x1, y), (x2, y), (0, 0, 0), thick + 4, cv2.LINE_AA)
    cv2.line(canvas_bgr, (x1, y), (x2, y), SCALE_BAR_BGR, thick, cv2.LINE_AA)
    text = f"{float(length_um):g} um"
    font = cv2.FONT_HERSHEY_SIMPLEX
    fs = float(np.clip(min(h, w) / 900.0, 0.42, 0.72))
    tw, th = cv2.getTextSize(text, font, fs, max(1, thick // 2 + 1))[0]
    tx = int(np.clip(x1 + (bar_px - tw) // 2, 0, max(0, w - tw - 1)))
    ty = int(np.clip(y - max(6, thick + 4), th + 2, max(th + 2, h - 1)))
    cv2.putText(canvas_bgr, text, (tx, ty), font, fs, (0, 0, 0), thick + 2, cv2.LINE_AA)
    cv2.putText(canvas_bgr, text, (tx, ty), font, fs, SCALE_BAR_BGR, max(1, thick // 2 + 1), cv2.LINE_AA)


def _run_inference(args: argparse.Namespace) -> None:
    log = logging.getLogger("infer_volume_slices_yolo")

    log.info("Volume path: %s", args.volume.resolve())
    log.info("Weights: %s", args.weights.resolve())
    log.info("Output dir: %s", args.out_dir.resolve())

    t0 = time.perf_counter()
    volume = load_volume(args.volume)
    load_s = time.perf_counter() - t0
    nbytes = int(volume.nbytes)
    log.info(
        "Loaded numpy volume | shape=%s dtype=%s | ~%.2f GiB | load %.2fs",
        volume.shape,
        volume.dtype,
        nbytes / (1024.0**3),
        load_s,
    )

    t0 = time.perf_counter()
    model = YOLO(str(args.weights))
    log.info("YOLO constructor done in %.2fs", time.perf_counter() - t0)

    pred_dir = args.out_dir / "predicted_boxes_cyan"
    slice_dir = args.out_dir / "slices"
    pred_dir.mkdir(parents=True, exist_ok=True)
    if args.save_slices:
        slice_dir.mkdir(parents=True, exist_ok=True)

    max_z = int(volume.shape[2])
    n_total = min(max_z, int(args.max_slices)) if args.max_slices is not None else max_z
    signal_by_z = None
    signal_threshold = None
    if args.skip_low_signal_slices:
        signal_by_z = slice_signal_values(volume, percentile=args.slice_signal_percentile)
        signal_max = float(np.nanmax(signal_by_z)) if signal_by_z.size else 0.0
        signal_threshold = signal_max * float(np.clip(args.slice_signal_rel_min, 0.0, 1.0))
        log.info(
            "Low-signal filter | percentile=%.1f | max=%.4g | rel_min=%.3f | threshold=%.4g",
            args.slice_signal_percentile,
            signal_max,
            args.slice_signal_rel_min,
            signal_threshold,
        )
    dev_s = str(args.device) if args.device is not None else "ultralytics-default"
    log.info(
        "Inference plan | device=%s | z-planes in file=%d | will run=%d planes | imgsz=%d conf=%.3f stretch=%s (%s-%s)",
        dev_s,
        max_z,
        n_total,
        args.imgsz,
        args.conf,
        args.stretch_slices,
        args.p_lo,
        args.p_hi,
    )
    if str(args.device).lower() in ("cpu", "mps"):
        log.warning(
            "Device is %s — YOLO is much slower than CUDA; wall time grows ~linearly with z-planes "
            "(same 000714_sub-2 stack is still every plane in the .npy, not the 21-slice timing smoke test).",
            args.device,
        )

    summary = {
        "volume": str(args.volume.resolve()),
        "weights": str(args.weights.resolve()),
        "volume_shape": list(volume.shape),
        "slice_convention": "volume[:, :, z, :] from input shape (X,Y,Z,C)",
        "conf": args.conf,
        "imgsz": args.imgsz,
        "stretch_slices": args.stretch_slices,
        "stretch_percentiles": [args.p_lo, args.p_hi] if args.stretch_slices else None,
        "voxel_spacing_um": [float(x) for x in args.voxel_spacing_um],
        "scale_bar_um": float(args.scale_bar_um),
        "num_slices": max_z,
        "max_slices": args.max_slices,
        "slices": [],
    }

    loop_t0 = time.perf_counter()
    for z_idx, plane in iter_cellpose_style_slices(volume):
        if args.max_slices is not None and len(summary["slices"]) >= args.max_slices:
            break
        t_slice = time.perf_counter()
        if signal_by_z is not None and float(signal_by_z[z_idx]) < float(signal_threshold):
            summary["slices"].append(
                {
                    "z": int(z_idx),
                    "n_predictions": 0,
                    "prediction_png": "",
                    "slice_png": "",
                    "boxes_xyxy_conf": [],
                    "skipped_low_signal": True,
                    "slice_signal": float(signal_by_z[z_idx]),
                    "slice_signal_threshold": float(signal_threshold),
                }
            )
            if args.log_every <= 1:
                log.info(
                    "[%d/%d z=%04d] skipped low signal %.4g < %.4g",
                    len(summary["slices"]),
                    n_total,
                    z_idx,
                    float(signal_by_z[z_idx]),
                    float(signal_threshold),
                )
            continue
        img_rgb = to_uint8_image(plane, stretch=args.stretch_slices, p_lo=args.p_lo, p_hi=args.p_hi)
        predict_kwargs = {"conf": args.conf, "imgsz": args.imgsz, "verbose": False}
        if args.device is not None:
            predict_kwargs["device"] = args.device
        result = model.predict(img_rgb, **predict_kwargs)[0]
        boxes = result.boxes.xyxy.detach().cpu().numpy() if result.boxes is not None else np.zeros((0, 4))
        confs = result.boxes.conf.detach().cpu().numpy() if result.boxes is not None else np.zeros((0,))

        stem = f"slice_{z_idx:05d}"
        out_pred = pred_dir / f"{stem}_pred_cyan.png"
        overlay_bgr = draw_predictions(
            img_rgb,
            boxes,
            confs,
            line_width=args.line_width,
            show_conf=args.show_conf,
        )
        if args.scale_bar_um > 0:
            draw_scale_bar(
                overlay_bgr,
                length_um=float(args.scale_bar_um),
                col_um_per_px=float(args.voxel_spacing_um[1]),
            )
        cv2.imwrite(str(out_pred), overlay_bgr)

        plain_path = None
        if args.save_slices:
            plain_path = slice_dir / f"{stem}.png"
            cv2.imwrite(str(plain_path), cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR))

        summary["slices"].append(
            {
                "z": int(z_idx),
                "n_predictions": int(len(boxes)),
                "prediction_png": str(out_pred),
                "slice_png": str(plain_path) if plain_path is not None else "",
                "boxes_xyxy_conf": [
                    [float(x1), float(y1), float(x2), float(y2), float(conf)]
                    for (x1, y1, x2, y2), conf in zip(boxes, confs)
                ],
            }
        )

        slice_s = time.perf_counter() - t_slice
        done = len(summary["slices"])
        elapsed = time.perf_counter() - loop_t0
        rem = max(0, n_total - done)
        eta_s = (elapsed / done) * rem if done else float("nan")
        if (
            args.log_every <= 1
            or done % int(args.log_every) == 0
            or done == 1
            or done == n_total
        ):
            eta_m = eta_s / 60.0
            rate = done / elapsed if elapsed > 0 else float("nan")
            log.info(
                "[%d/%d z=%04d] n_pred=%d | %.2fs/plane | %.2fs elapsed | %.3f planes/s | ETA ~%.1f min",
                done,
                n_total,
                z_idx,
                len(boxes),
                slice_s,
                elapsed,
                rate,
                eta_m if rem else 0.0,
            )

    summary["total_predictions"] = int(sum(s["n_predictions"] for s in summary["slices"]))
    summary_path = args.out_dir / "predictions_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    ran = len(summary["slices"])
    total_s = time.perf_counter() - loop_t0
    if args.max_slices is not None and ran < max_z:
        log.warning(
            "Partial run only: %d/%d z-planes (--max-slices); do not use this JSON for full-volume fusion.",
            ran,
            max_z,
        )
    log.info(
        "Finished | planes=%d / file_z=%d | predictions=%d | infer+write loop %.1fs (~%.3f s/plane avg)",
        ran,
        max_z,
        summary["total_predictions"],
        total_s,
        total_s / ran if ran else 0.0,
    )
    log.info("Cyan overlays: %s", pred_dir)
    log.info("Summary JSON: %s", summary_path)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Slice a NeuroPAL volume like Cellpose (volume[:, :, z, :]), run YOLOv8 on every "
            "slice, and save PNG overlays with cyan predicted boxes only."
        )
    )
    parser.add_argument("--volume", required=True, type=Path, help="Input .npy volume, shape (X,Y,Z,C).")
    parser.add_argument("--weights", required=True, type=Path, help="YOLOv8 weights, e.g. weights/best.pt.")
    parser.add_argument("--out_dir", required=True, type=Path, help="Output folder.")
    parser.add_argument("--conf", type=float, default=0.25, help="YOLO confidence threshold.")
    parser.add_argument("--imgsz", type=int, default=640, help="YOLO inference image size.")
    parser.add_argument("--device", default=None, help="Ultralytics device, e.g. 0 for GPU or cpu.")
    parser.add_argument("--line_width", type=int, default=2, help="Cyan box line width.")
    parser.add_argument("--show_conf", action="store_true", help="Draw confidence values next to boxes.")
    parser.add_argument(
        "--voxel-spacing-um",
        type=float,
        nargs=3,
        metavar=("SX", "SY", "SZ"),
        default=[0.4, 0.4, 1.5],
        help="Microns per voxel (row, col, z); col spacing calibrates the overlay scale bar.",
    )
    parser.add_argument(
        "--scale-bar-um",
        type=float,
        default=10.0,
        help="Draw this horizontal micron scale bar on cyan overlay PNGs (0 disables; default 10).",
    )
    parser.add_argument(
        "--stretch_slices",
        action="store_true",
        help="Apply per-slice p_lo/p_hi RGB percentile stretch before YOLO inference.",
    )
    parser.add_argument("--p_lo", type=float, default=2.0, help="Lower percentile for --stretch_slices.")
    parser.add_argument("--p_hi", type=float, default=98.0, help="Upper percentile for --stretch_slices.")
    parser.add_argument(
        "--skip-low-signal-slices",
        action="store_true",
        help="Skip z-planes whose signal percentile is below a relative threshold.",
    )
    parser.add_argument(
        "--slice-signal-percentile",
        type=float,
        default=90.0,
        help="Raw-volume percentile used by --skip-low-signal-slices.",
    )
    parser.add_argument(
        "--slice-signal-rel-min",
        type=float,
        default=0.15,
        help="Skip planes below this fraction of the maximum per-slice signal percentile.",
    )
    parser.add_argument(
        "--save_slices",
        action="store_true",
        help="Also save the plain per-z slice PNGs in out_dir/slices.",
    )
    parser.add_argument(
        "--max-slices",
        type=int,
        default=None,
        metavar="N",
        help="Process only the first N z-planes (debug/profiling). Output JSON is partial; do not feed to fusion.",
    )
    parser.add_argument(
        "--cprofile",
        type=Path,
        default=None,
        metavar="OUT.prof",
        help="Write Python cProfile stats (use with e.g. snakeviz, or: python -m pstats OUT.prof).",
    )
    parser.add_argument(
        "--cprofile-sort",
        choices=("cumtime", "tottime"),
        default="cumtime",
        help="Sort order for --cprofile text summary (default: cumtime).",
    )
    parser.add_argument(
        "--cprofile-top",
        type=int,
        default=40,
        metavar="K",
        help="Print top K functions after profiling (0 = skip print).",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Debug logging (e.g. more detail from dependencies if any).",
    )
    parser.add_argument(
        "--log-every",
        type=int,
        default=1,
        metavar="N",
        help="Progress log every N slices (default 1 = every slice; use 10/50 on slow I/O).",
    )
    args = parser.parse_args()

    _configure_logging(args.verbose)

    if args.log_every < 1:
        parser.error("--log-every must be >= 1")

    if args.cprofile is not None:
        prof = cProfile.Profile()
        prof.enable()
        try:
            _run_inference(args)
        finally:
            prof.disable()
            args.cprofile.parent.mkdir(parents=True, exist_ok=True)
            prof.dump_stats(str(args.cprofile))
            print(f"cProfile: wrote {args.cprofile.resolve()}")
            if args.cprofile_top > 0:
                s = pstats.Stats(prof)
                key = pstats.SortKey.CUMULATIVE if args.cprofile_sort == "cumtime" else pstats.SortKey.TIME
                s.sort_stats(key).print_stats(args.cprofile_top)
        return

    _run_inference(args)


if __name__ == "__main__":
    main()
