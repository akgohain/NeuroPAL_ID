# Performance engineering

This branch addresses predictable allocation spikes, repeated rendering work,
and worker lifetime management. Bedant's channel-specific detector integration
is separate work. The September RAM incident did not have a stage-level trace;
these changes do not establish a single historical root cause.

## Memory and responsiveness

- Main display retains the current RGB plane and a maximum projection, both
  uint8. It composes one plane at a time and invalidates cached projections when
  source pixels or display settings change. Raw image pixels remain resident.
- MAT loading reads named app fields rather than unrelated saved variables.
  Processing can read v7.3 MAT planes without opening the full image first.
  Main loading has a configurable native-pixel ceiling. CZI companion paths now
  replace only the file extension, preserving directory names. Older MAT versions have
  explicit limits because MATLAB cannot read their arrays incrementally.
- Detector color readout computes channel statistics in bounded passes and
  samples only neuron centers instead of retaining a full double z-score array.
- Histogram matching can return uint8 directly. The original uint64 default
  remains available for callers that require it. Numerical contracts compare
  the new path against the original algorithm, including CDF ties.
- Legacy neural detection predicts one tile at a time. Auto-ID cleans up its
  own futures/pools and preserves a pool supplied by the user.
- H5 video dragging coalesces pending events and reads the latest XY slice.
  Release refreshes full projections and overlays. MIP/last-ID modes preserve
  their display semantics by refreshing on release. The projection cache has
  a byte limit and source/request identity. Non-H5 full refresh still uses the
  existing full-frame reader.
- Main illustration export streams planes/patches. Legacy dialogs that require
  a complete RGB stack use a budgeted compatibility path.
- UI logs are bounded, reopen replaces owned listeners, and app close releases
  owned timers/listeners.

## Files and workers

NWB export binds datasets to disk before streaming planes. It no longer grows
an in-memory uint64 movie through DataPipe appends. New outputs are published
only after successful validation. Existing datasets are copied out of core.
See [LARGE_FILE_IO.md](LARGE_FILE_IO.md) for uint16 conversion, floating-point
normalization, source-change checks, and library-call cancellation limits.

Lazy processing writes a same-directory partial, validates it, then publishes
an unused output filename. Cancellation/failure preserves the source and prior
results; app state changes only after publication.

`Program.HeavyJob` and `+Wrapper/resource_control.py` share an OS-released job
lease. The detector/Transformer MATLAB Python runner uses argument arrays, bounded log tails, live
progress, cancellation, timeout, and process-tree cleanup. The supervisor
records per-process RSS and stops its own job if its configured memory ceiling
or the machine-headroom floor is reached. Process-tree RSS sums shared pages
more than once; it is an admission/diagnostic measure, not physical-memory
accounting. Sampling cannot guarantee prevention of every allocation spike.
Polling also cannot guarantee descendant cleanup after a supervisor is forcibly
killed or a child reparents between samples; process groups/Windows Job Objects
would provide stronger containment.

MoE preprocessing exits in a separate process before sequential experts run.
The routing process uses a memory-mapped prepared input. Metadata preflight
rejects oversized requests before allocation, and proposal counts bound the
estimated association workspace. Weights, thresholds, preprocessing math, and
coordinate transforms are unchanged.

## Configuration

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `NEUROPAL_IMAGE_MAX_MIB` | 512 | Main native-pixel payload ceiling, not total peak memory |
| `NEUROPAL_VIDEO_CACHE_MIB` | 32 | Retained video projection cache; capped at 256 MiB |
| `NEUROPAL_MAX_JOB_MIB` | 6144 | Supervised process-tree RSS ceiling |
| `NEUROPAL_MOE_WORKSPACE_MIB` | 4096 | Estimated MoE workspace admission ceiling |
| `NEUROPAL_ROUTER_MIB` | 512 | Estimated router association workspace ceiling |
| `NEUROPAL_JOB_LOCK` | OS temporary directory | Shared lock path; use the same path across app/worker processes |

Windows worker supervision requires `psutil`. Runtime validation in this sweep
uses macOS ARM64, MATLAB R2024a, and CPU inference. Windows/Linux behavior and
CUDA should be validated on their target hosts before release. Artifact retention
still follows each wrapper's `KeepArtifacts` option; there is no automatic disk
retention quota.

## Validation

The final development gate passed, including 19 worker-resource tests, six
archive contracts, and the MATLAB suites below. Archive comparison confirmed
that only `matlab/document.xml` changed; `appModel.mat` and other members are
identical. Optional comparisons against ignored extracted-source folders were
skipped because those folders are absent in this worktree.

Run `scripts/run_dev_cycle fast` for the existing app contracts plus bounded
performance contracts. MATLAB is supervised and serialized with inference.
The model-independent MATLAB suite can also be run directly:

```matlab
addpath('scripts');
test_performance_contracts;
```

Run the real-model acceptance separately with the installed bundle/interpreter:

```matlab
setenv('NEUROPAL_MOE_PYTHON', '/path/to/environment/bin/python');
addpath('scripts');
test_moe_app('/path/to/bundle', '/path/to/new/output');
```

