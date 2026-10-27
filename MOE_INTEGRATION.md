# MoE detection

The app runs the coherent fold-00 model bundle from GAT-NeuroPAL commit
`2276e61dedf9671740c1a36fab7d6d976b86de37`. It performs annotation-free image
preprocessing, Spotiflow four-view inference, YOLO slice inference and fusion,
3D heatmap inference, appearance scoring, candidate association, and frozen
nonlinear routing. It does not fit models or choose thresholds on a new image.

## Installation

1. Unpack the verified `neuropal_moe_handoff_fold00_20260911.zip` outside Git.
2. Create a dedicated Python 3.11 environment and install `requirements-moe.txt`.
3. Supply the three hash-matched YOLO scripts listed by
   `scripts/install_moe_bundle.py`. The original handoff omitted these files;
   the installer copies them into `app_support/yolo_inf2` and verifies their
   upstream hashes. Both the inference/fusion scripts and their base helper
   are required.
4. Run:

   ```sh
   python scripts/install_moe_bundle.py /path/to/handoff \
     --python /path/to/environment/bin/python \
     --yolo-source /path/to/yolo/scripts \
     --yolo-source /path/to/base/helper
   ```

5. Open **Tools → Models & runtimes…**, select **MoE detection**, choose the
   handoff directory and the Python executable, then click **Apply**. The app
   validates the bundle and runtime before saving the selection. Existing methods
   package installations are discovered automatically; no environment-variable
   setup or particular workspace folder layout is required.

Large models and example datasets remain outside the application repository.
The original checksums/provenance remain intact; app support and the installed
`method_bundle.json` are additions. Runtime verifies the original models,
configuration, provenance, source, and added YOLO scripts before inference.

## App usage

Open a native-intensity NeuroPAL image with valid RGBW channel mapping and
voxel spacing. Choose **MoE** in the detection dropdown.
In Settings choose the actual DANDI dataset when known; otherwise keep
**unknown**. For the packaged examples use `000541` and `000715`, respectively.
Run detection, review/edit the imported centers, and save annotations normally.
CPU is the tested Mac backend. CUDA is accepted for a compatible environment;
MPS is not exposed because its parity has not been validated.

The model uses dataset indicator features. Unknown datasets get all-zero
indicators as defined by the research feature extractor. That behavior has
not been validated as a production policy. Do not assign a familiar dataset
ID to unrelated acquisitions. The app consumes the selected RGBW channels;
it does not override corrected NWB metadata to mimic historical 000981 ordering.

This is an **integration model**, not a production-selected ensemble. It does
not replace the existing recommended detector. Fixed consensus remains available
only as the separate `Wrapper.runDetectionEnsemble` CSV utility.

## Coordinates and preprocessing

MATLAB exports native YXZC RGBW data and XYZ voxel spacing. Python transposes to
XYZC, applies the pinned image-only preprocessing functions, and resamples to
0.4, 0.4, 1.5 micrometers. Annotation loading and annotation-guided cropping are
never invoked. Channel identity is resolved by the app, before Python runs.

The inverse transform follows the research centroid convention: processed XYZ
micrometers divided by native XYZ spacing, then reordered to YXZ and shifted
by one for MATLAB indexing. Crop origin is zero because the adapter processes
the full supplied volume. The saved response contains the transform and model
provenance. Subpixel centers are retained; color sampling uses nearest voxels.
The app does not apply its legacy nearby-neuron removal rule to MoE results.

## Runtime behavior

Mac CPU inference can differ from the saved CUDA predictions. Strict
end-to-end research parity has not passed on this backend; do not claim the
saved cluster metrics for CPU runs or tune thresholds against the bundled
held-out examples.

The Python subprocess has a per-expert timeout; MATLAB supports cancel and an
overall timeout. Failed or empty inference preserves existing annotations.
Each run owns a unique artifact directory with logs, expert CSVs, processed
input, router features, final predictions, and a response written only on success.
