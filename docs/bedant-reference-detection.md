# Calcium detection, tracking and activity

Open a five-dimensional H5 recording with **File → Open**. The file needs `/data` and an adjacent `metadata.json` declaring its dimensions or axis order. The Video Tracking tab provides detection, coordinate review, resumable ZephIR tracking, and activity export. The original RGBW identification workflow remains available separately.

## Navigate the workspace

The workflow stages are **Detect**, **Track**, and **Review**. **Image settings** holds recording calibration and channel names; activity settings and export are in **Review**. The image, time slider and activity plot remain visible throughout. Slice, Slab (Z ±2), and MIP share fixed per-channel display contrast. **Contrast ▸** changes display only; **Auto once** computes a range from the current volume and retains it across frames.

Choose a preset in the playback FPS menu, or type any rate from **0.1 to 240 FPS**, including fractional rates. Playback follows elapsed time and skips display frames when rendering cannot keep up; the **Display** counter reports the actual rendered FPS. Pausing and frame stepping still allow every frame to be inspected. **Play** advances frames at the requested wall-clock rate; the achieved FPS appears during playback. Rendering speed can limit throughput. Z dragging and numeric Z changes remain available while playing and disable **Follow neuron**. Time seeking pauses playback. Enable **Loop** to expose its bounds; leaving the tab or starting a job stops playback. Rapid seeks are coalesced and frame reads are serialized.

The label dropdown offers no labels, selected, sparse and all labels. **XYZ views** shows crops around the selected neuron. In **Review**, confirm observations, correct centers, exclude measurements or undo recent edits. Undo is bounded to five snapshots and 32 MiB. Save sessions explicitly; do not rely on undo across reloads or tracking/detection runs.

## Detect and review

1. In **Detect**, choose a reference frame, input mode and detection channel(s). The display channel is independent. For Bedant's recording, **C0 is GCaMP**, **C1 is RFP**, and C2 is blank. Frame numbers are one-based; channel numbers are zero-based.
2. In **Image settings**, enter XYZ voxel spacing in micrometers. If spacing is missing, explicitly enable **Use assumed spacing** before detection. The initial `0.4 0.4 1.5` values are model-grid assumptions, not measured calibration.
3. Choose MoE or Spotiflow and press **Auto Detect**. A single selected channel is repeated into the frozen model's four input channels. This adapter requires no training or ground-truth annotations, but GCaMP detection accuracy is not established by the RGBW model's validation.
4. Review the orange candidates. Click a marker or list entry to select it, jump to its Z slice, and edit XYZ. Labels default to **Selected** to avoid overlapping text; **Sparse** and **All** are available. Click coincident markers repeatedly to cycle through nearby neurons. The projection shows all Z positions; the slice shows centers within 1.5 slices. Markers are displayed across image channels so coordinates can be compared against the co-registered second channel.
5. **Accept candidates** retains the seed set. **Add neuron**, then click in the slice image, adds a coordinate. **Delete candidate** removes a candidate; **Delete track** removes the selected neuron from every frame. Use the exclusion checkbox for individual bad frames. Re-detection does not silently replace accepted seeds.

The settings icon beside **Method** retains the packaged MoE score threshold by default. A custom threshold from 0 to 1 only changes which already-proposed candidates are kept; lowering it cannot recover a neuron missed by every expert. Custom thresholds require biological review. This override is disabled for Spotiflow and is saved with the session.

Coordinates are one-based XYZ voxel centers in the supplied image. The crop offset is retained as metadata, not added to coordinates. The selected ROI outline uses the activity radii in pixels; its XY cross-section changes with Z.

### Recommended reference frames

**Reference frames…** starts with the recording's supplied zero-based `t_ref_fn*` indices when present. **Recommend frames** compares at most 128 uniformly sampled frames in the selected channel, using pooled XYZ projections and a greedy correlation-medoid heuristic. Recommendations span image appearances; they do not establish neuron visibility, anatomical identity or tracking accuracy. Blank and spatially constant sampled images are excluded. The original recording and metadata are never changed.

Open a suggested frame, detect, review and accept the first seed set as the primary reference. Additional reference frames must use the **same neuron IDs**. After opening another suggested frame and running detection, **Match neurons…** lets you select a proposal in the viewer and explicitly assign it to an existing neuron. This adds a reviewed constraint at the new frame, retaining the original reference and its IDs. The app does not guess correspondence from spatial proximity. When no proposal matches, choose an existing neuron and **Place center…**, then click its center in the current Z slice. This is also available from **Review → Neuron actions → Match reference neurons…** without running detection. Existing observations require confirmation before replacement; **Undo edit** restores a recent match. **Finish matching** asks before discarding unused proposals while keeping accepted centers.

