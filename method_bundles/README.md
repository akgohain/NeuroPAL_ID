# Method bundles

These folders are checkpoint slots, not committed model storage. Copy an
example manifest to `method_bundle.json`, place the named assets beside it,
and either keep the directory here or point NeuroPAL_ID to it in method
settings.

Use **Tools → Models & runtimes…** to select the method, its complete bundle,
and a compatible Python executable where required. **Apply** validates the
installation before saving it outside the Git checkout. Package installations
are discovered automatically, including installations made with older setup kits.

The application validates the manifest and every required artifact before
launching inference. Large weights should remain outside Git.

## Installation flow

1. Copy the relevant `method_bundle.example.json` to `method_bundle.json` in a
   new writable bundle directory.
2. Place every required artifact at the relative path declared in the manifest.
3. Open **Tools → Models & runtimes…**, choose the method and select the bundle.
4. Choose its Python executable if needed, then click **Apply**. The app checks
   the installation and remembers it for future launches. **Check** validates
   without saving; **Details** shows the actual interpreter and package versions.

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
