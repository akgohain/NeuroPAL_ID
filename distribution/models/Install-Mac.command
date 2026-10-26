#!/bin/bash
set -euo pipefail

folder=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
support="$HOME/Library/Application Support/NeuroPAL_ID"
if [ "$(uname -m)" != arm64 ] || [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
    printf '%s\n' 'Managed model installation needs an Apple silicon Mac with macOS 14 or later.'
    exit 1
fi

# Bootstrap only a managed Python; model selection remains in the application.
tool_dir="$support/tools/uv-0.12.19"
stage=''
finish() {
    status=$?
    if [ -n "$stage" ]; then rm -rf -- "$stage"; fi
    exit "$status"
}
trap finish EXIT
if [ ! -x "$tool_dir/uv" ]; then
    mkdir -p "$support/tools"
    stage=$(mktemp -d "$support/tools/.uv-XXXXXX")
    archive="$stage/uv.tar.gz"
    curl --fail --location --proto '=https' --retry 3 --connect-timeout 30 \
        https://github.com/astral-sh/uv/releases/download/0.12.19/uv-aarch64-apple-darwin.tar.gz \
        --output "$archive"
    printf '%s  %s\n' a9a8df1eedeb192f2e47e40e2faabfb387db4b850209118786d42f89dde3e0ba "$archive" | shasum -a 256 -c -
    tar -xzf "$archive" -C "$stage"
    mkdir -p "$tool_dir"
    # Another app may finish bootstrapping the same verified tool first.
    if [ ! -x "$tool_dir/uv" ]; then
        cp "$stage/uv-aarch64-apple-darwin/uv" "$stage/uv.ready"
        mv -f "$stage/uv.ready" "$tool_dir/uv"
    fi
    rm -rf -- "$stage"
    stage=''
fi
export PATH="$tool_dir:/usr/bin:/bin:/usr/sbin:/sbin"
export UV_PYTHON_INSTALL_DIR="$support/python"
export UV_CACHE_DIR="$support/cache/uv"
unset PYTHONHOME PYTHONPATH VIRTUAL_ENV CONDA_PREFIX
exec "$tool_dir/uv" run --managed-python --python 3.11 --no-project \
    "$folder/model_manager.py" "$@"
