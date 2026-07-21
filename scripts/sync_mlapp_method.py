#!/usr/bin/env python3
"""Copy one missing App Designer method into the current mlapp document.

This updates only ``matlab/document.xml`` and preserves every other archive
member, including the current app model and metadata. It is deliberately more
conservative than rebuilding from an extraction that may be stale.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import tempfile
import zipfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("method")
    parser.add_argument("--repo-root", type=Path, default=root)
    parser.add_argument(
        "--source-document",
        type=Path,
        default=root / ".mlapp_extract" / "matlab" / "document.xml",
    )
    parser.add_argument("--no-backup", action="store_true")
    return parser.parse_args()


def method_pattern(name: str) -> re.Pattern[str]:
    escaped = re.escape(name)
    return re.compile(
        rf"\n        function\s+(?:\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?{escaped}\b"
        rf".*?(?=\n        function\b|\n    end\nend)",
        re.DOTALL,
    )


def main() -> int:
    args = parse_args()
    root = args.repo_root.resolve()
    target = root / "visualize_light.mlapp"
    source_text = args.source_document.read_text(encoding="utf-8")
    pattern = method_pattern(args.method)
    source_match = pattern.search(source_text)
    if source_match is None:
        raise ValueError(f"method {args.method!r} is absent from {args.source_document}")

    with zipfile.ZipFile(target) as archive:
        current_bytes = archive.read("matlab/document.xml")
    current_text = current_bytes.decode("utf-8")
    if pattern.search(current_text):
        print(f"OK: {args.method} already exists in {target.name}")
        return 0

    insertion_point = current_text.find("\n        function PickNeuron")
    if insertion_point < 0:
        raise ValueError("safe insertion anchor 'function PickNeuron' was not found")
    updated_text = (
        current_text[:insertion_point]
        + source_match.group(0)
        + "\n"
        + current_text[insertion_point:]
    )

    if not args.no_backup:
        backup = target.with_suffix(target.suffix + f".bak_before_{args.method}")
        if not backup.exists():
            shutil.copy2(target, backup)

    with tempfile.NamedTemporaryFile(
        dir=target.parent, prefix="visualize_light.", suffix=".mlapp.tmp", delete=False
    ) as handle:
        temporary = Path(handle.name)

    try:
        with zipfile.ZipFile(target) as source, zipfile.ZipFile(temporary, "w") as output:
            for item in source.infolist():
                payload = source.read(item.filename)
                if item.filename == "matlab/document.xml":
                    payload = updated_text.encode("utf-8")
                output.writestr(item, payload)
        with zipfile.ZipFile(temporary) as check:
            if check.testzip() is not None:
                raise ValueError("rebuilt archive failed ZIP integrity validation")
            repaired = check.read("matlab/document.xml").decode("utf-8")
            if pattern.search(repaired) is None:
                raise ValueError("method was not present after archive rebuild")
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()

    print(f"Added {args.method} to {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
