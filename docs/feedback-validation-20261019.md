# Feedback acceptance — 2026-10-19

The `feedback-fixes` branch contains a split series of **local commits** for
Bedant's and Ev's feedback. Nothing has been pushed. Validation below is on
Apple silicon macOS with MATLAB R2024a, using disposable data copies. This is
a source-validation record. **Delivery sign-off belongs to the separate
`ACCEPTANCE.md` supplied alongside the final ZIP**, with its exact commit,
package hash and fresh-install results. This committed record does not certify
a later ZIP or need rewriting after the package is built.

The evidence root is [release-acceptance-20261019](../../artifacts/release-acceptance-20261019/).
The final package's `catalog.json` and external acceptance report identify the
actual delivered source revision and installation tested.

## Completed checks

| Check | Result | Evidence and scope |
| --- | --- | --- |
| MATLAB engine regressions | **46/46 passed** | [Results](../../artifacts/release-acceptance-20261019/engine/results.json). Annotation transactions/recovery/exchange, missing-model guards, image/axis and NWB contracts, channel isolation, resource/memory policies, tracking adapters, callback lifecycle and App Designer source synchronization. |
| MATLAB main-tab integration | **17/17 passed** | [Results](../../artifacts/release-acceptance-20261019/main/results.json). Inline ID editing, full catalog lookup, captured ownership, conflicts/Undo, geometry-save protection, keyboard/slider/click contracts, method settings and annotation export contracts. These automated checks are separate from native gestures. |
| Python regression suite | **72/72 passed** | [Summary](../../artifacts/release-acceptance-20261019/python-final/regression-summary.json), [pytest log](../../artifacts/release-acceptance-20261019/python-final/pytest.log). Includes frame serving, reference recommendations, selected channels, score policy, interrupted tracking, named activity/export and single-channel NWB axis handling. The overlapping unittest run passed 67 tests; do not add that number to the pytest total. |
| Existing-source smoke checks | **14/14 passed** | [Summary](../../artifacts/release-acceptance-20261019/python/source-summary.json), [source log](../../artifacts/release-acceptance-20261019/python/source-smoke.log). Bounded reads of Bedant H5, original 000541 calcium/static NWB, original 000715 static NWB, CZI metadata, OME-TIFF and MAT fixtures. This is not a native open/inference pass for every file. |
| Package/installer regressions | **19/19 passed** | [Builder tests](../distribution/macos/test_build_package.py), [installer tests](../distribution/macos/test_setup.py). Committed-source inclusion, required annotation assets, corrupt/missing packs, unsafe archive paths, installer reuse/failure recovery, isolated version roots and safe resealing. This miniature-kit suite does not replace a real model installation. |
| Image-processing regression | **12/12 passed** | [Final results](../../artifacts/release-acceptance-20261019/final-processing-formats/results.json). `uint8`, `uint16` and `single` operations; normalization, geometry, spectral processing, session/canvas behavior, recovery, save refusal and legacy orientation defaults. Earlier failed runs are retained for diagnosis; this clean rerun follows the loader and test corrections. Explicit restoration of the original image also passed. |
| App format/process/save/reopen matrix | **12/12 passed** | [Results](../../artifacts/release-acceptance-20261019/final-processing-formats/results.json), [app log](../../artifacts/release-acceptance-20261019/video-formats.log). Real app/API import and processing round trips for CZI, ND2, four OME-TIFF variants, MAT variants and static NWB, including a `uint64` MATLAB image. File identity, first/middle/last planes of every channel and original-image restoration were checked. These are app/API calls, not separate native File-dialog sessions. |
| Original handoff fixture parity | **2/2 passed** | [Strict replay results](../../artifacts/release-acceptance-20261019/fixture-replay/results.json). Original 000541/000715 images reproduced packaged preprocessing arrays exactly; fitted gate/router replay from saved expert predictions returned **166/170** centers, scores and original/MATLAB coordinates within **1e-9**. This checks preprocessing/routing parity; it does not rerun the neural experts. |
| Ev CZI: real detection and Auto-ID | **Passed execution** | [Model results](../../artifacts/release-acceptance-20261019/native/ev-models.json). Native opening/import of Ev's actual CZI, fresh MoE produced **72 centers**, GAT produced **71 nonempty model identities out of 72**. [Progress](../../artifacts/release-acceptance-20261019/native/ev-moe-progress.png), [detections](../../artifacts/release-acceptance-20261019/native/ev-moe-result.png), [GAT result](../../artifacts/release-acceptance-20261019/native/ev-gat-result.png). These counts do not establish correct biological identities. |
| Paired 000541 NWB native open | **Passed** | [Native result](../../artifacts/release-acceptance-20261019/native/paired-nwb.json), [paired NeuroPAL reference](../../artifacts/release-acceptance-20261019/native/paired-neuropal-reference.png). File-dialog opening of the original paired NWB admitted its single-channel calcium recording; Bounded reads of GUI frames **1, 481 and 962** returned the correct 128 × 256 × 21 volume shape. Measured spacing, 0.25 s frame interval and linked static NeuroPAL metadata were retained. This is native I/O/reference acceptance, not a complete named-neuron inference/tracking run on that animal. |
| Native manual ID and restart | **Passed** | [Native log](../../artifacts/release-acceptance-20261019/matlab.log), [restart result](../../artifacts/release-acceptance-20261019/native/restart-result.json). Family typing without assignment, explicit unresolved IL1, exact AVAL, occupied-ID Cancel and atomic Move, durable Undo, full MAT export and complete MATLAB quit/restart/native reopen. Model evidence and annotation journal were unchanged on restart. |
| Native Z/navigation/add | **Passed** | The [native log](../../artifacts/release-acceptance-20261019/matlab.log) records slider/rendered Z agreement, canvas left/right navigation and a native double-click creating a neuron. Detection-overwrite Cancel preserved existing annotations. |
| Bedant connected CPU tracking/activity | **Passed** | [Run report](../../artifacts/release-acceptance-20261019/connected-tracking-native/tp21ac56ba_497d_4af1_9f8b_46f9173e5dde/report.json). **58 IDs × 12 frames = 696 observations**, GUI frames 903–914, reference 907 plus an additional reference at 909, window 5 and **40 epochs/frame**. Native Cancel after two durable windows, checkpoint load, actual resume, named activity/track export and exact session reload passed. Workflow methods drove the connected checks; cancellation was a native click. |
| Video regression and activity rerun | **13/14 initially; remaining case passed on rerun** | [Initial results](../../artifacts/release-acceptance-20261019/video/results.json), [rerun log](../../artifacts/release-acceptance-20261019/video-formats.log). Coordinate safety, reference constraints, marker editing, settings, playback/render serialization, contrast/units and wall-clock playback passed initially. The stale activity-test expectation was corrected; `ACTIVITY_FINAL_RERUN=passed` records its successful separate rerun. The initial JSON still retains its failure and is not presented as a clean aggregate run. |
| Native track center correction | **Passed after fix** | [Native log](../../artifacts/release-acceptance-20261019/relaunch.log), [marker regression](../scripts/test_reference_marker_editing.m). Marker clicks now honor center-correction mode; native correction/Undo preserved exact coordinates and correctly invalidated old extracted activity. Add/correct/Undo, projection and busy-state guards passed. |

