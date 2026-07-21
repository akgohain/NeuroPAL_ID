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