Prefer launching these commands under `+Wrapper/resource_control.py --report
/path/to/resources.jsonl -- /path/to/matlab -singleCompThread -batch ...` so the
whole MATLAB/worker tree is measured. Do not run real-model and full-app tests
in parallel on the development machine.

Measured on the local 16 GiB Mac:

- Both annotation-free fixture preprocess arrays match exactly. Saved-expert
  gate/router replay yields 166 and 170 detections with maximum numerical error
  below 1e-9.
- Full CPU inference on 000715 yields 169 detections, with zero center/score
  difference against the previous CPU output. This is not a claim of exact
  CPU/CUDA parity. Its isolated supervised run peaked at 3,115,888 KiB summed RSS.
- Real app open/import/edit/save of the same 169 saved detections passed.
  The 218×905×39 fixture retained 1,183,740 display-pixel bytes (two planes).
  The final handle/zoom/label regression test passed with slice p95 0.227 seconds
  across 60 updates. Startup was 24.5 seconds. The earlier 30-update run measured
  0.296 seconds; these are separate runs, not a controlled speedup experiment.
- Actual app-button MoE inference, coordinate import, edit, save and reload
  passed with 169 centers. Centers/scores exactly match the isolated CPU run.
  The combined app/worker test peaked at 3,768,112 KiB summed RSS.
- Original CZI conversion, repeated opening, video navigation, and the Save
  false-result check passed. First conversion/open took 26.7 seconds; reopening
  took 2.3 seconds. The combined test peaked at 3,041,776 KiB summed RSS. The CZI
  path uses the existing Python fallback here; the isolated worktree reuses the
  existing local `venv` through an ignored symlink. No models were retrained.
- The existing MAT companion contains 250,521,600 raw pixel bytes and retained
  4,294,656 display-pixel bytes. Opening it took 12.2 seconds, then 2.6 seconds
  on repeat. The 512-frame H5 fixture opened in 0.75 seconds; ten full video
  refreshes had p95 0.333 seconds.

Reports and screenshots from this development run are under
`/Users/adamg/neuroPAL/artifacts/performance-sweep/`. CZI measurements are included below. These timings
are fixture/machine measurements, not performance guarantees or a controlled
before/after speedup benchmark.

## Remaining limits

This is not a fully out-of-core main editor. Main pixel storage is still numeric;
non-H5 video refresh uses a whole frame. Static Bio-Formats, LIF, VLab H5 and
Python CZI imports now check decoded dimensions against the image payload ceiling
before reading pixels. Generic, CZI and legacy ND2 Bio-Formats imports read the
first series one plane at a time; LIF checks the selected series. Static readers
require one time point and separate channel planes; Bio-Formats uses its channel
separator before this check. NWB/ND2 and lazy MAT processing retain their dedicated bounded paths.
This is a payload admission check, not a total-memory guarantee: codec buffers,
MATLAB's current image, and later conversion copies still contribute to peak RAM.
Full-volume legacy algorithms
and unsupported lazy operations still need separate algorithm-specific work.

Dense per-frame tracking ROI storage remains unchanged. Tracking conversion now
uses typed columns, and annotation imports no longer allocate a temporary array
through every preceding frame for each observation.

UI guards cover supported mutation entry points and use small source/annotation
snapshots before committing model output. They intentionally do not hash image
pixels or prevent direct low-level script mutations. Tests cover real cancellation
of processing transactions and the Save false-result branch separately. Real
Parallel Toolbox pool ownership and legacy NN model execution were not exercised;
those resource contracts use controlled fixtures. App startup remains about
25 seconds on this machine.

## Import admission follow-up

- Replaced eager `bfopen` calls in static image readers with metadata inspection
  and sequential planes. ND2 channel-name lookup now reads metadata only.
- The Python CZI fallback checks dimensions before decoding, decodes one subblock
  at a time into a temporary memory map, and writes H5 planes sequentially. MATLAB
  reads those planes into the final array without a full-volume transpose copy.
- CZI fallback runs through the worker supervisor and inherits MATLAB's current
  `NEUROPAL_IMAGE_MAX_MIB` setting. Its temporary pixel file is owned by MATLAB's
  cleanup handler as well as Python, including when the worker is terminated.
- LIF preallocates its native array and closes its reader on every exit. The
  selected series is now passed to `setSeries`, rather than treated as time.

Validation: `scripts/test_import_memory.m` checks admission, synthetic Bio-Formats
plane assembly, and time-series rejection. `scripts/test_czi_import.py` checks
rejection before decoding, disk-backed conversion equality and scratch cleanup.

The real CZI fallback fixture (1536 × 466 × 25 × 7, 239 MiB of uint16 pixels)
loaded in 6.8 seconds. All 175 channel/Z planes matched the previously saved MAT
exactly, including orientation. A forced fallback also rejected the source under
MATLAB's reduced image limit. The supervised load-plus-comparison run peaked at
1,308,336 KiB summed RSS; this is fixture evidence, not an arbitrary-input ceiling.
Artifacts: `/Users/adamg/neuroPAL/artifacts/performance-sweep/import-hardening/`.
