# Large-file conversion contract

NeuroPAL_ID's conversion layer follows a transactional streaming contract:

1. Probe metadata without loading the image volume.
2. Reject unsupported dimensions and insufficient disk space before writing.
3. Read bounded source hyperslabs and write indexed slices to a Version 7.3
   MAT file. The default working-memory budget is 128 MiB and can be adjusted
   with `NEUROPAL_IO_CHUNK_MIB` (8–1024 MiB).
4. Write only to a hidden, same-directory partial file. Checkpoint each
   committed Z range and honor UI cancellation between chunks.
5. Resume only when source path, size, modification time, dataset path,
   dimensions, and element class still match.
6. Verify the output variable's dimensions and class, mark the checkpoint
   complete, then promote it to the requested filename. A partial conversion
   must never appear under the final filename.

NWB conversion implements the complete contract, including resumability. ND2
conversion shares the bounded-memory, disk-preflight, cancellation, on-disk
allocation, and final-promotion policies; its temporary file is discarded on
failure because Bio-Formats plane iteration does not yet expose a stable source
signature/checkpoint contract.

## Repeatable NWB stress audit

Run the cancellation/resume/equality harness against a local or downloaded NWB:

```sh
NPAL_LARGE_FILE_FIXTURE=/path/to/source.nwb scripts/run_large_file_audit
```

The harness intentionally interrupts after the first committed chunk, confirms
that no final file is visible, resumes the partial, and compares the first,
middle, and last output slices byte-for-byte with HDF5 hyperslab reads. Results
are written under `.ui_artifacts/large-file-audit` by default.

## Main image loading and processing

The main identification viewer still owns a numeric image array. Before loading
MAT pixels, it checks the decoded `data` variable against a **512 MiB native
payload limit**, configurable with `NEUROPAL_IMAGE_MAX_MIB`. This is not a peak
RAM budget: MATLAB, rendering, processing, and inference need additional memory.
The limit applies to the MAT load; it does not make every source-format converter
streaming. Only `data`, `version`, `info`, `prefs`, and `worm` are loaded, so
unrelated MAT variables cannot increase the main image's materialization cost.

Image Processing can inspect Version 7.3 MAT files lazily. Resolving/converting a
source no longer eagerly reopens all converted pixels. Large older MAT files must
be converted to Version 7.3 before lazy processing; small older MAT files retain
their existing support. Downsampling of lazy volumes is still unsupported.

Lazy processing writes slices to a unique hidden partial file, verifies dimensions,
dtype, and the first output slice, then publishes a new result. Existing
`_processed.mat` outputs are preserved by selecting an unused numbered filename.
Cancellation, changed input/settings, or processing failure removes the partial;
image path, preferences, scale, and flags are committed only after successful
publication. Cancellation is checked between slices.

## NWB export

NWB image/video export creates the output datasets before writing XY planes. It
does not append a movie to an unbound in-memory DataPipe. The installed extension
requires `uint16`: integer values in 0–65535 are preserved, larger/negative values
are rejected, and floating-point sources use one global linear scale across the
entire source. Floating-point export therefore uses two bounded passes; its source
range and conversion are recorded in standard NWB notes. Source pixels are not
modified. Previously bound datasets are copied through DataStub references when
merging into a new output.

Outputs are written to unique same-directory partial files and published only after
all planes and dimensions/dtype checks succeed. Cancellation and errors remove the
partial and preserve previous outputs. The initial MatNWB metadata/old-dataset copy
is a blocking library operation; cancellation is checked around it and between
planes. The chunk budget also checks the minimum plane/slice working size and
rejects oversized work units instead of materializing a whole volume as a fallback.

Focused contracts: `test_npal_mat_source`, `test_neuropal_image_loader`,
`test_nwb_stream_export`, and `test_processing_transaction` in `scripts/`.
