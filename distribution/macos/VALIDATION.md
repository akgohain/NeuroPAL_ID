# Package validation scope

The installer verifies archive and extracted-file SHA256 checksums before
registering any launcher paths. It loads all MoE experts and fitted routers,
checks preprocessing, loads GAT, executes a standalone YOLO CPU forward pass,
and imports the video bridge and ZephIR in its isolated runtime.

These installation checks are not accuracy tests. The September 25 predecessor
passed real CZI MoE detection, GAT identification, manual edits and CSV export
on Apple silicon with MATLAB R2024a. This package retains those checkpoints.
New validation results for this package are recorded in ACCEPTANCE.md alongside
the delivered archive. MATLAB toolbox availability remains a recipient requirement.

Missing Cellpose, standalone Spotiflow and CRF models have not been validated;
no claim is made that those methods are installed. The root repository README
is preserved.
