# Detector and Auto-ID Backlog

## Cellpose-family detector support

- Add selectable Cellpose-SAM and Cellpose-DINO detector modes alongside the existing local Cellpose wrapper.
- Treat these as Cellpose-family backends in the UI, but keep model/runtime-specific hyperparameters separate from traditional Cellpose.
- Preserve mask artifact export so the existing main-view mask overlay can display each backend's masks.

## YOLO INF2 integration

- Keep MATLAB as the UI/import layer and call the trusted Python YOLO INF2 snapshot as a subprocess.
- Default app parameters should follow the corrected-GT best row:
  - confidence: 0.60
  - image size: 512
  - slice stretch: p0.5-p99.5
  - IoU minimum: 0.50
  - max fused dz: 1
  - depth sanity ratio cap: 2.0
  - no length/width filter by default

## Anshita/GAT auto-ID integration

- UI should refer to the checkpoint as Anshita GAT, not generic Transformer.
- The checkpoint directory name may contain `transformer`, but `train_config.json` uses `model_type: gat`.
- Preserve the DANDI `000981` RGBW channel-base special case from the handoff bundle.
