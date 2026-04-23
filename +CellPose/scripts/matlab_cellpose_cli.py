"""
MATLAB-friendly Cellpose CLI. Modes (same data loaders as test_clean.py, utils.py):
  - single: one ad-hoc .npy (from MATLAB or disk)
  - raw:     load_raw_data(dataset) — NWB under raw dataset tree
  - clean:   load_clean_data(dataset, output_prefix) — cleaned .npy dirs (aniso/iso)
Does not modify test_clean.py, utils.py, or utils_graphs.py.
Data roots default to the paths in utils; override with flags or env (see --help).
"""
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

import h5py
import matplotlib.pyplot as _plt
import numpy as np
from cellpose import core, models, io as clio
from scipy import io as sio

_DIR = Path(__file__).resolve().parent
if str(_DIR) not in sys.path:
    sys.path.insert(0, str(_DIR))
# Import after path so we can override utils.RAW_INPUT_DIR / CLEAN_* before load_*.
import utils as neuropal_utils  # noqa: E402
from utils_graphs import plot_3d_mip, plot_3d_mip_with_masks  # noqa: E402


def _apply_data_root_overrides(ns, source):
    """Point utils.*_DIR to local or cluster paths (only override what the mode needs)."""
    if source == "raw":
        if getattr(ns, "raw_root", None):
            r = os.path.abspath(str(ns.raw_root).rstrip("/") + os.sep)
            if not r.endswith(os.sep):
                r += os.sep
            neuropal_utils.RAW_INPUT_DIR = r
        elif os.environ.get("NEUROPAL_RAW_ROOT"):
            r = os.path.abspath(
                os.environ["NEUROPAL_RAW_ROOT"].rstrip("/") + os.sep
            )
            if not r.endswith(os.sep):
                r += os.sep
            neuropal_utils.RAW_INPUT_DIR = r
    if source == "clean":
        aniso = getattr(ns, "clean_dir_aniso", None)
        iso = getattr(ns, "clean_dir_iso", None)
        if aniso:
            neuropal_utils.CLEAN_INPUT_DIR_ANISO = os.path.abspath(str(aniso))
        if iso:
            neuropal_utils.CLEAN_INPUT_DIR_ISO = os.path.abspath(str(iso))
        if not aniso and os.environ.get("NEUROPAL_CLEAN_DIR_ANISO"):
            neuropal_utils.CLEAN_INPUT_DIR_ANISO = os.path.abspath(
                os.environ["NEUROPAL_CLEAN_DIR_ANISO"]
            )
        if not iso and os.environ.get("NEUROPAL_CLEAN_DIR_ISO"):
            neuropal_utils.CLEAN_INPUT_DIR_ISO = os.path.abspath(
                os.environ["NEUROPAL_CLEAN_DIR_ISO"]
            )


def _slug(s):
    s = re.sub(r"[^\w\-.+]+", "_", str(s).strip(), flags=re.ASCII)
    return s[:200] or "subject"


def _run_cellpose_on_list(img_data, model_path=None):
    clio.logger_setup()
    if core.use_gpu() is False:
        raise ImportError("No GPU access, change your runtime")
    if model_path:
        model = models.CellposeModel(pretrained_model=model_path, gpu=True)
    else:
        model = models.CellposeModel(gpu=True)

    t0 = time.time()
    masks, flows, _ = model.eval(
        img_data,
        z_axis=2,
        channel_axis=3,
        do_3D=True,
        flow3D_smooth=1,
        batch_size=4,
    )
    print(
        f"Cellpose 3D Method runtime: {(time.time() - t0) / 60.0:.2f} minutes (test_clean)"
    )
    t0 = time.time()
    print("running cellpose 2D + stitching masks")
    masks_stitched, flows_stitched, _ = model.eval(
        img_data,
        z_axis=2,
        channel_axis=3,
        batch_size=4,
        do_3D=False,
        stitch_threshold=0.5,
    )
    print(
        f"Cellpose Stiching Method runtime: {(time.time() - t0) / 60.0:.2f} minutes (test_clean)"
    )
    return model, masks, flows, masks_stitched, flows_stitched


