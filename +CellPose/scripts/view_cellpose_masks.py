"""
View Cellpose *_masks.mat in Matplotlib (RGB + label MIPs + simple overlay).

  python view_cellpose_masks.py /path/to/prefix_masks.mat

Same variables as Wrapper/display_cellpose_masks.m: image_XYZC, masks_3D, masks_stitched.
Handles (X,Y,Z,3) or (X,Y,3,Z) layout from scipy savemat.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.io import loadmat

try:
    from skimage.color import label2rgb
except ImportError:
    label2rgb = None


def _to_xyz3_rgb(img: np.ndarray) -> np.ndarray:
    """Return (X, Y, Z, 3) uint8 for RGB stack."""
    v = np.asarray(img)
    if v.ndim != 4:
        raise ValueError(f"image_XYZC must be 4D, got {v.shape}")
    if v.shape[2] == 3 and v.shape[3] > 1 and v.shape[3] != 3:
        v = np.transpose(v, (0, 1, 3, 2))
    if v.shape[-1] != 3:
        raise ValueError(f"Expected 3 channels last after layout fix, got {v.shape}")
    if v.dtype != np.uint8:
        v = np.clip(v, 0, 255).astype(np.uint8)
    return v


def _mip_z_rgb(I: np.ndarray) -> np.ndarray:
    """I is (X, Y, Z, 3). Z-MIP -> (X, Y, 3)."""
    return np.max(I, axis=2)


def _mip_mask_xy(M: np.ndarray, x: int, y: int, z: int) -> np.ndarray:
    """
    Z-MIP of 3D label map to (X, Y) matching the RGB MIP.
    M may be (X,Y,Z) or (Z,X,Y) (Cellpose / scipy), etc.; we max along the
    axis whose length is z, then permute 2D to (x, y) if needed.
    """
    M = np.asarray(M)
    if M.ndim != 3:
        raise ValueError(f"mask must be 3D, got {M.shape}")
    s = M.shape
    if z not in s:
        raise ValueError(f"depth size z={z} not in mask shape {s}")
    z_ax = list(s).index(z)
    out = np.max(M, axis=z_ax)
    if out.shape == (x, y):
        return out
    if out.shape == (y, x):
        return out.T
    raise ValueError(
        f"After Z-MIP, mask 2D {out.shape} does not match image XY ({x},{y}) or ({y},{x})"
    )


def main() -> None:
    p = argparse.ArgumentParser(description="Plot Cellpose masks from *_masks.mat")
    p.add_argument(
        "mat_path",
        type=str,
        nargs="?",
        default=None,
        help="Path to *_masks.mat (from matlab_cellpose_cli.py)",
    )
    p.add_argument(
        "-o",
        "--out",
        type=str,
        default=None,
        help="Save figure to this path (png) instead of showing",
    )
    args = p.parse_args()

    mat_path = args.mat_path
    if not mat_path:
        here = Path(__file__).resolve().parent
        guess = here.parent / "Output" / "000715_sub11_masks.mat"
        if guess.is_file():
            mat_path = str(guess)
            print("Using default:", mat_path)
        else:
            p.print_help()
            sys.exit("Pass the path to *_masks.mat")

    mat_path = Path(mat_path)
    if not mat_path.is_file():
        sys.exit(f"Not found: {mat_path}")

    d = loadmat(str(mat_path), squeeze_me=True, struct_as_record=False)
    for key in ("__header__", "__version__", "__globals__"):
        d.pop(key, None)
    if "image_XYZC" not in d or "masks_3D" not in d:
        sys.exit(f"Need image_XYZC and masks_3D in {mat_path}")
    if "masks_stitched" not in d:
        d["masks_stitched"] = None

    I = _to_xyz3_rgb(d["image_XYZC"])
    M3 = np.asarray(d["masks_3D"])
    Ms = d.get("masks_stitched")
    if Ms is not None:
        Ms = np.asarray(Ms)

    x, y, z, _ = I.shape
    rgb_mip = _mip_z_rgb(I)
    m3_mip = _mip_mask_xy(M3, x, y, z)
    if Ms is not None and Ms.size:
        ms_mip = _mip_mask_xy(Ms, x, y, z)
    else:
        ms_mip = None

    fig, axes = plt.subplots(2, 2, figsize=(12, 12))
    fig.suptitle(f"Cellpose Z-MIP — {mat_path.stem}", fontsize=14)

    axes[0, 0].imshow(rgb_mip)
    axes[0, 0].set_title("Input RGB (Z-MIP)")
    axes[0, 0].axis("off")

    if label2rgb is not None:
        try:
            im_lbl = label2rgb(
                m3_mip,
                image=rgb_mip.astype(np.float64) / 255.0,
                bg_label=0,
                kind="overlay",
                alpha=0.45,
            )
        except (TypeError, ValueError):
            im_lbl = label2rgb(m3_mip, bg_label=0)
        axes[0, 1].imshow(im_lbl)
    else:
        axes[0, 1].imshow(m3_mip, cmap="nipy_spectral")
    axes[0, 1].set_title("3D run — labels (Z-MIP)")
    axes[0, 1].axis("off")

    if ms_mip is not None and np.any(ms_mip > 0):
        if label2rgb is not None:
            try:
                im_s = label2rgb(
                    ms_mip,
                    image=rgb_mip.astype(np.float64) / 255.0,
                    bg_label=0,
                    kind="overlay",
                    alpha=0.45,
                )
            except (TypeError, ValueError):
                im_s = label2rgb(ms_mip, bg_label=0)
            axes[1, 0].imshow(im_s)
        else:
            axes[1, 0].imshow(ms_mip, cmap="nipy_spectral")
        axes[1, 0].set_title("2D+stitch — labels (Z-MIP)")
    else:
        axes[1, 0].text(0.5, 0.5, "no masks_stitched", ha="center", va="center", transform=axes[1, 0].transAxes)
        axes[1, 0].set_title("2D+stitch")
    axes[1, 0].axis("off")

    # simple yellow tint where 3D mask > 0
    ovl = rgb_mip.astype(np.float32) / 255.0
    fg = m3_mip > 0
    ovl = ovl * 0.65
    ovl[:, :, 0] = np.clip(ovl[:, :, 0] + 0.35 * fg, 0, 1)
    ovl[:, :, 1] = np.clip(ovl[:, :, 1] + 0.35 * fg, 0, 1)
    axes[1, 1].imshow(ovl)
    axes[1, 1].set_title("RGB MIP + 3D foreground (yellow blend)")
    axes[1, 1].axis("off")

    plt.tight_layout()
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(out, dpi=150, bbox_inches="tight")
        print("Saved", out.resolve())
    else:
        plt.show()


if __name__ == "__main__":
    main()
