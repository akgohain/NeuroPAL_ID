#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

log_dir="$repo_root/logs"
mkdir -p "$log_dir"
timestamp=$(date +"%Y%m%d_%H%M%S")
log_path="$log_dir/neuroPAL_debug_${timestamp}.log"

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

echo "NeuroPAL debug log: $log_path"
echo "Reproduce the issue, then close MATLAB and send me that log."

NPAL_DEBUG=1 NPAL_DEBUG_LOG="$log_path" \
exec "$matlab_bin" \
    -desktop \
    -logfile "$log_path" \
    -sd "$repo_root" \
    -r "fprintf('Launching NeuroPAL_ID from %s\\n', pwd); try, run(fullfile(pwd,'scripts','launch_visualize_light.m')); catch ME, disp(getReport(ME,'extended','hyperlinks','off')); end"
