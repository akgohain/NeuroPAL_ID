Development model packs
=======================

This optional directory holds coherent model ZIPs through Git LFS. Ordinary users
do not need LFS: Tools > Models & runtimes > Install / update downloads a published
release instead. No model ZIPs are committed here initially.

For a model iteration, place the complete MoE/GAT archives here and prepare a new
catalog with `prepare_release.py`. Commit the catalog and matching LFS pointers
together. Keep expert weights, gate, router, feature order and thresholds coherent;
never replace a checkpoint in an existing archive/version.

Hydrate development assets with:

```sh
git lfs install
git lfs pull --include="distribution/models/development/*.zip"
```

A pointer is never loaded as a checkpoint. The installer verifies local ZIPs
against the selected catalog, or uses the published release if only a pointer is
available. Unpublished development weights require hydrated matching local ZIPs.
Model ZIPs in this directory are excluded from desktop source packages.
