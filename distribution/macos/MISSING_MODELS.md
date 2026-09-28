# Remaining model handoff

This distribution contains all locally available app methods. The following
separate trained resources must be supplied before claiming complete coverage.
Please provide a checksummed ZIP with the matching source revision, license,
training provenance, environment lock and one small inference fixture per method.
No retraining is requested.

* **Standalone Spotiflow:** the frozen four-view bundle specified by
  `method_bundles/spotiflow_supervised/method_bundle.example.json`, including
  `method_bundle.json`, `spotiflow_neuropal_v1_model.json`, `last.pt`,
  `config.yaml`, and `train_config.yaml` in the manifest's expected paths.
  Source: `46e7ef4e67519cce7bb13d13bc215ebb9147541c`.
  Expected last.pt SHA256:
  `9f194781ad4310d12ffae98064c996c24010ac4f6269d7924a026f47e3b3287b`.
  The MoE expert is a different checkpoint and cannot replace it.
* **CRF:** the real bundle matching
  `method_bundles/crf_cellid_2/method_bundle.example.json`, including
  `method_bundle.json`, `atlas.mat`, `unary_model.mat`, and the executable
  `run_neuropal_id_request.m` entry point with its dependencies.
  Source: `f025f12a3e7102a8fa0ac8ec390534da1586bd57`.
  Repository test fixtures are not trained models.
* **Cellpose:** the custom `cellpose_000715` checkpoint expected by the app,
  or an explicitly selected replacement with its model type, Cellpose version,
  channel/diameter/3D settings and validation fixture. Generic cyto/cpsam
  downloads are not equivalent to the missing trained NeuroPAL checkpoint.

Once supplied, add verified model packs and runtime checks to the installer;
do not ask recipients to select arbitrary developer-machine paths.
