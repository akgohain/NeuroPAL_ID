# Detection and Auto-ID Integration

This document defines the product boundary between NeuroPAL_ID and the
experimental methods in
[`neuropal_id_benchmarking`](https://github.com/akgohain/neuropal_id_benchmarking).
The initial product mapping was reviewed against benchmark commit
`c00c85f4e7e99c43d2ac8e6949081b91928e27bc` on 2026-07-21. The detector
selection was refreshed from `Yemini-Lab/GAT-NeuroPAL` PR #1 at commit
`46e7ef4e67519cce7bb13d13bc215ebb9147541c` on 2026-08-18.
The benchmark repository remains the source of truth for training, evaluation,
environment locks, and method selection. This application owns interactive
inference, review, correction, and persistence.

## September 2026 nonlinear MoE integration

The app now includes an experimental nonlinear MoE adapter for the coherent
fold-00 handoff from GAT-NeuroPAL PR #2 at
`2276e61dedf9671740c1a36fab7d6d976b86de37`. This supersedes the ensemble
scaffolding status below, which describes the earlier consensus implementation.
See [MOE_INTEGRATION.md](MOE_INTEGRATION.md) for setup and measured validation.
The earlier cross-dataset model-selection notes describe a different study;
fold 00 has not been selected as a production model.

## Product workflow

The first tab follows one explicit sequence:

1. Open and validate a multichannel NeuroPAL volume.
2. Detect neuron centers (and masks when the adapter provides them).
3. Assign ranked identities to the detected neurons.
4. Review low-confidence predictions and make manual corrections.
5. Save the corrected annotation state or export it.

Detection and identity are separate stages. A detector must never silently
choose identities, and an identity model must consume the currently reviewed
set of neuron centers rather than rerun detection behind the user's back.

## What is exposed now

| Stage | Method | Product role |
| --- | --- | --- |
| Detection | Spotiflow NeuroPAL v1 | Recommended frozen detector. Four-view TTA, complete-linkage fusion, and the validation-selected 0.185 operating threshold are reproduced from GAT-NeuroPAL PR #1. |
| Detection | YOLO INF2 | Portable learned fallback. The historical benchmark reports held-out F1@5um 0.7117. |
| Detection | Matching Pursuit | MATLAB-only fallback and continuity path. |
| Detection | Legacy neural network | Compatibility fallback. |
| Detection | Cellpose custom model | Advanced adapter for users who already have compatible local weights. |
| Identity | Anshita GAT | Primary learned auto-ID adapter. The geometry benchmark reports top-5 0.9382. |
| Identity | Atlas likelihood | Explicit legacy MATLAB fallback, not presented as the benchmark winner. |
| Identity | CRF Cell-ID 2.0 | Complete request/import transaction and bundle slot; selectable now and becomes runnable when the selected atlas, unary model, and adapter are supplied. |

Runnable adapters appear in the GUI. Checkpoint-backed adapters may be visible
before their large assets are installed, but the tab marks them as requiring a
bundle and blocks inference with actionable setup guidance. A method being
benchmarked is not sufficient: it also needs a portable adapter, a validated
bundle contract, bounded resource behavior, actionable dependency checks, and
a verified result import path.

The GAT adapter resolves assets from explicit settings first, then
`NEUROPAL_GAT_REPO`, `NEUROPAL_GAT_CHECKPOINT` (or the legacy transformer
environment variable), and finally workspace-relative locations. No
machine-specific absolute path is part of the default contract.

## Checkpoint-independent scaffolding completed

1. **Spotiflow NeuroPAL v1 detector** — the app reproduces the frozen
   identity/X/Y/XY reflection views, 2 um complete-linkage merge,
   confidence-weighted coordinates, support-calibrated score, 0.185 operating
   threshold, deterministic execution, checkpoint hash verification, centroid
   import, progress, and provenance contract from GAT-NeuroPAL PR #1. The
   142 MB checkpoint directory and isolated Spotiflow 0.6.5 environment are the
   remaining external inputs.
2. **CRF Cell-ID 2.0** — the app now exports reviewed YXZ centroids, physical XYZ
   coordinates, RGBW values, scale, and bundle configuration to a stable request.
   It validates the adapter's ranked output and applies it transactionally. The
   selected atlas/unary assets and production adapter implementation remain to be
   placed in the bundle.
3. **Accurate detection ensemble** — the historical Spotiflow-backbone plus
   YOLO/nnU-Net consensus-rescue fusion rule is implemented and contract-tested.
   It is intentionally not selectable yet: full in-app orchestration still needs
   the nnU-Net inference adapter and all three expert bundles. The locked
   benchmark reports F1@6um 0.9233. It is retained as an experimental route,
   not the default: upstream nested leave-dataset-out validation favored the
   frozen four-view Spotiflow detector over fixed consensus and the nonlinear
   router.

Each method uses `method_bundles/<method_id>/method_bundle.json`. The committed
example manifests document artifact roles and configuration; large checkpoints
stay outside Git. A bundle can instead be selected in the method Settings dialog
or resolved through the environment variables documented in
`method_bundles/README.md`.

Current Cellpose-SAM/DINO, nnU-Net, micro-SAM, Omnipose, and image-first methods
remain benchmark or specialist options until their environment and artifact
contracts are portable enough for an honest in-app readiness check.

## Stable adapter boundary

`Methods.MethodRegistry` records the product name, stable method ID, task,
readiness, input/output contract, and concise benchmark evidence. Experimental
run IDs and paths do not belong in GUI callbacks.

External detector adapters return a MATLAB table in physical coordinates:

```text
x_um, y_um, z_um, score
```

They may append fields such as `mask_path`, `source_id`, or uncertainty, but
the required columns are validated by `Methods.MethodContract.detection`.
Coordinates are converted to the app's internal pixel/YXZ representation in a
single importer, never independently by each GUI callback.

External identity adapters return at least:

```text
neuron_idx, predicted_class, confidence
```

Optional ranked fields such as `top5_classes` and `top5_probs` remain supported.
`Methods.MethodContract.identity` validates the shared minimum schema before
predictions mutate application state.

## Adapter promotion gate

A scaffolded method becomes runnable only after all of these pass:

- weights/assets resolve without a lab-specific absolute path;
- dependency probing fails with actionable instructions;
- a fixture inference run emits the stable result contract;
- coordinate/channel semantics are checked against a known NWB fixture;
- cancel, timeout, disk-full, and subprocess-failure paths leave app state intact;
- result import is transactional and preserves the previous annotations on failure;
- the real-app UI audit covers unloaded, ready, running, success, empty-result,
  and failure states;
- the packaged configuration points to a locked benchmark result and documents
  whether train or validation labels informed it.

This keeps the benchmark exploratory and the application boring—in the useful
sense that every visible option is expected to work.
