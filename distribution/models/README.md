Model distribution
==================

The application and trained models have independent versions. The tracked
`catalog.json` pins the baseline release, model checksums, training/source
revisions and the adapter/runtime contract. The app checks published stable
`models-*` releases only when the user chooses **Check updates**. It never changes
an installed model merely because a new release exists.

Users clone the app, start `visualize_light`, and choose **Tools > Models & runtimes
> Install / update**. On Apple silicon macOS 14+, the installer prepares an
isolated Python 3.11 environment without requiring Homebrew, a terminal or an
NVIDIA GPU. Model downloads resume after interruption and must pass SHA-256,
archive checks and real CPU model-load checks before use. Local methods packages
and manually selected existing installations remain supported. Managed runtime
downloads for Intel Macs, Windows and Linux are not supplied by this version.

Current downloadable components are MoE, GAT, the built-in YOLO model's runtime,
ZephIR, and a smaller runtime for recording/recommendation/alignment/activity.
MP, NN and the legacy atlas use their existing app/toolbox resources. No trained
standalone Spotiflow, Cellpose or CRF bundle is supplied by this catalog. MoE is
the coherent fold-00 integration fixture; final production model selection is
still unresolved. CPU loading establishes installation compatibility, not
scientific accuracy on new data.

Models, environments, verified downloads and completed installation receipts
live under the per-user NeuroPAL_ID application-support folder. An install can
select only its requested capability; it preserves other saved selections. If
another app changes that selection during installation, the newer selection
wins. Existing environments can be reused; **Rebuild runtime** creates a new
environment without replacing the previous one. **Use saved version** validates
the chosen receipt before switching back. No automatic deletion of older
versions or experimental files occurs.

Preparing a model release
-------------------------

1. Prepare coherent, versioned ZIPs with complete internal `SHA256SUMS`, and a
   source catalog containing `packs.moe` and `packs.gat` (the existing methods
   package catalog works), or the equivalent `models` definitions. Use new model
   versions and a new `models-*` release tag for changed bytes. Preserve training
   provenance. Do not include experimental images, caches or tracking outputs.
2. Run with Python 3.11 or newer from this folder:

   ```sh
   python3 prepare_release.py prepare --source-packs /path/to/packs \
     --output /path/to/new-candidate --tag models-YYYYMMDD-vN
   python3 prepare_release.py verify --output /path/to/new-candidate
   ```

   For hydrated LFS packs, add `--source-catalog catalog.json`. Copy the candidate's
   `model_catalog.json` to this folder as `catalog.json` when changing the tracked
   baseline. The candidate contains only the model ZIPs, catalog, checksums and
   release notes. It never overwrites an existing candidate directory.
3. Validate real inference and the app workflow with the candidate on supported
   hardware. Commit the reviewed source/catalog, then push that commit to the
   fork. No app release is needed when only compatible weights change. A new
   runtime lock or adapter contract requires a compatible app update.
4. After approval, stage a draft using an authenticated GitHub CLI:

   ```sh
   python3 prepare_release.py stage-draft --output /path/to/new-candidate
   ```

   This requires a clean checkout whose HEAD already exists on the fork, refuses
   existing tags/releases, uploads without clobbering, and verifies GitHub's asset
   digests. It leaves the release unpublished. Inspect the draft and publish it
   through GitHub after review. Never reuse a published version/tag for new bytes.
   A failed partial draft remains unpublished for inspection; use a new version
   after resolving it.

The optional **Prepare model release draft** GitHub workflow performs the same
steps using hydrated development packs at a reviewed ref. It is manual and
restricted to the fork; it does not publish. The workflow cannot use uncommitted
local packs. The initial candidate must be published before public model
downloads can succeed; the app reports this explicitly while preserving existing
installations. Checking updates uses GitHub's unauthenticated public API and may
be rate limited; local packages continue to work offline once dependencies are
installed/cached.

Git LFS and releases
--------------------

LFS is optional for short development iterations; only
`distribution/models/development/*.zip` uses it. No existing Git history or
checkpoints are migrated. Stable installations download release assets and do
not consume LFS bandwidth. LFS has account storage/bandwidth quotas, and changed
binary versions consume their full size again. See [GitHub LFS billing](https://docs.github.com/en/billing/concepts/product-billing/git-lfs).

Each [GitHub release asset](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
must be smaller than 2 GiB. These model packs are about 279 MB combined. Model
catalogs are verified against the release API's asset digest, and each model is
verified against its catalog checksum. Optional repository release immutability
can further protect published tags/assets; this tooling does not change account
settings, quotas or billing.
