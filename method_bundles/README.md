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

Most manifests are deliberately checkpoint-agnostic. The recommended
`spotiflow_supervised` bundle is intentionally stricter: its three model files
are checked against the frozen SHA-256 manifest from
`Yemini-Lab/GAT-NeuroPAL` PR #1. To install it, copy the example manifest to
`method_bundle.json`, create `checkpoint/`, and place `last.pt`, `config.yaml`,
and `train_config.yaml` there. A different checkpoint requires a deliberately
different model manifest rather than silently masquerading as the frozen v1
detector.

`detection_moe` now uses the nonlinear fold-00 MoE adapter. Install the verified
handoff with `scripts/install_moe_bundle.py`; see [MOE_INTEGRATION.md](../MOE_INTEGRATION.md)
for model/source requirements, CPU validation results, and app usage. The older
`Wrapper.runDetectionEnsemble` CSV consensus utility remains separate.
