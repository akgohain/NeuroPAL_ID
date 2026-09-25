# NeuroPAL ID for Ev

For an Apple silicon Mac (M1 or newer), macOS 14+, with MATLAB installed.
Tested with MATLAB R2024a. Setup needs an internet connection and at least
8 GB free. The model weights are included; Python and its libraries are
downloaded during setup. No NVIDIA GPU or training is needed.

## Install

1. Unzip the package and keep its files together.
2. Double-click **Setup-with-Auto-ID.command** to install MoE detection and
   GAT Auto-ID. For detection alone, use **Setup-Mac.command** instead.
3. Wait for **SETUP COMPLETE**. Then start a fresh MATLAB session, open
   **Start_NeuroPAL.m** from the extracted folder, and click **Run**.

Use that same MATLAB file to launch this installation in future. It selects
the included app and configures the installed models automatically.

If macOS won't open a command file, open Terminal, type `/bin/bash ` (with a
space), drag the desired command file onto the Terminal window, and press
Return. No Homebrew, preinstalled Python, or administrator password is needed.
If setup fails, keep `setup.log` from the extracted folder for your bug report.
Running setup again resumes by reusing verified installed components.

The app needs its usual MATLAB toolboxes: Image Processing, Statistics and
Machine Learning, and Optimization. Parallel Computing is optional.
This is MATLAB source software, not a standalone MATLAB Runtime application.

## Identify an animal

1. **File → Open** your CZI, MAT, NWB or other supported NeuroPAL image.
2. Check **Body**, **Sex**, the channel assignments and image spacing. Select
   Tail for a tail image. A filename does not set these correctly by itself.
3. Select **MoE** under Auto-detect, then **Run detection**. MoE uses all four
   distinct RGBW assignments, including W even when its display is unchecked.
4. Inspect and edit the centers. For automatic identities, choose **GAT** and
   **Run auto-ID**. Confirm or correct those suggestions manually.
5. Use **Save: IDs** to save the companion annotation file beside the image.
   Manual identification also works without running either model.

The app includes the App Designer method repair and the keyboard/slider fix.
Missing-model checks preserve existing annotations and explain setup failures.
The original repository README has not been changed.

## Included models and limits

- **MoE:** the verified fold-00 bundle from source
  `2276e61dedf9671740c1a36fab7d6d976b86de37`. Final production model selection
  remains unresolved. This package preserves the current model and provenance.
- **GAT:** optional checkpoint `20260601-v1` with matching source and configuration.
- **Standalone Spotiflow:** not included. It requires a different frozen
  checkpoint; select MoE to use the detector included in this package.
- **ZephIR:** its Python runtime is not installed by this identification kit.

Installation and test details are in `VALIDATION.md`; exact versions and hashes
are in `catalog.json` and `SHA256SUMS`. Passing the execution checks does not
establish detection or identity accuracy on a new animal.

Files install under
`~/Library/Application Support/NeuroPAL_ID/Ev-20260925/`.
Existing MATLAB/Python installations and older NeuroPAL setups stay separate.
No recordings are included or uploaded. Setup downloads software only.
Once installed, detection and identification run locally.

For a bug report, include `setup.log`, the installed `installation.json`,
the app's error message, and the steps that triggered it.
