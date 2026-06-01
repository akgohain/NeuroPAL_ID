#!/usr/bin/env python3
"""Validate or rebuild visualize_light.mlapp from the extracted app folder.

This keeps the App Designer archive shape stable. In particular, MATLAB rejects
packages that contain an accidental root-level visualize_light_app.m member even
though generic ZIP validation passes.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


REQUIRED_MEMBERS = {
    "[Content_Types].xml",
    "_rels/.rels",
    "appdesigner/appModel.mat",
    "matlab/document.xml",
    "metadata/appMetadata.xml",
}


FORBIDDEN_ROOT_SUFFIXES = ("_app.m",)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="NeuroPAL_ID repository root.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate the existing mlapp without rebuilding it.",
    )
    return parser.parse_args()


def validate_archive(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad is not None:
            raise ValueError(f"{path} has a corrupt archive member: {bad}")
        names = set(archive.namelist())
    missing = sorted(REQUIRED_MEMBERS - names)
    if missing:
        raise ValueError(f"{path} is missing required members: {missing}")
    forbidden = sorted(
        name for name in names
        if "/" not in name and name.endswith(FORBIDDEN_ROOT_SUFFIXES)
    )
    if forbidden:
        raise ValueError(f"{path} has invalid root-level source members: {forbidden}")


def iter_archive_files(source_dir: Path):
    for path in sorted(source_dir.rglob("*")):
        if path.is_file():
            rel = path.relative_to(source_dir).as_posix()
            if "/" not in rel and rel.endswith(FORBIDDEN_ROOT_SUFFIXES):
                continue
            yield path, rel


def rebuild(repo_root: Path) -> Path:
    source_dir = repo_root / ".mlapp_extracted" / "visualize_light"
    target = repo_root / "visualize_light.mlapp"
    if not source_dir.is_dir():
        raise FileNotFoundError(source_dir)

    with tempfile.NamedTemporaryFile(
        dir=target.parent,
        prefix="visualize_light.",
        suffix=".mlapp.tmp",
        delete=False,
    ) as handle:
        temp_path = Path(handle.name)

    try:
        with zipfile.ZipFile(temp_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path, rel in iter_archive_files(source_dir):
                archive.write(path, rel)
        validate_archive(temp_path)
        shutil.move(str(temp_path), str(target))
    finally:
        if temp_path.exists():
            temp_path.unlink()

    return target


def matlab_smoke(repo_root: Path, mlapp: Path) -> None:
    matlab = Path("/Applications/MATLAB_R2024a.app/bin/matlab")
    if not matlab.exists():
        return
    code = (
        f"cd('{repo_root.as_posix()}'); "
        "addpath(pwd); "
        "assert(strcmp(which('visualize_light'), fullfile(pwd,'visualize_light.mlapp'))); "
        "disp('mlapp_resolves_ok');"
    )
    subprocess.run([str(matlab), "-batch", code], check=True)


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    mlapp = repo_root / "visualize_light.mlapp"
    if args.check:
        validate_archive(mlapp)
    else:
        mlapp = rebuild(repo_root)
    matlab_smoke(repo_root, mlapp)
    print(f"OK: {mlapp}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
