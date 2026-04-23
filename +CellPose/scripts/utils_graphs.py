from matplotlib import pyplot as plt
from matplotlib.gridspec import GridSpec
import numpy as np

def norm2d(arr):
    lo, hi = arr.min(), arr.max()
    return (arr - lo) / (hi - lo + 1e-8)

def plot_3d_mip(img, dataset, figsize=(8, 12)):
    """
    Compute MIP projections along all 3 axes for a single image.

    Row 0 : Z-axis projection (top-down,  full XY resolution)
    Row 1 : X-axis projection (side view, Z visible as one axis)
    Row 2 : Y-axis projection (side view, Z visible as one axis)

    img     : (X, Y, Z, C) array
    dataset : used in title of image

    Figure: 3 content rows + 2 spacer rows, 1 column
    """

    from matplotlib.gridspec import GridSpec

    projections = [
        ('Z-MIP', 2, True,  'auto'),
        ('X-MIP', 0, True,  'auto'),
        ('Y-MIP', 1, True,  'auto'),
    ]

    # ── GridSpec layout ───────────────────────────────────────────────────────
    # 5 rows total: [Z_img, SPACER, X_img, SPACER, Y_img]
    height_ratios = [1, 0.25, 1, 0.25, 1]
    gs_row_map    = [0, 2, 4]   # gs row index per projection

    fig = plt.figure(figsize=figsize)
    gs  = GridSpec(
        5, 1, figure=fig,
        height_ratios=height_ratios,
        hspace=0.3, wspace=0.05,
        top=0.91, bottom=0.02, left=0.06, right=0.98
    )

    # ── Create content axes ───────────────────────────────────────────────────
    axes_img = {}   # proj_idx -> Axes

    for proj_idx, img_row in enumerate(gs_row_map):
        axes_img[proj_idx] = fig.add_subplot(gs[img_row, 0])

    # ── Plot ──────────────────────────────────────────────────────────────────
    for proj_idx, (label, img_ax, transp_img, aspect) in enumerate(projections):

        # MIP computation
        mip_img  = np.max(img,  axis=img_ax)
        rgb_mip  = mip_img[:, :, :3]
        rgb_norm = norm2d(rgb_mip)
        rgb_disp = rgb_norm.transpose(1, 0, 2) if transp_img else rgb_norm

        ax_img = axes_img[proj_idx]
        ax_img.imshow(rgb_disp, origin='lower', aspect=aspect)
        ax_img.axis('off')

    # ── Group headings ────────────────────────────────────────────────────────
    # Finalise positions before reading them
    fig.canvas.draw()

    for proj_idx, (label, *_) in enumerate(projections):
        pos   = axes_img[proj_idx].get_position()
        mid_x = (pos.x0 + pos.x1) / 2
        head_y = pos.y1 + 0.008   # sits in the spacer row above the image row

        fig.text(
            mid_x, head_y, label,
            fontsize=13, fontweight='bold',
            va='bottom', ha='center',
            bbox=dict(boxstyle='round,pad=0.3', facecolor='steelblue', alpha=0.25),
        )

    fig.suptitle(
        f"MIPs — {dataset}",
        fontsize=16, y=0.97
    )

    return plt

