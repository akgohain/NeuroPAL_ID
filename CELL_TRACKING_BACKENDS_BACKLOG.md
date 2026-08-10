# Cell Tracking Backends Backlog

## Objective

Add Higher-Order Cell Tracking Transformer (HOCT) and Ultrack as primary cell-tracking backends alongside ZephIR, without coupling the MATLAB UI to any backend's Python API or output format.

Checkpoint-independent integration is now active. Do not install tracker model
caches casually; keep each runtime isolated and verify disk headroom through the
development gate before downloading weights.

## Product model

- HOCT and Ultrack are segmentation-driven trackers. They require labeled masks or foreground/contour evidence across time.
- ZephIR remains the sparse, user-seeded point-tracking option.
- Present all three through one tracking-job UI with backend-specific prerequisites and settings.
- Preserve lineage, confidence, and provenance even if the initial worldline UI only displays flattened tracks.

## Proposed common contract

### Inputs

- Lazy video source and selected image channels.
- Spatial and temporal scale metadata.
- Segmentation source: cached Cellpose masks, imported labels, or backend-appropriate foreground/contour maps.
- Backend name and validated backend-specific configuration.
- Output/cache directory and resume policy.

### Results

Use a backend-neutral observation table containing at least:

```text
track_id, parent_id, t, z, y, x, confidence, provenance
```

Retain optional label masks and native output as sidecars. GEFF is the preferred graph interchange format where supported. Adapt the canonical observations into the existing `video_neurons`, ROI, `annotations.h5`, and `worldlines.h5` paths.

## Implementation phases

### 0. Prerequisites

- Reclaim enough storage for isolated Python environments, model weights, segmentation caches, and test output. Target at least 8-10 GiB free before starting.
- Create a Python 3.11+ runtime isolated from the legacy Python 3.9 ZephIR/TensorFlow environment. Prefer an external `uv`-managed process rather than MATLAB's embedded Python runtime.
- Add preflight checks for runtime, packages, model weights, writable cache space, solver availability, and estimated output size.
- Validate an open-source solver path on this machine. The installed Gurobi license expired on 2026-05-09.

### 1. Backend-neutral tracking jobs

- [x] Add a stable backend registry and expose ZephIR, Ultrack, and HOCT in the tracking tab with honest readiness states.
- [x] Define and test versioned request and canonical observation contracts.
- [x] Validate bounds, unique track/frame observations, confidence, provenance, consistent parents, missing parents, and lineage cycles.
- [ ] Introduce a MATLAB job controller with start, progress, structured logs, cancellation, timeout, failure reporting, and resume support.
- [ ] Serialize the validated request/result contracts as worker JSON/CSV manifests.
- Run workers as external processes so environments remain isolated and jobs can be cancelled reliably.
- Make result import transactional: validate dimensions, axes, frame bounds, and IDs before mutating app state.

### 2. Segmentation substrate

- Extend Cellpose from static centroid production to streaming 4D integer-label mask generation.
- Support imported integer masks and Ultrack foreground/contour arrays.
- Cache masks chunkwise rather than materializing a complete large video in memory.
- Record segmentation parameters, source channels, voxel scale, software/model versions, and per-frame failures.
- Add visual mask review before launching a tracker; tracking quality cannot recover consistently missing or merged detections.

### 3. Ultrack integration

- Integrate Ultrack first because its pipeline is mature, disk-backed, resumable, and supports segmentation uncertainty.
- Force and test the CBC solver while Gurobi is unavailable; expose solver choice and timeout in diagnostics, not as a casual UI tuning control.
- Map selected tracks and lineage into the canonical result contract.
- Validate first on a short crop, then the canonical 512-frame H5 fixture.

### 4. HOCT integration

- Reuse the same integer-label segmentation cache.
- Use the published pretrained model initially; pin the exact package/model version and verify downloaded weights.
- Prefer Apple MPS for transformer inference with CPU fallback.
- Explicitly verify SCIP or another open solver path. HOCT declares `gurobipy`, and an installed-but-unlicensed Gurobi must not cause runtime failure.
- Treat HOCT as experimental until it passes worm-specific validation; the public project and paper are new as of July 2026.

### 5. Cell Tracking tab redesign

- Replace the ZephIR-only action with backend cards or a selector for HOCT, Ultrack, and ZephIR.
- Show prerequisite readiness and segmentation source before enabling Run.
- Provide shared Run, Cancel, Resume, progress, logs, output location, and result-review controls.
- Keep backend-specific parameters in an advanced section with safe presets.
- Overlay tracks, gaps, low-confidence links, appearances/disappearances, and lineage events for review.
- Allow accepting all results or selected tracks without overwriting unrelated manual work.

### 6. Validation

- Smoke-test axis conventions and import/export on synthetic 2D and 3D sequences with known tracks.
- Stress-test H5/NWB/ND2 lazy access, cancellation, disk-full behavior, corrupt caches, missing frames, and worker crashes.
- Use the local 512-frame H5 video for long-run performance testing.
- Acquire at least one annotated public tracking dataset for quantitative regression tests; the current local videos do not include ground-truth trajectories.
- Compare HOCT, Ultrack, and ZephIR on worm-appropriate cases rather than treating general Cell Tracking Challenge performance as sufficient validation.

## Current readiness

| Component | State |
| --- | --- |
| Lazy H5/NWB/ND2/TIFF video access | Available |
| Long local video fixture | Available |
| Existing ROI/worldline import path | Mostly reusable |
| External Python worker precedent | Available |
| `uv` runtime manager | Available |
| Python 3.11+ tracker environment | Deferred/not installed |
| 4D segmentation masks | Major missing dependency |
| Backend-neutral tracking UI | Selector and readiness states implemented; workers remain disabled |
| Versioned tracking contracts | Implemented and synthetic-tested |
| Lineage/confidence representation | Canonical validation implemented; legacy import remains pending |
| Ground-truth trajectories | Not available locally |
| Commercial solver | Gurobi license expired |
| Storage headroom | No longer an immediate blocker in the 2026-08-10 audit; continue preflighting before installs |

## Upstream references

- [HOCT paper](https://arxiv.org/abs/2607.11754)
- [HOCT implementation](https://github.com/royerlab/hoct)
- [Ultrack paper](https://arxiv.org/abs/2308.04526)
- [Ultrack implementation](https://github.com/royerlab/ultrack)
- [Ultrack documentation](https://royerlab.github.io/ultrack/)
- [TracksData](https://royerlab.github.io/tracksdata/)

## Optional later experiment

After both backends work independently, evaluate a hybrid in which Ultrack supplies or selects segmentation hypotheses and HOCT scores temporal associations. Do not make this coupling part of the initial integration.
