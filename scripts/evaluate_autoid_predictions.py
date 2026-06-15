#!/usr/bin/env python3
"""Score NeuroPAL auto-ID endpoint CSVs against hidden NWB labels."""

from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path


def _read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def _pct(numer: int, denom: int) -> float:
    if denom == 0:
        return math.nan
    return 100.0 * numer / denom


def _print_metric(name: str, numer: int, denom: int) -> None:
    value = _pct(numer, denom)
    if math.isnan(value):
        print(f"{name}=NA ({numer}/{denom})")
    else:
        print(f"{name}={value:.2f}% ({numer}/{denom})")


def score_transformer(csv_path: Path) -> None:
    rows = _read_rows(csv_path)
    labeled = [r for r in rows if int(float(r.get("true_class_idx", "-1") or -1)) >= 0]
    top1 = [r for r in labeled if int(float(r.get("true_class_rank", "-1") or -1)) == 1]
    top5 = [
        r
        for r in labeled
        if 1 <= int(float(r.get("true_class_rank", "-1") or -1)) <= 5
    ]
    low_conf = [r for r in rows if str(r.get("flag_low_confidence", "")).lower() == "true"]
    print(f"endpoint=transformer csv={csv_path}")
    print(f"predicted_rows={len(rows)} labeled_rows={len(labeled)} low_confidence_rows={len(low_conf)}")
    _print_metric("top1_class_accuracy", len(top1), len(labeled))
    _print_metric("top5_class_accuracy", len(top5), len(labeled))


def score_nearest(csv_path: Path, gat_root: Path) -> None:
    sys.path.insert(0, str(gat_root.resolve()))
    from utils.neuron_classes import neuron_to_class  # noqa: WPS433

    rows = _read_rows(csv_path)
    comparable = [r for r in rows if r.get("truth_label") and r.get("predicted_id")]
    exact = [r for r in comparable if r["truth_label"].upper() == r["predicted_id"].upper()]

    class_matches = []
    class_comparable = []
    for row in comparable:
        try:
            truth_class = neuron_to_class(row["truth_label"])
            pred_class = neuron_to_class(row["predicted_id"])
        except ValueError:
            continue
        class_comparable.append(row)
        if truth_class == pred_class:
            class_matches.append(row)

    print(f"endpoint=nearest csv={csv_path}")
    print(f"predicted_rows={len(rows)} comparable_rows={len(comparable)}")
    _print_metric("exact_id_accuracy", len(exact), len(comparable))
    _print_metric("class_accuracy", len(class_matches), len(class_comparable))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--transformer-csv", type=Path)
    parser.add_argument("--nearest-csv", type=Path)
    parser.add_argument("--gat-root", type=Path, default=Path("../GAT-NeuroPAL"))
    args = parser.parse_args()

    if args.transformer_csv:
        score_transformer(args.transformer_csv)
    if args.nearest_csv:
        score_nearest(args.nearest_csv, args.gat_root)
    if not args.transformer_csv and not args.nearest_csv:
        parser.error("provide --transformer-csv and/or --nearest-csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