def _write_one_volume_artifacts(
    out_dir, prefix, img3, m0, ms, test_data_row, no_figures, extra_meta=None
):
    """Save npy (single), h5, mat, json, optional PNGs for one volume (first index in lists)."""
    m0i = np.asarray(m0, dtype=np.int32)
    msi = np.asarray(ms, dtype=np.int32)
    h5_path = out_dir / f"{prefix}_masks.h5"
    with h5py.File(h5_path, "w") as f:
        f.create_dataset("masks_3D", data=m0i, compression="gzip")
        f.create_dataset("masks_stitched", data=msi, compression="gzip")
    sio.savemat(
        str(out_dir / f"{prefix}_masks.mat"),
        {
            "masks_3D": m0i,
            "masks_stitched": msi,
            "image_XYZC": img3,
        },
    )
    meta = {
        "image_shape_XYZC": list(img3.shape),
        "masks_3D_shape": list(m0i.shape),
        "masks_stitched_shape": list(msi.shape),
    }
    if test_data_row:
        meta["subject"] = test_data_row.get("subject")
        meta["dataset"] = test_data_row.get("dataset")
    if extra_meta:
        meta.update(extra_meta)
    with open(out_dir / f"{prefix}_meta.json", "w", encoding="utf-8") as fp:
        json.dump(meta, fp, indent=2)

    if not no_figures:
        try:
            plot_3d_mip(img3, dataset=prefix, figsize=(8, 12))
            _plt.savefig(
                str(out_dir / f"{prefix}_mip_input.png"), dpi=150, bbox_inches="tight"
            )
            _plt.close("all")
            plot_3d_mip_with_masks(
                [img3], [m0i], dataset=prefix, mask_3D="3D", figsize=(20, 16)
            )
            _plt.savefig(
                str(out_dir / f"{prefix}_mip_masks_3D.png"),
                dpi=150,
                bbox_inches="tight",
            )
            _plt.close("all")
            plot_3d_mip_with_masks(
                [img3], [msi], dataset=prefix, mask_3D="stitch", figsize=(20, 16)
            )
            _plt.savefig(
                str(out_dir / f"{prefix}_mip_masks_stitched.png"),
                dpi=150,
                bbox_inches="tight",
            )
            _plt.close("all")
        except Exception as e:  # noqa: BLE001
            print("Figure export skipped (utils_graphs / matplotlib):", e)

    return h5_path


