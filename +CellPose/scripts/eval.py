import argparse

import numpy as np

# import cudf.pandas

import pandas as pd
from scipy.spatial.distance import cdist
from scipy.optimize import linear_sum_assignment
from matplotlib import pyplot as plt

from cellpose import transforms, utils

from utils import load_raw_data, load_clean_data


def get_segment_properties(masks):
    """
    EXTRACT CELLPOSE SEGMENT PROPERTIES
    For each cellpose segment compute:
      - center of mass centroid (z, x, y)
      - bounding box centroid  (z, x, y)
      - bounding box dims
      - voxel count (volume)
    masks shape: (Z, X, Y)
    """
    rows = []
    cellpose_ids = np.unique(masks[masks > 0])

    for cid in cellpose_ids:
        voxels = np.argwhere(masks == cid)   # shape: (N, 3) → columns: z, x, y

        # Center of mass centroid
        com = voxels.mean(axis=0)            # (z, x, y)

        # Bounding box 
        min_zxy = voxels.min(axis=0)
        max_zxy = voxels.max(axis=0)
        bbox_centroid = (min_zxy + max_zxy) / 2.0

        rows.append({
            'cellpose_id'    : cid,
            # center of mass
            'com': tuple(com),
            # bounding box centroid
            'bbox': tuple(bbox_centroid),
            # volume
            'voxel_count' : len(voxels),
        })

    return pd.DataFrame(rows)


def point_in_mask_metric(df_ann, mask_data):
    """
    For each annotated neuron centroid, check if the point (z, x, y)
    falls inside any cellpose mask (i.e. mask value > 0 at that voxel).

    df_ann    : annotations DataFrame with roi_idx column (z, x, y) tuples
    mask_data : 3D numpy array of cellpose masks (Z, X, Y) where 0=background, >0=cellpose segment ID

    Returns dict of metrics + per-neuron result DataFrame.
    """

    ann_coords = df_ann['roi_idx'].values           
    ann_coords = np.stack(ann_coords).astype(int)             # shape: (N_ann, 3) → columns: z, x, y

    ann_coords = np.clip(
        ann_coords,
        a_min=[0, 0, 0],
        a_max=[mask_data.shape[0] - 1,
            mask_data.shape[1] - 1,
            mask_data.shape[2] - 1]
    )

    # Look up mask value at each annotation coordinate
    cellpose_ids = mask_data[
        ann_coords[:, 0],   # z
        ann_coords[:, 1],   # x
        ann_coords[:, 2],   # y
    ]                                               # shape: (N_ann,) — vectorised, no loop needed

    inside_mask = cellpose_ids > 0                  # True = annotation falls inside a segment

    df_result = pd.DataFrame({
        'neuron_id'   : df_ann['neuron_id'].values,
        'ann_coords'  : list(map(tuple, ann_coords)),
        'cellpose_id' : cellpose_ids,
        'inside_mask' : inside_mask,
    })

    metrics = {
        'n_annotated'    : len(df_result),
        'n_inside_mask'  : inside_mask.sum(),
        'n_outside_mask' : len(df_result) - inside_mask.sum(), # n_annotated - n_inside_mask
        'coverage'       : round(float(inside_mask.sum() / len(df_result) if len(df_result) > 0 else 0.0), 4), # n_inside_mask / n_annotated
    }

    return metrics, df_result


def hungarian_matching(df_ann, df_seg, distance_threshold=10.0):
    """
    HUNGARIAN MATCHING — annotated centroids ↔ cellpose centroids
    For each annotated neuron, find the closest cellpose segment centroid.
    Distance threshold: if matched pair is farther than this → not a true match
    """

    # Build coordinate arrays
    ann_coords = df_ann['roi_idx'].values
    seg_coords = df_seg['com'].values

    ann_coords = np.stack(ann_coords)  # shape: (N_ann, 3)
    seg_coords = np.stack(seg_coords)  # shape: (N_seg, 3

    dist_matrix = cdist(ann_coords, seg_coords, metric='euclidean')     # (N_ann, N_seg)
    print(f"\nDistance matrix shape: {dist_matrix.shape}  (annotations × segments)")

    # Hungarian algorithm — finds optimal 1-to-1 assignment minimising total distance
    ann_indices, seg_indices = linear_sum_assignment(dist_matrix)

    match_results = []
    for ann_i, seg_i in zip(ann_indices, seg_indices):
        dist = dist_matrix[ann_i, seg_i]
        match_results.append({
            'neuron_id'     : df_ann.loc[ann_i, 'neuron_id'],
            'ann_coords': (ann_coords[ann_i, 0], ann_coords[ann_i, 1], ann_coords[ann_i, 2]),
            'cellpose_id'   : df_seg.loc[seg_i, 'cellpose_id'],
            'seg_coords': (seg_coords[seg_i, 0], seg_coords[seg_i, 1], seg_coords[seg_i, 2]),
            'centroid_dist' : dist,
            'matched'       : dist <= distance_threshold,
        })

    return pd.DataFrame(match_results)


