# Detection and Auto-ID Integration

This document defines the product boundary between NeuroPAL_ID and the
experimental methods in
[`neuropal_id_benchmarking`](https://github.com/akgohain/neuropal_id_benchmarking).
The initial product mapping was reviewed against benchmark commit
`c00c85f4e7e99c43d2ac8e6949081b91928e27bc` on 2026-07-21.
The benchmark repository remains the source of truth for training, evaluation,
environment locks, and method selection. This application owns interactive
inference, review, correction, and persistence.

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
| Detection | YOLO INF2 | Recommended portable learned detector. The benchmark reports held-out F1@5um 0.7117. |
| Detection | Matching Pursuit | MATLAB-only fallback and continuity path. |
| Detection | Legacy neural network | Compatibility fallback. |
| Detection | Cellpose custom model | Advanced adapter for users who already have compatible local weights. |
| Identity | Anshita GAT | Primary learned auto-ID adapter. The geometry benchmark reports top-5 0.9382. |
| Identity | Atlas likelihood | Explicit legacy MATLAB fallback, not presented as the benchmark winner. |

Only runnable registry entries appear in the GUI. A method being benchmarked is
not sufficient: it also needs a portable adapter, obtainable weights/assets,
bounded resource behavior, actionable dependency checks, and a verified result
import path.

The GAT adapter resolves assets from explicit settings first, then
`NEUROPAL_GAT_REPO`, `NEUROPAL_GAT_CHECKPOINT` (or the legacy transformer
environment variable), and finally workspace-relative locations. No
machine-specific absolute path is part of the default contract.

## What is scaffolded next

1. **Spotiflow NeuroPAL detector** — best single held-out detector in the
   benchmark (F1@5um 0.8125). Package its selected checkpoint and preprocessing
   as a volume-to-centroid adapter before making it selectable.
2. **CRF Cell-ID 2.0** — strongest locked identity row (top-1 0.8128, top-5
   0.9550). The adapter must package the selected atlas/unary configuration and
   remove cluster- and checkout-specific paths.
3. **Accurate detection ensemble** — Spotiflow backbone plus YOLO/nnU-Net
   consensus rescue. The locked benchmark reports F1@6um 0.9233. This should be
   an optional high-resource profile, not the default desktop path.

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