if __name__ == "__main__":
    # Back-compat:  `python this.py vol.npy out`  same as  `python this.py single vol.npy out`
    if len(sys.argv) >= 3 and sys.argv[1].endswith(".npy"):
        nxt = next((a for a in ("single", "raw", "clean") if a == sys.argv[1]), None)
        if nxt is None and not sys.argv[1].startswith("-"):
            sys.argv.insert(1, "single")

    p = argparse.ArgumentParser(
        description="Cellpose (test_clean) with single .npy, or utils.load_raw_data / load_clean_data"
    )
    sub = p.add_subparsers(dest="source", required=True)

    s_single = sub.add_parser(
        "single", help="One .npy volume (X,Y,Z) or (X,Y,Z,C) — e.g. from MATLAB"
    )
    s_single.add_argument("input_npy", type=str)
    s_single.add_argument("output_dir", type=str)
    s_single.add_argument(
        "--prefix", default="matlab_volume", help="Output name prefix (like test_clean)"
    )
    s_single.add_argument("--model_path", default=None, help="Optional custom Cellpose model")
    s_single.add_argument(
        "--no-figures", action="store_true", help="Skip utils_graphs MIP PNGs"
    )

    s_raw = sub.add_parser("raw", help="NWB pipeline (utils.load_raw_data, same as test_clean)")
    s_raw.add_argument("output_dir", type=str, help="Where to write results")
    s_raw.add_argument(
        "--dataset", required=True, choices=["000715", "000981"],
        help="Subfolder of RAW input root (test_clean --dataset)"
    )
    s_raw.add_argument(
        "--prefix", default="neuropal", help="Prefix for per-subject and summary files"
    )
    s_raw.add_argument(
        "--raw-root",
        default=None,
        help="Override utils.RAW_INPUT_DIR (or env NEUROPAL_RAW_ROOT). Expect subfolders 000715, 000981, … (like …/dataset/)",
    )
    s_raw.add_argument(
        "--sample-size",
        type=int,
        default=None,
        help="Random subset of subjects (like utils.load_raw_data sample_size)",
    )
    s_raw.add_argument("--model_path", default=None, help="Optional custom Cellpose model")
    s_raw.add_argument(
        "--no-figures", action="store_true", help="Skip utils_graphs MIP PNGs (many volumes: faster)"
    )

    s_clean = sub.add_parser(
        "clean", help="Pre-cleaned .npy in aniso/iso dirs (utils.load_clean_data)"
    )
    s_clean.add_argument("output_dir", type=str, help="Where to write results")
    s_clean.add_argument(
        "--dataset", required=True, choices=["000715", "000981"],
    )
    s_clean.add_argument(
        "--output-prefix", required=True,
        help="Same as test_clean: include 'aniso' in the string to use the anisotropic path",
    )
    s_clean.add_argument(
        "--clean-dir-aniso", default=None, help="Anisotropic cleaned-npy directory (or env NEUROPAL_CLEAN_DIR_ANISO)"
    )
    s_clean.add_argument(
        "--clean-dir-iso", default=None, help="Isotropic cleaned-npy directory (or env NEUROPAL_CLEAN_DIR_ISO)"
    )
    s_clean.add_argument(
        "--sample-size", type=int, default=None,
        help="Random subset of npy files",
    )
    s_clean.add_argument("--model_path", default=None, help="Optional custom Cellpose model")
    s_clean.add_argument(
        "--no-figures", action="store_true", help="Skip MIP PNGs for each volume",
    )

    a = p.parse_args()
    _apply_data_root_overrides(a, a.source)

    out_dir = Path(a.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    mpath = getattr(a, "model_path", None)
    nof = a.no_figures

    if a.source == "single":
        in_path = Path(a.input_npy)
        vol = np.load(str(in_path))
        v = np.asarray(vol)
        if v.ndim == 3:
            v3 = (v.astype(np.float32) - v.min()) / (v.max() - v.min() + 1e-8) * 255.0
            u8 = np.round(v3).clip(0, 255).astype(np.uint8)
            img3 = np.stack([u8, u8, u8], axis=-1)
        elif v.ndim == 4:
            if v.shape[-1] < 3:
                sys.exit("Need (X,Y,Z) or (X,Y,Z,C) with C>=3")
            out = v[..., :3]
            if np.issubdtype(out.dtype, np.floating):
                out = ((out - out.min()) / (out.max() - out.min() + 1e-8) * 255.0).clip(0, 255)
            if out.dtype != np.uint8:
                out = np.round(out).clip(0, 255).astype(np.uint8)
            else:
                out = out.astype(np.uint8)
            img3 = out
        else:
            sys.exit("Array must be 3D or 4D (X,Y,Z) or (X,Y,Z,C)")

        img_data = [img3]
        test_data = [{"dataset": "from_matlab", "subject": in_path.stem}]

        _, masks, flows, masks_stitched, flows_stitched = _run_cellpose_on_list(
            img_data, model_path=mpath
        )
        prefix = a.prefix
        npy_out = out_dir / f"{prefix}_cellpose_neuropal.npy"
        np.save(
            str(npy_out),
            {
                "masks": masks,
                "flows": flows,
                "masks_stitched": masks_stitched,
                "flows_stitched": flows_stitched,
                "subject": [d["subject"] for d in test_data],
                "dataset": [d["dataset"] for d in test_data],
            },
        )
        m0, ms0 = masks[0], masks_stitched[0]
        _write_one_volume_artifacts(
            out_dir,
            prefix,
            img3,
            m0,
            ms0,
            test_data[0],
            nof,
            extra_meta={"input_file": str(in_path.resolve()), "npy_result": str(npy_out.resolve())},
        )
        print("Wrote:", npy_out, "and *masks* in", out_dir)

    elif a.source == "raw":
        test_data, img_data = neuropal_utils.load_raw_data(
            a.dataset, sample_size=a.sample_size, display_stats=True
        )
        if not img_data:
            sys.exit("load_raw_data returned no volumes (check paths and --raw-root / NEUROPAL_RAW_ROOT)")

        _, masks, flows, masks_stitched, flows_stitched = _run_cellpose_on_list(
            img_data, model_path=mpath
        )
        pfx = a.prefix
        npy_out = out_dir / f"{pfx}_cellpose_neuropal.npy"
        np.save(
            str(npy_out),
            {
                "masks": masks,
                "flows": flows,
                "masks_stitched": masks_stitched,
                "flows_stitched": flows_stitched,
                "subject": [d["subject"] for d in test_data],
                "dataset": [d["dataset"] for d in test_data],
            },
        )
        print(f"Wrote batch npy: {npy_out}; per-subject h5/mat…")

        for i, row in enumerate(test_data):
            subj = _slug(row["subject"])
            q = f"{pfx}_{i:04d}_{subj}"
            _write_one_volume_artifacts(
                out_dir,
                q,
                img_data[i],
                masks[i],
                masks_stitched[i],
                row,
                nof,
                extra_meta={"batch_npy": str(npy_out.resolve())},
            )
        print("Done. Summary:", len(img_data), "volumes in", out_dir)

    else:  # clean
        test_data, img_data = neuropal_utils.load_clean_data(
            a.dataset, a.output_prefix, sample_size=a.sample_size, display_stats=True
        )
        if not img_data:
            sys.exit(
                "load_clean_data returned no npy (check aniso/iso in --output-prefix, dirs, env, or --clean-dir-*)"
            )
        _, masks, flows, masks_stitched, flows_stitched = _run_cellpose_on_list(
            img_data, model_path=mpath
        )
        pfx = a.output_prefix.replace("/", "_")
        npy_out = out_dir / f"{pfx}_cellpose_neuropal.npy"
        np.save(
            str(npy_out),
            {
                "masks": masks,
                "flows": flows,
                "masks_stitched": masks_stitched,
                "flows_stitched": flows_stitched,
                "subject": [d["subject"] for d in test_data],
                "dataset": [d["dataset"] for d in test_data],
            },
        )
        for i, row in enumerate(test_data):
            subj = _slug(row["subject"])
            q = f"{pfx}_{i:04d}_{subj}"
            _write_one_volume_artifacts(
                out_dir,
                q,
                img_data[i],
                masks[i],
                masks_stitched[i],
                row,
                nof,
                extra_meta={"batch_npy": str(npy_out.resolve())},
            )
        print("Done. Summary:", len(img_data), "volumes; batch", npy_out, "in", out_dir)