def calculate_metrics(df_ann, df_seg, df_matches, subject, distance_threshold=10.0):
    """
    CALCULATE EVALUATION METRICS
    - Precision, Recall, F1 Score
    - Accuracy (Jaccard / detection accuracy)
    - Centroid distance statistics (mean, median, std, max)
    - Distance error rate (fraction of annotations > threshold from matched segment)
    """
    n_annotated = len(df_ann)
    n_cellpose  = len(df_seg)

    tp = df_matches['matched'].sum()
    fn = n_annotated - tp                    # annotated but unmatched / too far
    fp = n_cellpose  - tp                    # cellpose segments with no annotation match

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall    = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1        = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    accuracy  = tp / (tp + fp + fn) if (tp + fp + fn) > 0 else 0.0  # Jaccard / detection acc


    # ── Voxel distance error (only over matched pairs) ────────────────────────────
    matched_dists = df_matches.loc[df_matches['matched'], 'centroid_dist']
    mean_dist     = matched_dists.mean()
    median_dist   = matched_dists.median()
    std_dist      = matched_dists.std()
    max_dist      = matched_dists.max()

    # Error rate: fraction of annotations whose centroid is off by > threshold
    distance_error_rate = (df_matches['centroid_dist'] > distance_threshold).mean()

    return {
        'subject'             : subject,
        'n_annotated'         : n_annotated,
        'n_cellpose'          : n_cellpose,
        'tp'                  : int(tp),
        'fp'                  : int(fp),
        'fn'                  : int(fn),
        'precision'           : round(precision, 4),
        'recall'              : round(recall, 4),
        'f1'                  : round(f1, 4),
        'accuracy'            : round(accuracy, 4),
        'mean_dist_vx'        : round(mean_dist, 4),
        'median_dist_vx'      : round(median_dist, 4),
        'std_dist_vx'         : round(std_dist, 4),
        'max_dist_vx'         : round(max_dist, 4),
        'distance_error_rate' : round(distance_error_rate, 4),
    }


def norm2d(arr):
    lo, hi = arr.min(), arr.max()
    return (arr - lo) / (hi - lo + 1e-8)


def plot_3d_mip_with_masks_old(imgs, masks_list, output_prefix, dataset, mask_3D, figsize=(20, 8)):
    """
    Compute full-Z MIP for each image.
    Row 1: MIP image only (no masks)
    Row 2: MIP image with cellpose predicted mask outlines overlaid

    imgs       : list of (X, Y, Z, C) arrays
    masks_list : list of (Z, X, Y) arrays
    dataset    : used in title of image

    Figure: 2 rows × imgs columns
    """

    fig, axes = plt.subplots(2, len(imgs), figsize=figsize)  

    for col, (img, masks) in enumerate(zip(imgs, masks_list)):

        # ── Shared MIP computation ────────────────────────────────────────────
        mip_img  = np.max(img, axis=2)
        rgb_mip  = mip_img[:, :, :3]
        # rgb_norm = (rgb_mip - rgb_mip.min()) / (rgb_mip.max() - rgb_mip.min() + 1e-8)
        rgb_norm = norm2d(rgb_mip)
        rgb_disp = rgb_norm.transpose(1, 0, 2)               # (Y, X, C) for imshow

        mip_mask = np.max(masks, axis=0).T.astype(np.int32)  # (Y, X) for outlines

        # ── Row 0: image only ─────────────────────────────────────────────────
        ax_img = axes[0, col]                                 
        ax_img.imshow(rgb_disp, origin='lower')
        ax_img.axis('off')
        if col == 0:
            ax_img.set_ylabel('Image', fontsize=9)            # row label on leftmost column

        # ── Row 1: image + mask outlines ──────────────────────────────────────
        ax_mask = axes[1, col]                                
        ax_mask.imshow(rgb_disp, origin='lower')
        if mip_mask.max() > 0:
            outlines_pred = utils.outlines_list(mip_mask)
            for o in outlines_pred:
                ax_mask.plot(o[:, 0], o[:, 1], color=[1, 1, 0.3], lw=0.75, ls='--')
        ax_mask.axis('off')
        if col == 0:
            ax_mask.set_ylabel('Masks', fontsize=9)           # row label on leftmost column

    plt.tight_layout(rect=[0, 0, 1, 0.93])
    image_type  = "CLEANED" if "clean" in output_prefix else "RAW"
    image_type += f" - Anisotropic" if "aniso" in output_prefix else f" - Isotropic"
    method      = f"{(args.method_3D).upper() if args.method_3D else 'MERGED'}"
    plt.suptitle(
        f"Predicted Masks Overlayed on MIPs — {dataset} with {method} Cellpose 3D Method, Image: {image_type}",
        fontsize=16
    )

    fname = f"results/{dataset}/{args.output_prefix}_{mask_3D}_mip.png"
    plt.savefig(fname, dpi=100, bbox_inches='tight')
    plt.close(fig)
    print(f"Saved → {fname}")