The recommended list shows reference-center counts and is saved with the session. These counts include accepted or manually reviewed centers; automatic ZephIR positions do not count as reference annotation. Partial additional references are supported: a later frame can constrain only the neurons you can identify confidently. Every tracked neuron must still exist at the primary reference. ZephIR receives these same-ID constraints in the relevant tracking windows, and exports preserve the manually accepted centers exactly. Independent detections in a second frame cannot silently create a second incompatible set of neuron IDs.

Resolve pending candidates before saving a session, importing seeds, loading tracking progress or extracting activity. Saving a session never pretends that unaccepted proposals are accepted tracks. Re-detection asks before replacing existing pending candidates after a successful nonempty result; canceling, a failed run or an empty result keeps the previous proposals and edits. Opening another recording/run or closing a candidate-only session also warns about unsaved work. Loading progress preserves reviewed or confirmed coordinates, names and exclusions made after the checkpoint. Invalid saved settings are checked before a session import changes the live observations.


### Arbitrary multi-channel detection

Choose **Multi-channel**, check any two or more source channels, and set the merge distance in micrometers (default 2 µm). Both MoE and Spotiflow run their existing single-channel inference separately on each selected channel, sequentially. Blank channels are skipped. This is a union of independent detections, not a newly trained joint multichannel model.

Cross-channel matches within the merge distance retain the strongest proposal's center and score. At most one proposal from each channel joins a match, distances are measured against the retained center, and no transitive chain merging is used. Two proposals from the same channel are never combined. A zero merge distance combines only coincident centers. Larger distances can merge distinct nearby neurons, so review the candidates for the recording's calibration and density.

Session settings retain selected channels and merge distance. Detection provenance records all per-channel runs, unmerged centers and scores, retained-source and supporting channels, merge policy, and skipped channels. Annotation `channel` records the channel of the retained proposal and is retained per neuron through tracking and export; support information remains in the detection provenance. Detection channels do not restrict the separately selected tracking or activity channel. Cancellation/failure leaves existing candidates and tracks unchanged; a zero-result run does not change the tracking reference or clear Undo. Saved legacy RGBW sessions retain their original joint RGBW execution path; ordinary new sessions offer Single channel and Multi-channel.

The single-channel adaptation repeats one channel into the frozen RGBW experts. Arbitrary-channel detection inherits that adaptation; its biological accuracy on non-NeuroPAL recordings requires review and has not been established by these engineering checks.


## Track

In **Track**, set the full range, reference frame, tracking channel, frames per window, and epochs. All seed IDs must be present at the reference frame. Detection and tracking channels can differ; using a weak or non-colocalized reference channel can still produce poor tracks.

**Run ZephIR** tracks forward and backward from the reference in windows of at most 100 frames. Adjacent windows share an anchor frame and retain neuron IDs. Each completed window is written to an atomic checkpoint before its temporary image copy is removed. Existing manual coordinates are retained as constraints; propagated boundary coordinates carry their original provenance.

**Cancel** stops the worker tree. **Load progress** imports completed windows, and **Resume tracking** continues the same run. Changed seeds or settings require a new run. After restarting the app, **Open tracking run…** loads `tracking.json` from the saved workspace; the source identity must match. Original H5 data is never modified.

Review tracks at representative times. Trace/heatmap clicks seek to the corresponding frame. Coordinate edits retain the neuron ID. **Exclude this observation from activity** marks a bad measurement without deleting the worldline or silently interpolating its position. Editing positions does not automatically repair later frames: rerun the relevant tracking range using the corrected reference constraints.

## Measure and export

In **Review → Activity settings**, choose:

- Signal channel: normally C0 for GCaMP.
- Optional reference channel: only use a co-registered signal appropriate for normalization.
- Ellipsoid ROI radii in XYZ **pixels** (default `3 3 1`).
- Local background subtraction (enabled by default).
- Baseline percentile (default 20) and motion-warning distance in pixels per frame.

**Extract activity** uses the range in Tracking. Coordinate coverage is shown before extraction. The worker reads original image intensities one frame at a time; it does not measure the contrast-stretched display.

For each frame and neuron:

1. Voxel centers inside the ellipsoid form the ROI. Overlapping voxels belong to the nearest neuron in radius-normalized XYZ coordinates; equal-distance ties go to the lower ID. Thus overlapping ROIs never double-count a voxel.
2. Raw fluorescence is the mean of the assigned voxel intensities. Background is the median in an ellipsoidal shell from 1.5 to 2.5 times the radii, excluding all neuron ROI voxels. Corrected fluorescence is raw minus background. Negative values are retained.
3. F0 is the chosen percentile of finite corrected fluorescence over the selected range. ΔF/F is `(F - F0) / F0`; nonpositive or missing F0 produces NaN.
4. If configured, the reference ratio divides corrected signal fluorescence by positive corrected reference fluorescence. Ratio ΔF/F uses its own percentile baseline. Invalid reference denominators remain NaN.

No bleaching correction, spike inference, temporal interpolation, or automatic biological quality acceptance is performed. Missing or excluded observations remain gaps. ROI size and baseline choices affect the signal and should be reviewed for the experiment. Finite ΔF/F is not a guarantee of trustworthy activity.

The persistent **Activity** plot shows selected-neuron ΔF/F, raw/corrected fluorescence or reference fluorescence. The **Population** button switches to a population heatmap. Changing coordinates, exclusions, measurement settings, or the range marks results out of date; extraction must be repeated before export.

**Export activity + tracks…** copies a complete analysis folder containing:

- `activity.h5`: frame numbers, neuron IDs, original time samples, XYZ centers, raw and background fluorescence per selected channel, corrected signal, F0, ΔF/F, optional ratios, ROI voxel counts, saturation fractions and quality flags. Matrix axes are frame × neuron; H5 attributes record axis conventions.
- `activity.csv`: long-form coordinates and measurements with one row per frame/neuron.
- `quality.csv`: per-neuron counts of measured/finite samples and each quality flag.
- `analysis.json`: source identity, parameters, software hashes, units, flag definitions and provenance.
- `tracks/`: ZephIR `annotations.h5` and `worldlines.h5`, exact `observations.json`, coordinate CSV and provenance.

Flags identify missing/excluded observations, ROI clipping/overlap/empty masks, unavailable background, invalid baselines/reference signals, large coordinate steps, and intensity saturation. They identify review targets; they are not a tracking-accuracy metric.

The UI uses frame numbers. Original `/times` values are exported unchanged; unknown time units are not labeled as seconds. Bedant's supplied images are uint8, so raw fluorescence is in those stored intensity units.

## Save and resume

**File → Save tracking session…** saves accepted observations, exclusions, detection history and the current tracking/activity settings and workspace paths. It creates a fresh directory and does not overwrite earlier exports. **File → Load tracking session…** restores it in an empty reference session. Keep the exact JSON sidecar with the H5 files: ZephIR normalized float32 coordinates alone cannot preserve full coordinate precision.

ZephIR coordinates use `t_idx = frame - 1` and `(coordinate - 0.5) / dimension`. IDs are unchanged. Source metadata and source identity are checked on tracking, extraction, import/export, and checkpoint loading. The source path is part of the identity, so moving a recording requires reopening it and an explicit new workflow rather than silently attaching old coordinates to another file.

## Runtime and resource limits

Set `NEUROPAL_VIDEO_PYTHON` to a Python environment with NumPy, h5py and the application's ZephIR dependencies (`requirements-macos.txt` / `requirements.txt`). Existing local setups also check `NEUROPAL_YOLO_PYTHON` and the sibling `.venv-ai-pipeline` environment. MoE uses its configured bundle and interpreter; install the frozen bundle with `scripts/install_moe_bundle.py`. Weights and recordings are not committed to Git.

The viewer keeps an LRU cache of up to five frames (about 32 MiB for Bedant's recording), targeting a 64 MiB cache budget with at least one frame. MATLAB reads supported H5 filters directly; LZF recordings use a persistent h5py reader that closes with the session and exits if MATLAB disappears. Scrubbing coalesces pending requests so the final requested frame wins. Images, marker groups and activity cursors reuse their graphics handles. The trace is rebuilt only when the selected neuron, plot mode or analysis changes. Frame/chunk reads are limited to 256 MiB; each staged tracking window must fit 1 GiB plus disk reserve. Window sizes are 2–100 frames, with CPU ZephIR and 40 epochs by default. The full recording is processed as multiple windows rather than one large image allocation.

Fluorescence arrays, ROI neighborhoods, worker memory, logs and process lifetimes have explicit bounds. The existing supervisor enforces cancellation and prevents simultaneous heavy jobs. Default workspaces are under MATLAB's `prefdir/NeuroPAL/reference-jobs`. A failed or canceled tracking run preserves its last completed checkpoint and logs.
