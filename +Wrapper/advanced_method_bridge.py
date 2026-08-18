#!/usr/bin/env python3
"""Checkpoint-independent bridges for advanced NeuroPAL methods."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
from typing import Any

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


VIEW_ALIASES = {
    "identity": (0, False),
    "flip-x": (0, True),
    "flip-y": (2, True),
    "flip-xy": (2, False),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_spotiflow_model(model_dir: Path, manifest_path: Path) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    checks = (
        (manifest["checkpoint_filename"], manifest["checkpoint_sha256"]),
        (manifest["config_filename"], manifest["config_sha256"]),
        (manifest["train_config_filename"], manifest["train_config_sha256"]),
    )
    for filename, expected in checks:
        path = model_dir / filename
        if not path.is_file():
            raise FileNotFoundError(f"Frozen detector file is missing: {path}")
        actual = sha256(path)
        if actual != expected:
            raise ValueError(
                f"SHA-256 mismatch for {path}: expected {expected}, got {actual}"
            )
    expected_version = str(manifest.get("spotiflow_version", "")).strip()
    if expected_version:
        try:
            actual_version = importlib.metadata.version("spotiflow")
        except importlib.metadata.PackageNotFoundError as error:
            raise ImportError("Frozen detector requires Spotiflow") from error
        if actual_version != expected_version:
            raise ValueError(
                "Spotiflow version mismatch: "
                f"expected {expected_version}, got {actual_version}"
            )


def configure_determinism() -> None:
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    try:
        import torch
    except ImportError:
        return
    torch.manual_seed(0)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(0)
    torch.use_deterministic_algorithms(True)
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True


def transform_image(image: np.ndarray, view: str) -> np.ndarray:
    rotations, reflect_x = VIEW_ALIASES[view]
    transformed = np.rot90(image, k=rotations, axes=(1, 2)) if rotations else image
    if reflect_x:
        transformed = np.flip(transformed, axis=2)
    return np.ascontiguousarray(transformed)


def invert_points(
    points_zyx: np.ndarray, shape_zyx: tuple[int, int, int], view: str
) -> np.ndarray:
    restored = np.asarray(points_zyx, dtype=float).copy()
    if restored.size == 0:
        return restored.reshape(0, 3)
    rotations, reflect_x = VIEW_ALIASES[view]
    height, width = float(shape_zyx[1]), float(shape_zyx[2])
    transformed_width = height if rotations % 2 else width
    if reflect_x:
        restored[:, 2] = transformed_width - 1.0 - restored[:, 2]
    transformed_y = restored[:, 1].copy()
    transformed_x = restored[:, 2].copy()
    if rotations == 1:
        restored[:, 1] = transformed_x
        restored[:, 2] = width - 1.0 - transformed_y
    elif rotations == 2:
        restored[:, 1] = height - 1.0 - transformed_y
        restored[:, 2] = width - 1.0 - transformed_x
    elif rotations == 3:
        restored[:, 1] = height - 1.0 - transformed_x
        restored[:, 2] = transformed_y
    return restored


def detail_scores(details: Any, count: int) -> np.ndarray:
    probability = getattr(details, "prob", None)
    if probability is None:
        return np.ones(count, dtype=float)
    scores = np.asarray(probability, dtype=float).reshape(-1)
    if len(scores) != count:
        raise ValueError(f"Spotiflow returned {count} points but {len(scores)} scores")
    return scores


def merge_view_predictions(
    predictions: list[tuple[str, np.ndarray, np.ndarray]],
    spacing_xyz_um: tuple[float, float, float],
    views: tuple[str, ...],
    merge_radius_um: float,
    operating_score_threshold: float,
    support_power: float,
) -> list[dict[str, Any]]:
    spacing_zyx = np.asarray(spacing_xyz_um[::-1], dtype=float)
    candidates = [
        {"point": point, "score": float(score), "view": view}
        for view, points, scores in predictions
        for point, score in zip(points, scores)
    ]

    def distance(left: dict[str, Any], right: dict[str, Any]) -> float:
        return float(np.linalg.norm((left["point"] - right["point"]) * spacing_zyx))

    clusters: list[list[dict[str, Any]]] = []
    for candidate in sorted(candidates, key=lambda row: (-row["score"], row["view"])):
        choices = []
        for cluster_index, cluster in enumerate(clusters):
            if any(member["view"] == candidate["view"] for member in cluster):
                continue
            distances = [distance(candidate, member) for member in cluster]
            if distances and max(distances) <= merge_radius_um:
                choices.append((float(np.mean(distances)), cluster_index))
        if choices:
            clusters[min(choices)[1]].append(candidate)
        else:
            clusters.append([candidate])

    merged: list[dict[str, Any]] = []
    for cluster in clusters:
        scores = np.asarray([member["score"] for member in cluster], dtype=float)
        scores = np.where(np.isfinite(scores), scores, 0.0)
        weights = np.clip(scores, 1e-6, None)
        center = np.average(
            np.stack([member["point"] for member in cluster]), axis=0, weights=weights
        )
        support = len(cluster)
        raw_score = float(scores.mean())
        calibrated_score = raw_score * (support / len(views)) ** support_power
        if calibrated_score < operating_score_threshold:
            continue
        merged.append(
            {
                "point": center,
                "score": calibrated_score,
                "raw_score": raw_score,
                "tta_support": support,
                "tta_views": "+".join(sorted(member["view"] for member in cluster)),
            }
        )
    return merged


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
    if volume.ndim != 4 or volume.shape[-1] != 4:
        raise ValueError(f"Expected Y,X,Z,4 RGBW volume, got {volume.shape}")

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

    views = tuple(request.get("views", ("identity", "flip-x", "flip-y", "flip-xy")))
    unknown_views = set(views).difference(VIEW_ALIASES)
    if unknown_views:
        raise ValueError(f"Unsupported TTA views: {sorted(unknown_views)}")
    spacing = tuple(float(value) for value in request["scale_um_xyz"])
    if len(spacing) != 3 or any(value <= 0 for value in spacing):
        raise ValueError("scale_um_xyz must contain three positive values")
    checkpoint = Path(request["checkpoint"])
    model_manifest = Path(request["model_manifest"])
    progress("Verifying frozen Spotiflow checkpoint")
    verify_spotiflow_model(checkpoint, model_manifest)
    if bool(request.get("deterministic", True)):
        configure_determinism()
    progress("Loading frozen Spotiflow checkpoint")
    model = Spotiflow.from_folder(
        str(checkpoint),
        which=request.get("which", "last"),
        map_location=request.get("device", "auto"),
        verbose=False,
    )
    normalizer = normalize_per_channel if request.get("normalizer_mode") == "per-channel" else "auto"
    candidate_probability = float(request.get("candidate_probability", 0.02))
    view_predictions = []
    for view_index, view in enumerate(views, start=1):
        progress(f"Running Spotiflow view {view_index}/{len(views)}: {view}")
        transformed = transform_image(image, view)
        points, details = model.predict(
            transformed,
            prob_thresh=candidate_probability,
            min_distance=int(request.get("minimum_distance", 1)),
            normalizer=normalizer,
            device=request.get("device", "auto"),
            subpix=bool(request.get("subpixel", True)),
            peak_mode=request.get("peak_mode", "fast"),
            verbose=False,
        )
        points = np.asarray(points, dtype=float)
        if points.ndim == 1 and points.size:
            points = points.reshape(1, -1)
        points = invert_points(points, image.shape[:3], view)
        view_predictions.append((view, points, detail_scores(details, len(points))))

    merged = merge_view_predictions(
        view_predictions,
        spacing,
        views,
        float(request.get("merge_radius_um", 2.0)),
        float(request.get("operating_score_threshold", 0.185)),
        float(request.get("support_power", 1.0)),
    )
    scale_x, scale_y, scale_z = [float(value) for value in request["scale_um_xyz"]]
    rows: list[dict[str, float | str | int]] = []
    centroids_yxz: list[list[float]] = []
    for item in merged:
        point = item["point"]
        z = float(point[0]) - offsets[0]
        y = float(point[1]) - offsets[1]
        x = float(point[2]) - offsets[2]
        if not (0 <= z < original_shape[0] and 0 <= y < original_shape[1] and 0 <= x < original_shape[2]):
            continue
        score = float(np.clip(item["score"], 0, 1))
        rows.append({
            "pred_id": f"spotiflow_{len(rows):05d}",
            "x_um": x * scale_x,
            "y_um": y * scale_y,
            "z_um": z * scale_z,
            "score": score,
            "raw_score": float(item["raw_score"]),
            "tta_support": int(item["tta_support"]),
            "tta_views": str(item["tta_views"]),
            "_centroid_yxz": [y + 1, x + 1, z + 1],
        })

    rows.sort(key=lambda row: float(row["score"]), reverse=True)
    centroids_yxz = [row.pop("_centroid_yxz") for row in rows]
    for index, row in enumerate(rows):
        row["pred_id"] = f"spotiflow_{index:05d}"

    output_csv = Path(request["output_csv"])
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=[
            "pred_id", "x_um", "y_um", "z_um", "score", "raw_score",
            "tta_support", "tta_views"
        ])
        writer.writeheader()
        writer.writerows(rows)
    response_path.write_text(json.dumps({
        "method_id": "spotiflow_supervised",
        "centroids_yxz": centroids_yxz,
        "scores": [row["score"] for row in rows],
        "predictions_csv": str(output_csv),
        "num_centroids": len(rows),
        "policy": "spotiflow_neuropal_v1_four_view_tta",
        "source_revision": request.get("source_revision", "unknown"),
        "model_manifest_sha256": sha256(model_manifest),
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
