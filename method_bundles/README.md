# Method bundles

These folders are checkpoint slots, not committed model storage. Copy an
example manifest to `method_bundle.json`, place the named assets beside it,
and either keep the directory here or point NeuroPAL_ID to it in method
settings.

Environment-variable alternatives:

- `NEUROPAL_SPOTIFLOW_SUPERVISED_BUNDLE`
- `NEUROPAL_CRF_CELLID_2_BUNDLE`
- `NEUROPAL_DETECTION_MOE_BUNDLE`

The application validates the manifest and every required artifact before
launching inference. Large weights should remain outside Git.

## Installation flow

1. Copy the relevant `method_bundle.example.json` to `method_bundle.json` in a
   new writable bundle directory.
2. Place every required artifact at the relative path declared in the manifest.
3. Select that directory from the method's Settings dialog, or set its
   environment variable before launching MATLAB.
4. Select the method. The workflow banner and dropdown tooltip report whether
   the bundle is ready before inference starts.

The manifests are deliberately checkpoint-agnostic. Replacing a checkpoint or
atlas should require only a new bundle directory/manifest, not changes to GUI
callbacks or result import code.

`detection_moe` already has a tested canonical fusion layer, but it remains
hidden until the nnU-Net inference adapter can produce the same prediction CSV
contract as Spotiflow and YOLO.
