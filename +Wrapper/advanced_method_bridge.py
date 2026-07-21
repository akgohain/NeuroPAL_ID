#!/usr/bin/env python3
"""Checkpoint-independent bridges for advanced NeuroPAL methods."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np


def progress(message: str) -> None:
    print(f"NEUROPAL_PROGRESS:{message}", flush=True)


def normalize_per_channel(image: np.ndarray) -> np.ndarray:
    output = np.zeros(image.shape, dtype=np.float32)
    for channel in range(image.shape[-1]):
        values = image[..., channel].astype(np.float32, copy=False)
        lo, hi = np.percentile(values, (1.0, 99.8))
        if hi > lo:
            output[..., channel] = (values - lo) / (hi - lo)
    return output


def run_spotiflow(request_path: Path, response_path: Path) -> None:
    from spotiflow.model import Spotiflow

    request = json.loads(request_path.read_text(encoding="utf-8"))
    progress("Loading NeuroPAL volume")
    if request.get("volume_order") != "F" or request.get("volume_dtype") != "float32":
        raise ValueError("Unsupported staged-volume encoding")
    shape = tuple(int(value) for value in request["volume_shape_yxzc"])
    expected_values = int(np.prod(shape))
    volume = np.fromfile(request["volume_raw"], dtype=np.float32)
    if volume.size != expected_values:
        raise ValueError(
            f"Staged volume has {volume.size} values; expected {expected_values} for {shape}"
        )
    volume = volume.reshape(shape, order="F")
    if volume.ndim == 3:
        volume = volume[..., None]
    if volume.ndim != 4:
        raise ValueError(f"Expected Y,X,Z,C volume, got {volume.shape}")

    image = np.transpose(volume, (2, 0, 1, 3))
    original_shape = image.shape[:3]
    pad_width: list[tuple[int, int]] = []
    offsets: list[int] = []
    for size, target in zip(original_shape, (32, 64, 64)):
        missing = max(target - size, 0)
        before = missing // 2
        pad_width.append((before, missing - before))
        offsets.append(before)
    image = np.pad(image, pad_width + [(0, 0)], mode="constant")

    progress("Loading Spotiflow checkpoint")
    model = Spotiflow.from_folder(
        request["checkpoint"],
        which=request.get("which", "last"),
        map_location=request.get("device", "auto"),
        verbose=False,
    )
    normalizer = normalize_per_channel if request.get("normalizer_mode") == "per-channel" else "auto"
    threshold = float(request.get("probability_threshold", -1))
    progress("Running Spotiflow inference")
    points, details = model.predict(
        image,
        prob_thresh=None if threshold < 0 else threshold,
        min_distance=int(request.get("minimum_distance", 1)),
        normalizer=normalizer,
        device=request.get("device", "auto"),
        subpix=True,
        verbose=False,
    )

    points = np.asarray(points, dtype=float)
    if points.ndim == 1 and points.size:
        points = points.reshape(1, -1)
    probabilities = getattr(details, "prob", None)
    probabilities = None if probabilities is None else np.asarray(probabilities).reshape(-1)
    scale_x, scale_y, scale_z = [float(value) for value in request["scale_um_xyz"]]
    rows: list[dict[str, float | str]] = []
    centroids_yxz: list[list[float]] = []
    for index, point in enumerate(points):
        z = float(point[0]) - offsets[0]
        y = float(point[1]) - offsets[1]
        x = float(point[2]) - offsets[2]
        if not (0 <= z < original_shape[0] and 0 <= y < original_shape[1] and 0 <= x < original_shape[2]):
            continue
        score = 1.0
        if probabilities is not None and index < len(probabilities) and np.isfinite(probabilities[index]):
            score = float(np.clip(probabilities[index], 0, 1))
        centroids_yxz.append([y + 1, x + 1, z + 1])
        rows.append({
            "pred_id": f"spotiflow_{len(rows):05d}",
            "x_um": x * scale_x,
            "y_um": y * scale_y,
            "z_um": z * scale_z,
            "score": score,
        })

    output_csv = Path(request["output_csv"])
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["pred_id", "x_um", "y_um", "z_um", "score"])
        writer.writeheader()
        writer.writerows(rows)
    response_path.write_text(json.dumps({
        "method_id": "spotiflow_supervised",
        "centroids_yxz": centroids_yxz,
        "scores": [row["score"] for row in rows],
        "predictions_csv": str(output_csv),
        "num_centroids": len(rows),
    }, indent=2) + "\n", encoding="utf-8")
    progress(f"Spotiflow finished: {len(rows)} centroids")


def read_predictions(path: Path, source: str, threshold: float) -> list[dict[str, float | str]]:
    rows: list[dict[str, float | str]] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        required = {"pred_id", "x_um", "y_um", "z_um", "score"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"{path} is missing columns: {', '.join(sorted(missing))}")
        for row in reader:
            score = float(row["score"])
            coordinates = [float(row[key]) for key in ("x_um", "y_um", "z_um")]
            if not np.isfinite([*coordinates, score]).all() or not 0 <= score <= 1:
                raise ValueError(f"{path} contains non-finite coordinates or an invalid score")
            if score < threshold:
                continue
            rows.append({
                "pred_id": row["pred_id"],
                "source": source,
                "x_um": coordinates[0],
                "y_um": coordinates[1],
                "z_um": coordinates[2],
                "score": score,
            })
    return rows


def xyz(row: dict[str, float | str]) -> np.ndarray:
    return np.asarray([row["x_um"], row["y_um"], row["z_um"]], dtype=float)


def run_ensemble(request_path: Path, response_path: Path) -> None:
    request = json.loads(request_path.read_text(encoding="utf-8"))
    spot = read_predictions(Path(request["spotiflow_csv"]), "spotiflow", float(request.get("spotiflow_threshold", 0.30)))
    yolo = read_predictions(Path(request["yolo_csv"]), "yolo", float(request.get("yolo_threshold", 0.30)))
    nnunet = read_predictions(Path(request["nnunet_csv"]), "nnunet", float(request.get("nnunet_threshold", 0.30)))
    agreement = float(request.get("agreement_radius_um", 3.0))
    isolation = float(request.get("isolation_radius_um", 2.5))

    output = [dict(row) for row in spot]
    pair_candidates = sorted(
        (
            float(np.linalg.norm(xyz(yolo_row) - xyz(nn_row))),
            yolo_index,
            nn_index,
        )
        for yolo_index, yolo_row in enumerate(yolo)
        for nn_index, nn_row in enumerate(nnunet)
        if float(np.linalg.norm(xyz(yolo_row) - xyz(nn_row))) <= agreement
    )
    used_yolo: set[int] = set()
    used_nnunet: set[int] = set()
    matched_pairs: list[tuple[int, int]] = []
    for _, yolo_index, nn_index in pair_candidates:
        if yolo_index in used_yolo or nn_index in used_nnunet:
            continue
        used_yolo.add(yolo_index)
        used_nnunet.add(nn_index)
        matched_pairs.append((yolo_index, nn_index))

    for yolo_index, nn_index in matched_pairs:
        yolo_row = yolo[yolo_index]
        nn_row = nnunet[nn_index]
        weights = np.asarray([float(yolo_row["score"]), float(nn_row["score"])])
        point = np.average(np.vstack([xyz(yolo_row), xyz(nn_row)]), axis=0, weights=weights)
        if output and min(float(np.linalg.norm(point - xyz(row))) for row in output) < isolation:
            continue
        output.append({
            "pred_id": f"ensemble_rescue_{len(output):05d}",
            "source": "yolo+nnunet",
            "x_um": float(point[0]),
            "y_um": float(point[1]),
            "z_um": float(point[2]),
            "score": float(np.mean(weights)),
        })

    output_csv = Path(request["output_csv"])
    with output_csv.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = ["pred_id", "source", "x_um", "y_um", "z_um", "score"]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(output)
    response_path.write_text(json.dumps({
        "method_id": "detection_moe",
        "predictions_csv": str(output_csv),
        "num_centroids": len(output),
        "num_spotiflow": len(spot),
        "num_rescued": len(output) - len(spot),
    }, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("spotiflow", "ensemble"))
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--response", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "spotiflow":
        run_spotiflow(args.request, args.response)
    else:
        run_ensemble(args.request, args.response)


if __name__ == "__main__":
    main()
