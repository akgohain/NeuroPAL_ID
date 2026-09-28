#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
exec > >(tee -a setup.log) 2>&1
stage=''

finish() {
    status=$?
    if [ -n "$stage" ] && [ -d "$stage" ]; then rm -rf -- "$stage"; fi
    if [ "$status" -ne 0 ]; then
        printf '\n%s\n' 'Setup did not finish. Keep this output for your bug report.'
    fi
    if [ -t 0 ]; then read -r -p 'Press Return to close. ' || true; fi
    exit "$status"
}
trap finish EXIT

if [ "$(uname -m)" != arm64 ] || [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
    printf '%s\n' 'This package needs an Apple silicon Mac with macOS 14 or later.'
    exit 1
fi

# Keep the setup tool and Python separate from the user's other installations.
setup_root="${NEUROPAL_SETUP_ROOT:-$HOME/Library/Application Support/NeuroPAL_ID/Methods-20260928}"
tool_dir="$setup_root/tools/uv-0.12.19"
if [ ! -x "$tool_dir/uv" ]; then
    mkdir -p "$setup_root/tools"
    stage=$(mktemp -d "$setup_root/tools/.uv-XXXXXX")
    archive="$stage/uv.tar.gz"
    curl --fail --location --retry 3 --connect-timeout 30 \
        https://github.com/astral-sh/uv/releases/download/0.12.19/uv-aarch64-apple-darwin.tar.gz \
        --output "$archive"
    printf '%s  %s\n' a9a8df1eedeb192f2e47e40e2faabfb387db4b850209118786d42f89dde3e0ba "$archive" | shasum -a 256 -c -
    tar -xzf "$archive" -C "$stage"
    mkdir -p "$tool_dir"
    mv "$stage/uv-aarch64-apple-darwin/uv" "$tool_dir/uv"
    rm -rf -- "$stage"
    stage=''
fi
export PATH="$tool_dir:/usr/bin:/bin:/usr/sbin:/sbin"
export UV_PYTHON_INSTALL_DIR="$setup_root/python"
export UV_CACHE_DIR="$setup_root/cache"
uv run --managed-python --python 3.11 --no-project setup_models.py --root "$setup_root" "$@"
printf '\n%s\n' 'Setup complete. In a fresh MATLAB session, open Start_NeuroPAL.m from this folder and click Run.'