The native full annotation export is
[native-annotations.mat](../../artifacts/release-acceptance-20261019/native/native-annotations.mat).
Readback matched the authoritative store, including unresolved candidates,
stable owners, certainty, model evidence and journal. The
[occupied-ID screenshot](../../artifacts/release-acceptance-20261019/native/occupied-id-warning.png)
shows the conflict choice exercised during that session.

The connected Bedant trial completed in **45.82 s**, including native cancellation,
checkpoint loading, resume, two activity extractions, export and exact session
reload; the actual resume took **10.77 s**. It retained all 58 IDs on every frame
and the additional manual reference. About 94.8% of extracted ΔF/F values were
finite. These are software execution/persistence observations, not scientific
quality measures or a whole-recording speed guarantee. Peak memory was not
measured by that report.

Playback uses wall-clock timing and drops display frames when rendering cannot keep up.
The Bedant test advanced its timeline at approximately 2, 30, 60, 141 and
241 frames/s for requests of 2, 30, 60, 144 and 240. Actual display throughput
was about 2–10 frames/s during this test; high requested rates do not promise
that every frame is rendered. The timing table is in `video-formats.log`.

## Delivery checks and declared limitations

Earlier failures remain in the artifacts for diagnosis. The final package report
must distinguish passed source checks, declared unavailable optional methods
and the actual fresh-install results; it must not silently promote a failure
to passing acceptance.

