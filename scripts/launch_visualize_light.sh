#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

if [ -n "${MATLAB_BIN:-}" ]; then
    matlab_bin="$MATLAB_BIN"
elif [ -x "/Applications/MATLAB_R2024a.app/bin/matlab" ]; then
    matlab_bin="/Applications/MATLAB_R2024a.app/bin/matlab"
elif command -v matlab >/dev/null 2>&1; then
    matlab_bin=$(command -v matlab)
else
    echo "Could not find a MATLAB binary." >&2
    echo "Set MATLAB_BIN or install MATLAB somewhere on PATH." >&2
    exit 1
fi

if [ -z "${NEUROPAL_YOLO_PYTHON:-}" ] && [ -x "/Users/adamg/neuroPAL/.venv-ai-pipeline/bin/python" ]; then
    export NEUROPAL_YOLO_PYTHON="/Users/adamg/neuroPAL/.venv-ai-pipeline/bin/python"
fi

filter_matlab_launcher_noise() {
    if [ "${NPAL_SHOW_MATLAB_STARTUP_WARNINGS:-0}" = "1" ]; then
        cat
    else
        sed \
            -e '/^WARNING: package sun\.awt\.X11 not in java\.desktop$/d' \
            -e '/^FALLBACK (log once): Fallback to SW vertex/d'
    fi
}

"$matlab_bin" \
    -desktop \
    -sd "$repo_root" \
    -r "try, run(fullfile(pwd,'scripts','launch_visualize_light.m')); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); end" \
    2>&1 | filter_matlab_launcher_noise