def plot_3d_mip_with_masks(imgs, masks_list, dataset, mask_3D, figsize=(20, 16)):
    """
    Compute MIP projections along all 3 axes for each image.

    Rows 0–1 : Z-axis projection (top-down,  full XY resolution)
    Rows 2–3 : X-axis projection (side view, Z visible as one axis → fewer pixels)
    Rows 4–5 : Y-axis projection (side view, Z visible as one axis → fewer pixels)

    Within each row pair:
      - First row  : MIP image only (no masks)
      - Second row : MIP image with cellpose predicted mask outlines overlaid

    imgs       : list of (X, Y, Z, C) arrays
    masks_list : list of (Z, X, Y) arrays
    dataset    : used in title of image

    Figure: 6 content rows + 2 spacer rows × len(imgs) columns
    """

    from matplotlib.gridspec import GridSpec

    projections = [
        ('Z-MIP', 2, 0, True,  True,  'auto'),
        ('X-MIP', 0, 1, True,  False, 'auto' ),
        ('Y-MIP', 1, 2, True,  False, 'auto' ),
    ]

    n_cols = len(imgs)

    # ── GridSpec layout ───────────────────────────────────────────────────────
    # 8 rows total:
    #   [Z_img, Z_mask, SPACER, X_img, X_mask, SPACER, Y_img, Y_mask]
    # The spacer rows (ratio 0.25) create an empty band where the headings sit.
    height_ratios = [1, 1, 0.25, 1, 1, 0.25, 1, 1]
    gs_row_map    = [(0, 1), (3, 4), (6, 7)]   # (img_gs_row, mask_gs_row) per projection

    fig = plt.figure(figsize=figsize)
    gs  = GridSpec(
        8, n_cols, figure=fig,
        height_ratios=height_ratios,
        hspace=0.3, wspace=0.05,
        top=0.91, bottom=0.02, left=0.06, right=0.98
    )

    # ── Create content axes ───────────────────────────────────────────────────
    axes_img  = {}   # (proj_idx, col) -> Axes
    axes_mask = {}

    for proj_idx, (img_row, mask_row) in enumerate(gs_row_map):
        for col in range(n_cols):
            axes_img [(proj_idx, col)] = fig.add_subplot(gs[img_row,  col])
            axes_mask[(proj_idx, col)] = fig.add_subplot(gs[mask_row, col])

    # ── Plot ──────────────────────────────────────────────────────────────────
    for col, (img, masks) in enumerate(zip(imgs, masks_list)):
        for proj_idx, (label, img_ax, mask_ax, transp_img, transp_mask, aspect) in enumerate(projections):

            # MIP computation
            # img_rot = np.rot90(img, k=1, axes=(0, 1))
            mip_img  = np.max(img,   axis=img_ax)
            rgb_mip  = mip_img[:, :, :3]
            rgb_norm = norm2d(rgb_mip)
            rgb_disp = rgb_norm.transpose(1, 0, 2) if transp_img else rgb_norm

            # masks_rot = np.rot90(masks, k=1, axes=(1, 2))
            mip_mask_raw = np.max(masks, axis=mask_ax)
            mip_mask     = (mip_mask_raw.T if transp_mask else mip_mask_raw).astype(np.int32)

            # Image-only row
            ax_img = axes_img[(proj_idx, col)]
            ax_img.imshow(rgb_disp, origin='lower', aspect=aspect)
            ax_img.axis('off')
            if col == 0:
                ax_img.set_ylabel('Image', fontsize=9)

            # Image + mask outlines row
            ax_mask = axes_mask[(proj_idx, col)]
            ax_mask.imshow(rgb_disp, origin='lower', aspect=aspect)
            # if mip_mask.max() > 0:
            #     outlines_pred = utils.outlines_list(mip_mask)
            #     for o in outlines_pred:
            #         ax_mask.plot(o[:, 0], o[:, 1], color=[1, 1, 0.3], lw=0.75, ls='--')
            ax_mask.axis('off')
            if col == 0:
                ax_mask.set_ylabel('Masks', fontsize=9)

    # ── Group headings ────────────────────────────────────────────────────────
    # Finalise positions before reading them
    fig.canvas.draw()

    for proj_idx, (label, *_) in enumerate(projections):
        pos_left  = axes_img[(proj_idx, 0)         ].get_position()
        pos_right = axes_img[(proj_idx, n_cols - 1)].get_position()

        mid_x  = (pos_left.x0 + pos_right.x1) / 2
        head_y = pos_left.y1 + 0.008   # sits in the spacer row above the image row

        fig.text(
            mid_x, head_y, label,
            fontsize=13, fontweight='bold',
            va='bottom', ha='center',
            bbox=dict(boxstyle='round,pad=0.3', facecolor='steelblue', alpha=0.25),
        )

    method      = f"{(mask_3D).upper() if mask_3D else 'MERGED'}"
    fig.suptitle(
        f"Predicted Masks Overlayed on MIPs — {dataset} with {method} Cellpose 3D Method",
        fontsize=16, y=0.97
    )

    return plt