#!/usr/bin/env python3
"""Export NWB neuron ROI centroids and labels for endpoint evaluation."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("nwb_path", type=Path)
    parser.add_argument("--dataset-id", default="000981")
    parser.add_argument("--gat-root", type=Path, default=Path("../GAT-NeuroPAL"))
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    gat_root = args.gat_root.resolve()
    sys.path.insert(0, str(gat_root))

    from data.preprocessing import load_roi_centroids  # noqa: WPS433
    from utils.neuron_classes import neuron_to_class  # noqa: WPS433

    records = load_roi_centroids(str(args.nwb_path), args.dataset_id)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    with args.out.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "roi_idx",
                "label",
                "class_label",
                "x",
                "y",
                "z",
                "recognized",
            ],
        )
        writer.writeheader()
        for idx, record in enumerate(records):
            label = str(record.get("neuron_id") or "").strip()
            class_label = ""
            recognized = False
            if label:
                try:
                    class_label = neuron_to_class(label)
                    recognized = True
                except ValueError:
                    class_label = ""
            writer.writerow(
                {
                    "roi_idx": idx,
                    "label": label,
                    "class_label": class_label,
                    "x": record["x_aniso"],
                    "y": record["y_aniso"],
                    "z": record["z_aniso"],
                    "recognized": int(recognized),
                }
            )

    labeled = sum(1 for record in records if str(record.get("neuron_id") or "").strip())
    print(f"exported_rois={len(records)} labeled={labeled} out={args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
