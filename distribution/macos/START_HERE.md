# NeuroPAL ID — versioned methods package

For an Apple silicon Mac (M1 or newer), macOS 14+, with MATLAB installed.
Tested with MATLAB R2024a. Setup needs an internet connection and at least
12 GB free. Model weights are included; Python and its libraries are downloaded
during setup. No NVIDIA GPU or training is needed.

## Install and launch

1. Unzip the package and keep its files together.
2. Double-click **Setup-Mac.command**. It installs MoE detection, GAT Auto-ID
   and ZephIR tracking. **Setup-with-Auto-ID.command** is an equivalent alias.
3. Wait for **SETUP COMPLETE**. Start a fresh MATLAB session, open
   **Start_NeuroPAL.m** from the extracted folder, and click **Run**.

Use that same MATLAB file to launch this installation in future. It selects
this package's app and configures the included models automatically. No model
path editing is required. This is MATLAB source software; it requires MATLAB,
not just MATLAB Runtime.

If macOS won't open a command file, open Terminal, type `/bin/bash ` (with a
space), drag the command file onto the Terminal window, and press Return.
No Homebrew, preinstalled Python or administrator password is needed. If setup
fails, keep `setup.log`. Running setup again reuses verified installed components.

The app requires its usual MATLAB toolboxes: Image Processing, Statistics and
Machine Learning, and Optimization. Deep Learning Toolbox is required for the
legacy neural detector. Parallel Computing is optional.

## Identify an animal

1. Choose **File → Open** and select a supported NeuroPAL image, such as CZI,
   MAT or NWB. Check **Body**, **Sex**, channel assignments and image spacing.
   Select Tail for a tail image; the filename does not set these automatically.
2. For detection, use the gear beside **Auto-detect** to choose **MoE** and its
   input channels, then click **Auto-detect**. The default RGBW input uses the
   assigned channels even if a channel is hidden in the display. Single-channel
   and selected-channel inputs are also available. Inspect and edit the centers.
3. Select a neuron and type in **ID**. Matching names appear as you type.
   Select an individual name with its exact L/R or other suffix. A family such
   as IL1 can remain explicitly unresolved; the app does not invent a side.
   Click **Assign** or press **Command-Enter** / **Control-Enter** to save.
   Typing or leaving the field does not assign an identity.
4. Use **Neurons → Undo ID edit** to undo an annotation change. If an individual
   is already assigned elsewhere, review the conflict dialog before moving or
   swapping it. **Prefill prediction** only fills a provisional suggestion in
   the editor; it does not accept a prediction or assign an identity by itself.
5. For automatic suggestions, use the gear beside **Auto-ID** to choose **GAT**,
   then click **Auto-ID**. Review its predictions manually. Manual identification
   works without running either model and does not rewrite model probabilities.

Edits save to the companion `_ID.mat` beside the image. Keep the image and its
companion files together. Keep a backup before opening an original experiment
with a new software version. Use this launcher consistently; older app versions
do not understand the full structured annotation history.

Choose **Analysis → Export neuron IDs…** for a separate export. The default
**MAT** export preserves identities, unresolved candidates, certainty, stable
neuron IDs, evidence and edit history. Use **File → Import annotations…** to
restore it onto the same source/owners. A CSV is a summary, requires explicit
acknowledgement and includes a structured MAT companion; do not use CSV alone
as an annotation backup. **File → Review ID recovery…** handles preserved
previous-save choices when recovery is needed.

## Calcium videos

Open the recording through **File → Open** and use **Video Tracking**. Confirm
channel selection and spacing in **Image settings**, choose a reference frame,
detect and accept centers, then run ZephIR. Extra reference frames must be matched
to the existing neuron IDs. In **Review**, inspect/correct tracks, extract activity
and export the activity and tracks. A biological review of tracking and activity
is still necessary. Missing or assumed acquisition metadata is not measured
calibration. This desktop package does not include cluster or cloud submission.

## Included models and limits

- **MoE:** the verified fold-00 bundle from source
  `2276e61dedf9671740c1a36fab7d6d976b86de37`. Final production model selection
  remains unresolved. The package preserves its checkpoints and provenance.
- **GAT:** checkpoint `20260601-v1` with matching source and configuration.
- **YOLO:** the vendored YOLO INF 2 checkpoint and its inference scripts.
- **Matching pursuit, neural network and Atlas:** the app's existing MATLAB
  implementations and model assets, pinned with the app source. The legacy
  neural detector requires Deep Learning Toolbox; check `ACCEPTANCE.md` for
  whether that inference was exercised on the tested installation.
- **ZephIR:** a separate CPU runtime, version 1.0.4.
- **Standalone Spotiflow, custom Cellpose and CRF:** their separate trained
  assets are unavailable and are not included. The Spotiflow expert inside MoE
  is a different checkpoint. See `MISSING_MODELS.md` for exact requirements.
- **Ultrack and Higher-Order Transformer:** backend placeholders; not working
  tracking methods in this package. WormND Atlas is not an enabled portable method.

`METHODS.json` records every registered method, including unavailable ones.
Execution checks do not establish detector recall or correct biological IDs on
an unfamiliar animal. Missing-model errors must not prevent manual annotation.

## Version, validation and support

The release identifier is in `PACKAGE_VERSION`; `catalog.json` pins the source
commit and model packs, and `SHA256SUMS` records the packaged file hashes.
Installation files live under
`~/Library/Application Support/NeuroPAL_ID/Methods-<PACKAGE_VERSION>/`.
Existing MATLAB/Python installations and older NeuroPAL packages stay separate.
No recordings are included or uploaded. Setup downloads software only; inference
runs locally after installation.

Read `VALIDATION.md` for the test policy and `ACCEPTANCE.md`, when included, for
the actual checks completed on this exact release. For a bug report, include the
release identifier, `setup.log`, installed `installation.json`, the app's error
message and steps that triggered it. The original repository README is unchanged.
