# Calcium reference detection and ZephIR seeds

Use **File → Open** to select a five-dimensional H5 recording with `/data` and adjacent `metadata.json`. The Video Tracking tab opens a reference workspace. Existing NeuroPAL RGBW detection remains available in the identification workflow.

## Workflow

1. Choose a one-based **Frame** and a zero-based source **Channel**. Bedant's recording uses **C0 = GCaMP**, **C1 = RFP**; C2 is blank. The selected channel supplies both the preview and inference input.
2. Enter XYZ voxel spacing in micrometers. If the metadata does not supply `spacing_um_xyz`, explicitly check **Use assumed spacing** before detection. The initial `0.4 0.4 1.5` values are model-grid assumptions, not measurements of this recording.
3. Run **Detect frame**. MoE runs the three frozen fold-00 experts and router; Spotiflow runs the corresponding frozen expert alone. A single selected channel is repeated into the model's four input channels. This is an inference adapter; these NeuroPAL-trained models have not been validated for GCaMP accuracy.
4. Inspect orange candidates across Z. **Accept candidates** moves them into the editable table. Edit XYZ coordinates there; click in the image then **Add at last click**, or select table rows and **Delete selected**. Re-detection never silently replaces accepted seeds. Discard candidates or delete the existing seeds before accepting a replacement for the same frame/channel.
5. **Save seeds** creates a new subfolder containing `annotations.h5`, `worldlines.h5`, `centers.csv`, exact `observations.json`, and `provenance.json`. Load `annotations.h5` in an empty reference session to resume. Keep these files together to preserve exact coordinates, channel information, scores and source identity.
6. Choose a short inclusive tracking window containing the reference frame and press **Track window**. This creates an isolated ZephIR dataset containing only the selected channel and window. The run uses CPU, 40 epochs and a linear frame order. It imports resulting observations into the table with the original frame numbers and worldline IDs. Save again to export the resulting observations. New tracked positions carry `zephir` provenance and score 0 (unscored); reviewed seed scores are retained.

The first tracking milestone is deliberately limited to **100 frames per run**. It does not launch a full 1,800-frame tracking job or claim biological tracking accuracy. Use a complete reviewed reference set in the window; independently detected frames receive new IDs and are not automatically identity-matched.

## Data and coordinates

- Native `TCZYX` and MATLAB-written `TCZXY` layouts are resolved using explicit `axis_order` or matching `shape_t/c/z/y/x` metadata. Conflicting or missing shape metadata is rejected.
- MATLAB previews are YXZ; table/CSV coordinates are one-based XYZ pixel centers. The frame control is one-based; channel labels use the source's zero-based numbering.
- ZephIR H5 uses `t_idx = frame - 1` and normalized centers `(coordinate - 0.5) / dimension`. Worldline IDs remain unchanged. Float32 H5 normalization is paired with exact JSON coordinates for lossless app round-trips.
- Coordinates refer to the supplied cropped image. `crop_box_yxyx` is retained as metadata, not silently added to coordinates.
- Unknown voxel spacing and `/times` units remain unknown in source provenance. An assumed model spacing is recorded with the detection request.
- Source data and metadata are read-only. Export creates a fresh directory; tracking runs in a separate directory and preserves original time samples for its window.

## Runtime and resource limits

The viewer caches one frame (about 6.4 MiB for this recording). Z and channel navigation reuse it. Frame reads, inference and tracking use the existing supervised Python process runner, cancellation and memory limits. Frames or individual H5 chunks larger than 256 MiB are rejected by this reference reader. Tracking windows must fit a 1 GiB staging budget, with a disk-space reserve checked before copying. Failed jobs preserve accepted annotations.

Set `NEUROPAL_VIDEO_PYTHON` to a Python environment with NumPy, h5py and the application's ZephIR dependencies (`requirements-macos.txt` / `requirements.txt`). For existing local setups the viewer also checks `NEUROPAL_YOLO_PYTHON` and the sibling `.venv-ai-pipeline` environment. MoE uses its configured method bundle and `NEUROPAL_MOE_PYTHON` or the bundle's interpreter. Install the frozen bundle with `scripts/install_moe_bundle.py` and its `requirements-moe.txt` environment. Model weights and example recordings are not committed to the repository.

Default job output is under MATLAB's `prefdir/NeuroPAL/reference-jobs`. Detector output includes the request, transform, scores, expert predictions, logs and resource records. Track output includes staged input, ZephIR files and source-frame/channel mapping.

## Validation

- `scripts/test_reference_video.py`: native/legacy layout, axis markers, normalized-coordinate and exact sidecar round-trip, identity preservation, invalid indices, metadata mismatch and source-change rejection.
- `scripts/test_single_channel_moe.py`: channel isolation, RGBW input preservation, blank/nonfinite/mismatched input and memory preflight.
- `scripts/test_reference_workflow.m`: actual app callbacks on the supplied recording, blank C2, C0 detection, acceptance, editing, save/reload and a three-frame ZephIR run.
- Existing MoE fixture replay and app development checks remain regression checks.

Example MATLAB invocation after launching the app:

```matlab
addpath('scripts');
test_reference_workflow(Program.app, '/path/to/Test Image/data.h5', '/path/to/test-output');
```
