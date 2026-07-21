# NeuroPAL UI development loop

UI changes should be developed against the real App Designer application, not
standalone visual prototypes. The loop is:

1. Make one coherent UI change in source and synchronize `visualize_light.mlapp`.
2. Run deterministic captures of every top-level tab at compact and reference
   viewport sizes.
3. Inspect the PNGs directly and use the JSON manifests to locate components
   with invalid, overflowing, or probably clipped bounds.
4. Compare the capture with the last accepted milestone baseline.
5. Iterate until the screenshots, layout audit, MATLAB Code Analyzer, and app
   drift check all pass.
6. Ask for human review only when the workflow or visual hierarchy changes.
   Spacing, clipping, alignment, and resize regressions belong to this loop.

## Capture the actual application

Unloaded state only:

```sh
scripts/run_ui_audit
```

Unloaded and representative loaded states:

```sh
scripts/run_ui_audit .ui_artifacts/candidate /Users/adamg/neuroPAL/6_mYAa.mat
```

Include a real video-loaded state when changing tracking or video processing:

```sh
scripts/run_ui_audit .ui_artifacts/candidate \
  /Users/adamg/neuroPAL/6_mYAa.mat \
  /Users/adamg/neuroPAL/ZephIR_example_data/neuroPAL_ID_compatible/data.h5
```

Each run produces PNG screenshots and JSON component manifests for every main
tab at 1200x760 and 1400x880. Loaded runs also capture expanded spectral
unmixing and an unsaved processing-preview state; unloaded runs capture the
debug-enabled log layout. `ui-audit.json`
contains the aggregate diagnostics. The output directory is intentionally
ignored by Git.

## Visual regression comparison

Accept a reviewed milestone once:

```sh
python3 scripts/compare_ui_snapshots.py \
  ui_baselines/main .ui_artifacts/candidate --accept
```

Compare later work against it:

```sh
python3 scripts/compare_ui_snapshots.py \
  ui_baselines/main .ui_artifacts/candidate
```

The comparator reports missing screenshots, size changes, changed-pixel ratio,
mean pixel delta, and writes heat-map PNGs. Baseline acceptance is explicit so
an accidental layout regression cannot silently become the new reference.

## Division of responsibility

- Codex owns deterministic launching, direct screenshot inspection, component
  geometry, cross-tab and cross-viewport checks, visual diffs, and iterative
  spacing/alignment fixes.
- The project owner reviews milestone-level product decisions: information
  hierarchy, terminology, and workflow behavior.
- Model quality is kept outside UI acceptance. Stub or cached results should be
  used when a screen requires populated detector/ID output.

## UI change acceptance checklist

- App object remains alive and accessible as `NEUROPAL_DEV_APP` in interactive
  development launches.
- Both compact and reference viewports are captured.
- Unloaded and loaded states are captured when the change touches image,
  processing, detection, ID, or tracking views.
- No new structural layout errors or unexplained warnings appear.
- Visual comparison stays within the intended changed regions.
- `scripts/check_mlapp_drift.py`, `git diff --check`, and MATLAB Code Analyzer
  complete before the change is committed.

`check_mlapp_drift.py` treats the current archive and `.mlapp_extract` as the
authoritative pair. The older `.mlapp_extracted/visualize_light` tree is reported
as advisory because it may lag the current App Designer model. If a single
callback method is missing from the archive, synchronize it without replacing
the current app model:

```sh
python3 scripts/sync_mlapp_method.py MethodName
```