| Gate | Status / required evidence |
| --- | --- |
| Legacy neural detector | **Weights included; inference unavailable without compatible converter support.** Deep Learning Toolbox is licensed, but this R2024a installation lacks `nnet.keras.layer.BinaryCrossEntropyRegressionLayer` from the compatible Deep Learning Toolbox Converter for TensorFlow Models. Converter support is not bundled or verified. [Actual runtime log](../../artifacts/release-acceptance-20261019/video-formats.log) records `REAL_LEGACY_NN_SAFE_DEPENDENCY_GUARD=PASS`: current code rejects the unrestored model safely and explains alternatives. This is not a neural-inference pass. |
| Video reporting | All 14 cases have passing evidence across the initial run and corrected activity rerun. The external package report should retain that distinction and the initial failure record, or link a later clean aggregate run. |
| Fresh delivery package | Record in the final kit's external **`ACCEPTANCE.md`**: versioned committed build, ZIP/file hashes, fresh extraction and versioned installation with empty caches, and fresh MATLAB process/profile launched through `Start_NeuroPAL.m`. No developer model/interpreter overrides. Include the recipient's core manual-ID, supplied-model and reopen/export results. Source-suite results alone do not satisfy this check. |
| Final source and delivery audit | The external package report must record final commit, package version/hash, exact checks and limitations. Verify the root README is unchanged, only intended app changes are committed, `cluster/` is excluded, and no recordings/developer environments were accidentally packaged. No push or external handoff has been performed in this source-validation pass. |

The local commit series separately covers structured annotations, the compact
manual editor, protected model/processing jobs, channelwise detection,
reference matching, NWB movies, keyboard/lifecycle fixes, image-processing
compatibility, marker correction and versioned packaging. Commit the source
validation and final fixes before building; finish delivery sign-off in the
external package report so that acceptance does not require another source
revision and another package rebuild.

## Data and interpretation limits

Bedant's original H5 has shape **(1800, 3, 25, 175, 512)** in **TCZYX** order,
`uint8`. C0=GCaMP and C1=RFP are supplied experiment knowledge; sampled C2 is
zero. The source metadata does not give measured voxel spacing or time units.
Any 0.4 × 0.4 × 1.5 µm model-grid spacing is an explicit assumption, not measured
calibration. Reference recommendations are bounded appearance heuristics, not
proof of neuron visibility or identity.

The original 000541 NWB contains a real single-channel, four-dimensional calcium
recording as well as static NeuroPAL data. Its current bounded source test passes
without losing singleton channel axes. Static 000715, OME-TIFF and MAT fixtures
add channel count, dtype and orientation variation. The completed app/API
format matrix above goes beyond the bounded metadata/source checks. The formerly
used 000981 paired fixture is no longer local and is not claimed as tested in
this pass.

Full manual lookup is independent of model vocabulary: 302 XX individuals,
387 XO individuals and 395 in the union. IL1 exposes all six catalog members
and can remain explicitly unresolved. That fixes annotation availability; it
does **not** prove that Auto-ID can correctly identify an IL1 cell in new data.
Similarly, an optional MoE threshold can retain existing proposals but cannot
recover a neuron that no expert proposed. Bright-cell recall and biological
Auto-ID/tracking/activity accuracy still require reviewed ground truth and
researcher inspection.

The package includes available MoE/GAT/YOLO assets, ZephIR and the existing
MATLAB methods. Separate standalone Spotiflow, custom Cellpose and CRF weights
are missing; their errors and continued manual use must be handled gracefully.
Legacy neural inference requires compatible TensorFlow converter support as well
as Deep Learning Toolbox. The missing Keras import-layer class is safely rejected
on the current licensed installation; the converter is not shipped or verified,
and neural inference is not claimed as validated.
Ultrack and Higher-Order Transformer remain placeholders. Cluster/cloud
submission is out of scope. Windows, Intel macOS, Linux, screen readers and complete 1,800-frame
tracking are not certified by this Apple-silicon acceptance pass.
