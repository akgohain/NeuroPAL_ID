#!/usr/bin/env python3
"""App Designer drift checker for generated MATLAB app artifacts.

Checks the current `visualize_light.mlapp` archive against the primary extracted
source tree, reports secondary extraction staleness without failing, and checks
callbacks from the current archive rather than an arbitrary old extraction.

Exits non-zero when drift or dangling callbacks are detected.
"""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from typing import Iterable, Optional, Set, Tuple


DOC_PROPERTIES_START = re.compile(r"^properties\s*\(\s*Access\s*=\s*public\s*\)$")
DOC_PROPERTY_DECL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s+")
CREATE_CALLBACK = re.compile(
    r"createCallbackFcn\s*\(\s*app\s*,\s*@\s*([A-Za-z_][A-Za-z0-9_]*)\s*,",
)
FUNCTION_DEF = re.compile(
    r"^\s*function\s+(?:\[[^\]]*\]\s*=\s*|[A-Za-z_][A-Za-z0-9_]*\s*=\s*)?"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|$)",
    re.MULTILINE,
)


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mlapp",
        type=Path,
        default=repo_root / "visualize_light.mlapp",
        help="Current App Designer archive",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=repo_root,
        help="Repository root to check (default: workspace root)",
    )
    parser.add_argument(
        "--primary-document",
        type=Path,
        default=repo_root / ".mlapp_extract" / "matlab" / "document.xml",
        help="Primary document.xml path",
    )
    parser.add_argument(
        "--secondary-document",
        type=Path,
        default=repo_root / ".mlapp_extracted" / "visualize_light" / "matlab" / "document.xml",
        help="Secondary document.xml path",
    )
    return parser.parse_args()


def read_text(path: Path) -> Optional[str]:
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8")


def extract_document_text(xml_path: Path) -> str:
    root = ET.parse(xml_path).getroot()
    chunks = []
    for element in root.iter():
        if element.tag.split("}")[-1] == "t" and element.text:
            chunks.append(element.text)
    return "".join(chunks)


def extract_document_bytes(data: bytes) -> str:
    root = ET.fromstring(data)
    return "".join(
        element.text or ""
        for element in root.iter()
        if element.tag.split("}")[-1] == "t"
    )


def extract_mlapp_document(archive_path: Path) -> str:
    with zipfile.ZipFile(archive_path) as archive:
        return extract_document_bytes(archive.read("matlab/document.xml"))


def extract_component_names(document_text: str) -> Set[str]:
    names: Set[str] = set()
    in_public_properties = False

    for raw_line in document_text.splitlines():
        line = raw_line.strip()
        if not in_public_properties:
            if DOC_PROPERTIES_START.match(line):
                in_public_properties = True
            continue

        if line == "end":
            break

        match = DOC_PROPERTY_DECL.match(line)
        if match:
            names.add(match.group(1))

    return names


def compare_sets(left: Set[str], right: Set[str]) -> Tuple[Set[str], Set[str]]:
    return right - left, left - right


def format_lines(items: Iterable[str], indent: str = "  ") -> str:
    values = sorted(items)
    if not values:
        return f"{indent}(none)"
    return "\n".join(f"{indent}{value}" for value in values)


def extract_callback_references(app_text: str) -> Set[str]:
    return set(CREATE_CALLBACK.findall(app_text))


def extract_function_definitions(app_text: str) -> Set[str]:
    return set(FUNCTION_DEF.findall(app_text))


def run() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()

    failed = False

    try:
        current_text = extract_mlapp_document(args.mlapp)
    except (OSError, KeyError, zipfile.BadZipFile, ET.ParseError) as exc:
        print(f"ERROR: cannot read current mlapp document: {exc}")
        return 1

    primary_text = read_text(args.primary_document)
    secondary_text = read_text(args.secondary_document)
    if primary_text is None:
        print(f"SKIP: missing primary document: {args.primary_document}")
    if secondary_text is None:
        print(f"SKIP: missing secondary document: {args.secondary_document}")

    current_names = extract_component_names(current_text)
    if primary_text is not None:
        try:
            primary_names = extract_component_names(extract_document_text(args.primary_document))
        except ET.ParseError as exc:
            print(f"ERROR: failed to parse document XML: {exc}")
            return 1

        print(
            f"UI component declarations: current mlapp: {len(current_names)} "
            f"| primary extraction: {len(primary_names)}"
        )

        added, removed = compare_sets(primary_names, current_names)
        if added or removed:
            failed = True
            print("DRIFT: current mlapp differs from primary extraction")
            print("  Added in current mlapp:")
            print(format_lines(added, indent="    "))
            print("  Missing from current mlapp:")
            print(format_lines(removed, indent="    "))
        else:
            print("OK: current mlapp matches primary component declarations")
    else:
        print("SKIP: primary component comparison (document file is missing)")

    if secondary_text is not None:
        secondary_names = extract_component_names(extract_document_text(args.secondary_document))
        added, removed = compare_sets(current_names, secondary_names)
        if added or removed:
            print("WARNING: secondary extraction is stale (not used as build source)")
        else:
            print("OK: secondary extraction matches current component declarations")

    callback_refs = extract_callback_references(current_text)
    function_names = extract_function_definitions(current_text)
    missing = sorted(callback_refs - function_names)

    if missing:
        failed = True
        print("DRIFT: dangling callbacks found in current mlapp")
        print("  createCallbackFcn(app,@Name,...) Name has no local function definition:")
        print(format_lines(missing, indent="    "))
    else:
        print("OK: current mlapp callbacks resolve to local function definitions")

    print(f"Checked in: {repo_root}")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
