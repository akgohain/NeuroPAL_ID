# Paired NeuroPAL and calcium recordings

Open the NWB through **File → Open**. A supported paired file opens its calcium series in Video Tracking. In **Detect**, choose **NeuroPAL reference…** to open the structural volume.

1. **Auto Detect** runs the selected detector on the reference's RGBW channels. Large references use sequential overlapping tiles under the existing detector memory budget. Select a table row to locate its center in both previews; **Remove neuron** removes an unwanted reference candidate.
2. **Auto ID** uses the selected **ID profile** (the recording's DANDI cohort) to identify these detected centers using the installed GAT/transformer checkpoint. It does not read the NWB's published neuron labels or segmentation coordinates. Suggestions carry `auto-id` provenance and a `?` in the viewer. Editing a name marks that name as reviewed; confidence is retained separately from detection and tracking confidence. The current model supplies class suggestions, which can repeat and may not distinguish left/right homologues. Numeric tracking IDs remain unique. Isolated neurons for which the graph model fails stay unnamed and remain available for tracking and manual naming.
3. Choose the structural and video channels with corresponding anatomy and a video reference frame. **Align to video** estimates an image-based translation after either matching image extents or applying voxel spacing. Inspect the mapped centers before **Use aligned seeds**. This supports aligned acquisition axes, scale and translation; it is not an automatic rotation or deformable registration tool. Low correlation or centers outside the recording prevent transfer.
4. In **Track**, choose the tracking channel, frame range, reference frame, window size and epochs, then **Run ZephIR**. Stable numeric IDs retain their anatomical names across windows. Subpixel centers can occupy the full image footprint, from 0.5 to dimension+0.5 in one-based coordinates; genuinely out-of-field coordinates are rejected, and partially clipped sampling regions retain the existing ROI quality flag. In **Review**, inspect trajectories and edit names/coordinates before activity extraction.
5. Extract activity and export. Names, their provenance and confidence accompany the numeric IDs in activity H5/CSV, `identities.json`, and session/track sidecars. Renaming after extraction refreshes exported labels without remeasuring pixels. Changing coordinates or measurement settings still requires extraction again.

The original NWB is read-only. Saved sessions retain the source identity, reference channel mapping, image transform, detection tile metadata, Auto-ID input positions and prediction table, and reviewed names. A different source is rejected when importing a saved session or resuming tracking.

## Supported layout and memory limits

The native NWB reader currently requires one `MultiChannelVolumeSeries` under acquisition, with on-disk axes **T,X,Y,Z,C**. It discovers that dataset by NWB type rather than by a fixed acquisition name. Paired `MultiChannelVolume` references support standard **X,Y,Z,C** and the legacy **C,Z,X,Y** exporter. Four distinct zero-based `RGBW_channels` indices and valid structural spacing are required for paired detection/ID. Ambiguous multiple acquisitions are rejected instead of silently choosing one. Other NWB video layouts are not covered by this reader. The legacy Y,X,Z,C structural layout used in 000692 has not been validated here; this fixture does not establish compatibility with all five Dandisets.

The video is streamed by frame. The frame cache targets 64 MiB, with 256 MiB frame/chunk guards. NeuroPAL RGBW input is limited to 256 MiB; detector tiles retain 12.8 µm of context on each side and use disjoint center ownership plus a 1 µm cross-tile duplicate merge. Each tile runs the frozen pipeline independently, including normalization and routing context. Tiled output is not claimed to be identical to whole-volume inference. Detection succeeds atomically; a failure/cancellation preserves previous reference results.

## DANDI integration fixture

- Dandiset: [000981, published version 0.260910.1747](https://dandiarchive.org/dandiset/000981/0.260910.1747).
- Asset: `004778fe-d596-4012-b3bd-948ce152b80a`.
- Path: `sub-20220630-h6/sub-20220630-h6_ses-20220630_ophys.nwb`.
- Size: 1,200,419,476 bytes.
- SHA-256: `2aec139602f68d6d5bed46d03ddfc50ac19812d4278b85e9461234f793329e1e`.
- Calcium: `(4981,512,400,23,3)` uint16 on disk; 2.66 Hz; reported XYZ spacing `(0.4,0.4,1.5)` µm.
- Structural: `(6,23,1024,800)` uint16, C,Z,X,Y; RGBW indices `(3,1,2,4)`; reported spacing also `(0.4,0.4,1.5)` µm.

The structural image has twice the video's XY dimensions despite the same reported spacing. Matching image extents and then registering structural C0 to video C0 at frame 1 gives a strong image match; do not infer matching coordinate systems merely from the spacing fields. The optical-channel table has more entries than the actual calcium channel axis, so the app leaves those channel names unassigned. Video C2 has signal in frame 1 but is blank in later sampled frames; C0 is used for this integration run.

Published labels and tracks remain in the original NWB but are not used as detector/identity inputs or tracking seeds. This is an engineering fixture, not a held-out accuracy benchmark: the installed model's training set may include this cohort. Inspect Auto-ID suggestions, alignment, trajectories, and ROI settings before interpreting traces biologically.

## Validation

`test_reference_identity_results.m` checks zero/one-based indices, failed graph predictions and malformed result tables. `test_reference_nwb.py` covers axes, channel selection, timing, image alignment, blank/invalid channels, changed-source rejection, and named export round trips. `test_reference_analysis.py` covers name retention across tracking windows and existing fluorescence/checkpoint contracts. `test_named_activity_roundtrip.m` checks exact saved coordinates/names and edited-name exports without modifying the original measurements. `test_paired_neuropal_workflow.m` exercises real detected and identified centers through 25 ZephIR frames across two windows, named activity, a session reload, and renaming after extraction. It requires the local models and downloaded fixture; it does not download data or run implicitly in unit tests.

### Observed results on 21 September 2026

MoE detected 226 centers using two sequential tiles (953.86 seconds on CPU). Auto ID returned 214 provisional class suggestions and 12 unnamed graph failures (72.26 seconds); only 15 predictions had confidence at least 0.5. Image-extent alignment to video frame 1 achieved correlation 0.99674. ZephIR produced 5,650 observations for 226 stable IDs over frames 1–25, across two 13-frame windows at 10 epochs/frame. The rest of the 4,981-frame recording was not tracked in this validation.

Native MATLAB frame reads matched Python exactly at frames 1, 2,491 and 4,981, taking 0.15–0.20 seconds per read with a two-frame cache. The session reopened in a fresh app; exact coordinates, names, identity provenance and current activity survived save/reload. A name edited after measurement appeared in exported H5/CSV and identity metadata while the original activity remained unchanged. Native UI checks covered reference alignment, named selection, Track/Review navigation, contrast and looped playback. Twenty-one Python tests and the MATLAB identity/session integration checks passed.

These results establish the engineering path, not trustworthy biological output. With C0, ROI radii [5,5,1.5] pixels, local background subtraction and a 20th-percentile baseline over this short interval, 91 neurons had nonpositive baselines and only 59.7% of ΔF/F samples were finite. Some tiny positive baselines produced very large ratios. The first two frames were substantially brighter than subsequent frames; default contrast fitted there can obscure later signal. Overlapping ROIs affected 3,782 of 5,650 samples, and flags also recorded clipped/empty ROIs and large steps. Review the centers, identities, alignment, channel, ROI settings and baseline interval before using the traces for analysis. Missing samples remain gaps; no clipping or interpolation was added to make the fixture look better.