def plot_3d_mip_with_masks(imgs, masks_list, output_prefix, dataset, mask_3D, figsize=(20, 16)):
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
            if mip_mask.max() > 0:
                outlines_pred = utils.outlines_list(mip_mask)
                for o in outlines_pred:
                    ax_mask.plot(o[:, 0], o[:, 1], color=[1, 1, 0.3], lw=0.75, ls='--')
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

    # ── Title & save ──────────────────────────────────────────────────────────
    image_type  = "CLEANED" if "clean" in output_prefix else "RAW"
    if "aniso" in output_prefix:
        image_type += " - Anisotropic"
    elif "iso" in output_prefix:
        image_type += " - Isotropic"
    else:
        image_type += " - Anisotropic"
    method      = f"{(args.method_3D).upper() if args.method_3D else 'MERGED'}"
    fig.suptitle(
        f"Predicted Masks Overlayed on MIPs — {dataset} with {method} Cellpose 3D Method, Image: {image_type}",
        fontsize=16, y=0.97
    )

    fname = f"results/{dataset}/{args.output_prefix}_{mask_3D}_mip_all.png"
    fig.savefig(fname, dpi=100, bbox_inches='tight')
    plt.close(fig)
    print(f"Saved → {fname}")


def main(args):
    segments_array = np.load(f"results/{args.output_prefix}_cellpose_neuropal.npy", allow_pickle=True).item()
    df_segments = pd.DataFrame(segments_array)

    print(f"Loaded cellpose results for {len(df_segments)} subjects")

    if len(df_segments) == 0:
        print("No cellpose results found. Exiting.")
        return

    df_gold = pd.read_csv(args.gold_neurons)      

    dataset = df_segments['dataset'].unique()[0].split('/')[-1]
    print(f"Evaluating dataset: {dataset}")                     

    subjects = df_gold['subject'].unique()                             
    print(f"Subjects to process: {list(subjects)}")

    mask_3D = "masks_stitched" if args.method_3D else "masks"

    all_matches = []                                                      
    all_metrics = []    

    for subject in subjects:
        print(f"\nProcessing subject: {subject}")
        df_seg_subj = df_segments[df_segments['subject'] == subject].reset_index(drop=True)
        df_ann_subj   = df_gold[df_gold['subject'] == subject].reset_index(drop=True)

        if len(df_seg_subj)==0:
            continue

        mask_data = df_seg_subj[mask_3D][0]

        df_seg = get_segment_properties(mask_data)
        print(f"Cellpose segments extracted: {len(df_seg)}")

        df_ann_subj['roi_idx'] = df_ann_subj[[f'z{args.csv_col_suffix}', f'x{args.csv_col_suffix}', f'y{args.csv_col_suffix}']].apply(tuple, axis=1)
        print(f"Annotated neurons loaded: {len(df_ann_subj)}")

        # CALCULATE POINT IN MASK METRIC (annotation coverage)
        point_in_mask_metrics , _ = point_in_mask_metric(df_ann_subj, mask_data)
        print(f"Point-in-mask coverage: {point_in_mask_metrics['coverage']:.4f} ({point_in_mask_metrics['n_inside_mask']}/{point_in_mask_metrics['n_annotated']})")

        # Handle no matched segments or annotations case
        if len(df_seg) == 0 or len(df_ann_subj) == 0:
            print(f"No segments or annotations for subject {subject}. Skipping matching and metric calculation.")
            all_metrics.append({
                'subject': subject,     
                'n_annotated': len(df_ann_subj),
                'n_cellpose': len(df_seg),
                'tp': 0,
                'fp': len(df_seg),
                'fn': len(df_ann_subj),
                'precision': 0.0,
                'recall': 0.0,
                'f1': 0.0,
                'accuracy': 0.0,
                'mean_dist_vx': None,
                'median_dist_vx': None,
                'std_dist_vx': None,
                'max_dist_vx': None,
                'distance_error_rate': None,
            } | point_in_mask_metrics)
            continue

        # HUNGARIAN MATCHING
        df_matches = hungarian_matching(df_ann_subj, df_seg)
        df_matches['subject'] = subject
        print(f"Matches found: {df_matches['matched'].sum()}")

        # CALCULATE METRICS
        metrics = calculate_metrics(df_ann_subj, df_seg, df_matches, subject)
        all_matches.append(df_matches)                                   
        all_metrics.append(metrics | point_in_mask_metrics)

    # Save
    if not all_matches:
        print("No matches to save.")
    else:
        df_all_matches = pd.concat(all_matches, ignore_index=True)
        df_all_matches.to_csv(f"results/{dataset}/{args.output_prefix}_{mask_3D}_evaluation_matches.csv", index=False)

    if not all_metrics:
        print("No metrics to save.")
    else:
        df_all_metrics = pd.DataFrame(all_metrics)
        df_all_metrics.to_csv(f"results/{dataset}/{args.output_prefix}_{mask_3D}_evaluation_metrics.csv", index=False)

        numeric_cols = ['n_annotated', 'n_cellpose', 'tp', 'fp', 'fn',
                        'precision', 'recall', 'f1', 'accuracy',
                        'std_dist_vx', 'distance_error_rate', 
                        'coverage', 'n_inside_mask', 'n_outside_mask']
        mean_metrics = df_all_metrics[numeric_cols].mean()

        print(f"""
        {'='*50}
        {dataset} - SEGMENTATION EVALUATION METRICS MEAN ACROSS {len(all_metrics)} SUBJECTS
        3D Method: {(args.method_3D).upper() if args.method_3D else 'MERGED'}
        Dataset: {'CLEANED' if args.use_clean_data else 'RAW'}
        {'='*50}
        Annotated neurons         : {mean_metrics['n_annotated']:.1f}
        Cellpose segments         : {mean_metrics['n_cellpose']:.1f}
        {'='*50}
        Avg True  Positives (TP)      : {mean_metrics['tp']:.1f}
        Avg False Positives (FP)      : {mean_metrics['fp']:.1f}   ← cellpose, no annotation
        Avg False Negatives (FN)      : {mean_metrics['fn']:.1f}   ← annotated, not detected
        {'='*50}
        Precision                 : {mean_metrics['precision']:.3f}
        Recall                    : {mean_metrics['recall']:.3f}
        F1 Score                  : {mean_metrics['f1']:.3f}
        Accuracy (Jaccard)        : {mean_metrics['accuracy']:.3f}
        {'='*50}
        Centroid Distance (matched pairs):
        Std                     : {mean_metrics['std_dist_vx']:.2f} vx
        Distance Error Rate       : {mean_metrics['distance_error_rate']:.3f}
        (frac. annotations > {10} vx from matched segment)
        {'='*50}
        Points inside mask          : {mean_metrics['n_inside_mask']:.1f}
        Points outside mask         : {mean_metrics['n_outside_mask']:.1f}
        Point-in-Mask Coverage    : {mean_metrics['coverage']:.3f}
        (frac. annotated neurons with centroid inside any cellpose segment)
        {'='*50}
        """)

    if args.plot_samples:
        print("Sampling data for plotting...")
        if args.use_clean_data:
            test_data, img_data = load_clean_data(dataset, args.csv_col_suffix, sample_size=3)
        else:
            test_data, img_data = load_raw_data(dataset, sample_size=3)

        subjects = [d['subject'] for d in test_data]

        sample_masks = []
        for s in subjects:
            mask = df_segments.loc[df_segments['subject'] == s, mask_3D].values[0]
            sample_masks.append(mask)
        
        plot_3d_mip_with_masks(img_data, sample_masks, args.output_prefix, dataset, mask_3D)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_prefix", help="Prefix for output files")
    parser.add_argument("--gold_neurons", help="Path to gold standard neurons file")
    parser.add_argument("--csv_col_suffix", default="_aniso_raw", choices=["_aniso_raw", "_aniso", "_iso"], help="Suffix for ROI CSV column names")
    parser.add_argument("--method_3D", default="", help="3D method for evaluation")
    parser.add_argument("--use_clean_data", action="store_true", help="Whether to use cleaned .npy files instead of raw NWB files")
    parser.add_argument("--plot_samples", action="store_true", help="Whether to plot sample MIPs with mask overlays")
    args = parser.parse_args()
    main(args)