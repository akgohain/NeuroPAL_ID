#!/usr/bin/env python3
"""Compare two NeuroPAL UI capture directories and emit visual diffs."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("--diff-dir", type=Path)
    parser.add_argument("--max-changed-ratio", type=float, default=0.01)
    parser.add_argument("--max-mean-delta", type=float, default=0.01)
    parser.add_argument(
        "--accept",
        action="store_true",
        help="Replace the baseline PNG/JSON files with the current capture.",
    )
    return parser.parse_args()


def image_metrics(baseline_path: Path, current_path: Path, diff_path: Path) -> dict:
    baseline = Image.open(baseline_path).convert("RGB")
    current = Image.open(current_path).convert("RGB")
    if baseline.size != current.size:
        return {
            "status": "size_mismatch",
            "baseline_size": baseline.size,
            "current_size": current.size,
        }

    left = np.asarray(baseline, dtype=np.int16)
    right = np.asarray(current, dtype=np.int16)
    delta = np.abs(left - right)
    pixel_delta = delta.max(axis=2)
    changed = pixel_delta > 20

    heat = np.zeros_like(left, dtype=np.uint8)
    heat[:, :, 0] = np.clip(pixel_delta * 4, 0, 255).astype(np.uint8)
    heat[:, :, 2] = changed.astype(np.uint8) * 180
    diff_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(heat, mode="RGB").save(diff_path)

    return {
        "status": "compared",
        "changed_ratio": float(changed.mean()),
        "mean_delta": float(delta.mean() / 255.0),
        "max_delta": int(delta.max()),
        "diff": str(diff_path),
    }


def accept_capture(baseline: Path, current: Path) -> None:
    baseline.mkdir(parents=True, exist_ok=True)
    for pattern in ("*.png", "*.json", "README.txt"):
        for source in current.glob(pattern):
            shutil.copy2(source, baseline / source.name)


def main() -> int:
    args = parse_args()
    if args.accept:
        accept_capture(args.baseline, args.current)
        print(f"Accepted UI baseline: {args.baseline}")
        return 0

    diff_dir = args.diff_dir or args.current / "diff"
    baseline_images = {path.name: path for path in args.baseline.glob("*.png")}
    current_images = {path.name: path for path in args.current.glob("*.png")}
    names = sorted(set(baseline_images) | set(current_images))

    report = {"comparisons": [], "failures": 0}
    for name in names:
        if name not in baseline_images:
            metrics = {"status": "missing_baseline"}
        elif name not in current_images:
            metrics = {"status": "missing_current"}
        else:
            metrics = image_metrics(
                baseline_images[name], current_images[name], diff_dir / name
            )

        failed = metrics["status"] != "compared"
        if metrics["status"] == "compared":
            failed = (
                metrics["changed_ratio"] > args.max_changed_ratio
                or metrics["mean_delta"] > args.max_mean_delta
            )
        metrics.update({"image": name, "failed": failed})
        report["comparisons"].append(metrics)
        report["failures"] += int(failed)

    diff_dir.mkdir(parents=True, exist_ok=True)
    report_path = diff_dir / "comparison.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"Compared {len(names)} UI snapshots; failures={report['failures']}")
    print(report_path)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
