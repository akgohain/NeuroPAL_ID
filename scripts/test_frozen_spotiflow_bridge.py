#!/usr/bin/env python3
"""Checkpoint-free regression tests for the frozen Spotiflow v1 policy."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
BRIDGE_PATH = ROOT / "+Wrapper" / "advanced_method_bridge.py"
BUNDLE_DIR = ROOT / "method_bundles" / "spotiflow_supervised"
SPEC = importlib.util.spec_from_file_location("advanced_method_bridge", BRIDGE_PATH)
assert SPEC is not None and SPEC.loader is not None
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


def test_four_view_merge() -> None:
    views = ("identity", "flip-x", "flip-y", "flip-xy")
    predictions = [
        (view, np.asarray([[3.0, 5.0, 7.0]]), np.asarray([0.9]))
        for view in views
    ]
    merged = BRIDGE.merge_view_predictions(
        predictions, (0.4, 0.4, 1.5), views, 2.0, 0.185, 1.0
    )
    assert len(merged) == 1
    np.testing.assert_allclose(merged[0]["point"], [3.0, 5.0, 7.0])
    assert merged[0]["score"] == 0.9
    assert merged[0]["tta_support"] == 4


def test_support_calibration() -> None:
    views = ("identity", "flip-x", "flip-y", "flip-xy")
    predictions = [
        ("identity", np.asarray([[3.0, 5.0, 7.0]]), np.asarray([0.7])),
        *[(view, np.empty((0, 3)), np.empty(0)) for view in views[1:]],
    ]
    merged = BRIDGE.merge_view_predictions(
        predictions, (0.4, 0.4, 1.5), views, 2.0, 0.185, 1.0
    )
    assert merged == []


def test_view_roundtrip() -> None:
    image = np.zeros((7, 11, 15, 4), dtype=np.float32)
    original = np.asarray([[5.0, 2.0, 12.0]])
    for view in BRIDGE.VIEW_ALIASES:
        transformed = BRIDGE.transform_image(image, view)
        marker = BRIDGE.transform_image(
            np.pad(
                np.ones((1, 1, 1, 1), dtype=np.float32),
                ((5, 1), (2, 8), (12, 2), (0, 3)),
            ),
            view,
        )
        point = np.asarray(np.unravel_index(np.argmax(marker[..., 0]), transformed.shape[:3]))
        restored = BRIDGE.invert_points(point[None, :], image.shape[:3], view)
        np.testing.assert_allclose(restored, original)


def test_model_manifest() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        hashes = {}
        for name, content in {
            "last.pt": b"checkpoint",
            "config.yaml": b"model config",
            "train_config.yaml": b"training config",
        }.items():
            (root / name).write_bytes(content)
            hashes[name] = hashlib.sha256(content).hexdigest()
        manifest = {
            "checkpoint_filename": "last.pt",
            "checkpoint_sha256": hashes["last.pt"],
            "config_filename": "config.yaml",
            "config_sha256": hashes["config.yaml"],
            "train_config_filename": "train_config.yaml",
            "train_config_sha256": hashes["train_config.yaml"],
        }
        manifest_path = root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        BRIDGE.verify_spotiflow_model(root, manifest_path)
        (root / "last.pt").write_bytes(b"wrong")
        try:
            BRIDGE.verify_spotiflow_model(root, manifest_path)
        except ValueError as error:
            assert "SHA-256 mismatch" in str(error)
        else:
            raise AssertionError("Expected the altered checkpoint to be rejected")


def test_committed_frozen_contract() -> None:
    bundle = json.loads(
        (BUNDLE_DIR / "method_bundle.example.json").read_text(encoding="utf-8")
    )
    config = bundle["configuration"]
    assert config["views"] == ["identity", "flip-x", "flip-y", "flip-xy"]
    assert config["merge_radius_um"] == 2.0
    assert config["candidate_probability"] == 0.02
    assert config["operating_score_threshold"] == 0.185
    assert config["deterministic"] is True
    assert "46e7ef4e67519cce7bb13d13bc215ebb9147541c" in bundle["source_revision"]
    model = json.loads(
        (BUNDLE_DIR / "spotiflow_neuropal_v1_model.json").read_text(
            encoding="utf-8"
        )
    )
    assert model["spotiflow_version"] == "0.6.5"
    assert model["checkpoint_size_bytes"] == 142113033
    assert len(model["checkpoint_sha256"]) == 64


def main() -> None:
    test_four_view_merge()
    test_support_calibration()
    test_view_roundtrip()
    test_model_manifest()
    test_committed_frozen_contract()
    print("FROZEN_SPOTIFLOW_BRIDGE=PASS")


if __name__ == "__main__":
    main()
