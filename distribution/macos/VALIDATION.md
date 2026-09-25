# Ev package validation

This package targets Apple silicon, macOS 14+, MATLAB R2024a, CPU inference.
The MoE and GAT archives retain the hashes verified in the September 22 package.
The repaired app source is pinned by commit in `catalog.json`.

Source checks before packaging:

- App Designer editable/runnable code synchronization.
- Missing-model preflight before image staging or annotation changes.
- Keyboard Z navigation, slider dragging and processing-canvas regression tests.

The final sharing ZIP also includes `ACCEPTANCE.md` with the results of its
fresh-install, real-image inference and MATLAB checks. See that report for
the actual outcomes and timings. Do not infer successful inference from
weight loading alone.

The tests check installation and execution, not detection or identity accuracy.
No training or model reselection occurs. MoE remains the existing fold-00
integration model. Standalone frozen Spotiflow and a ZephIR runtime are not
included. Intel Macs and Windows are not supported by this package.

The bootstrap downloads uv 0.12.19 from the official astral-sh/uv release and
checks its pinned SHA-256. Python libraries come from the package index with
exact version locks. The installer does not change shell profiles or system
Python. Subsequent model inference runs locally.
