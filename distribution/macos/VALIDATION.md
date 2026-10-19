# Package validation scope

## What setup checks

The installer verifies archive and extracted-file SHA256 checksums before
registering launcher paths. It loads all MoE experts and fitted routers, checks
preprocessing, loads GAT, executes a standalone YOLO CPU forward pass, and
imports the video bridge and ZephIR in its isolated runtime. A failed check
preserves the previous launcher rather than registering an incomplete install.

Each package identifies its source commit and model pack hashes in
`catalog.json`. The builder refuses modified or untracked desktop application
sources; the separate `cluster/` toolkit is intentionally omitted. This keeps
local development files from silently disappearing from a recipient's copy.
The release-specific installation folder avoids replacing an older package.

## Release acceptance

Setup checks are execution checks, not scientific accuracy tests. Acceptance
must be recorded in `ACCEPTANCE.md` alongside the delivered archive, with the
source commit, MATLAB/macOS versions, toolboxes, data fixtures, test commands,
results and limits. Do not reuse an earlier package's acceptance as proof that
a new source build passed.

The local source regression suites cover structured manual identities, full
catalog lookup, explicit assignment, occupied-ID conflicts and Undo, annotation
recovery and exchange, keyboard focus, navigation, channelwise detection,
reference matching, background-job safety and tracking/activity exports.
Release acceptance also needs native application checks on a fresh extraction:

1. Open representative CZI, MAT and NWB images. Drag Z, use left/right keys,
   add/edit centers and confirm slider/image synchronization.
2. Assign individual and unresolved IDs, cancel a conflict, Undo, save, quit,
   relaunch and reopen. Export structured MAT and verify a full round trip.
3. Run the supplied MoE and GAT models using the package launcher without
   developer path overrides. Exercise cancellation and missing-weight errors.
4. Open the calcium-video fixture, detect a chosen reference frame, track a
   representative segment, cancel/resume, correct observations, extract/export
   activity and reload the saved session. Record runtime and memory limits.

These checks have different scopes: callback tests do not replace native
mouse/keyboard checks, a short CPU tracking run does not validate an entire
recording, and successful inference does not establish biological accuracy.
The authoritative results for a delivered build belong in its acceptance file.

## Unavailable or deferred coverage

Standalone Spotiflow, the custom Cellpose model and CRF weights are absent; no
claim is made that those methods are installed. Manual identification must
remain usable when optional methods are unavailable. The legacy neural
checkpoint is included but needs Deep Learning Toolbox; a build tested without
that toolbox must state that its inference was not revalidated. Ultrack and
Higher-Order Transformer remain backend contracts, not implemented tracking
methods. This desktop release excludes cluster and cloud submission.

Apple silicon macOS with MATLAB R2024a is the supported delivery target for this
package. Windows, Intel macOS, Linux and screen-reader behavior require separate
acceptance. MATLAB toolbox availability remains a recipient requirement. The
root repository README is preserved.
