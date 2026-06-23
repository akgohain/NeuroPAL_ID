# YOLO → Fusion → L/W Filter → MATLAB

How to run **inference**, **3D fusion** (with MATLAB export), and **post-fusion L/W filtering** for data16 neuroPAL volumes.

**Scripts (in this folder):**

| Step | Script |
|------|--------|
| 1. Inference | `infer_volume_slices_yolo.py` |
| 2. Fusion + `.mat` | `mip_centroids_iou_color_fuse.py` |
| 3. **L/W filter** | **`filter_fused_neurons_lw_um.py`** |

---

## Setup

```bash
cd /scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell
source /scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuropal_env/bin/activate
```

**Paths (edit for your worm):**

```bash
VOLUME="/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/final_experimental_data_16/anisotropic/000715_sub-20-YAaLR_anisotropic.npy"
WEIGHTS="/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/results/final_exp_715_541_cellpose2d_volume_holdout_stretched_e200/weights/best.pt"
OUT_DIR="/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/neuroPAL-detection/yolov8-cell/results/my_worm_run"
mkdir -p "${OUT_DIR}"
```

**Recommended settings (data16 cohort analysis):**

| Parameter | Value |
|-----------|-------|
| YOLO conf | **0.45** |
| Fusion | IoU-color, `iou_min=0.5`, `fuse_max_dz=1`, `--no-color-match` |
| Voxel spacing | `0.4 0.4 1.5` µm |
| L/W band (fixed) | **L [3.5, 7.5] × W [3.5, 7.5] µm** (~67% keep) |

**Fusion kwargs must match between step 2 and step 3.**

---

## Step 1 — Inference

Runs YOLO on every Z slice. Output: `predictions_summary.json` + per-slice PNGs.

**On GPU node** (use `device=0`, not `gpu` — Ultralytics API):

```bash
/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/wormId_project/.venv/bin/python \
  infer_volume_slices_yolo.py \
  --volume "${VOLUME}" \
  --weights "${WEIGHTS}" \
  --out_dir "${OUT_DIR}/infer_conf045" \
  --conf 0.45 \
  --imgsz 640 \
  --device 0 \
  --stretch_slices --p_lo 2 --p_hi 98 \
  --voxel-spacing-um 0.4 0.4 1.5 \
  --scale-bar-um 10
```

**Output:** `${OUT_DIR}/infer_conf045/predictions_summary.json`

---

## Step 2 — Fusion + MATLAB export

Fuses slice boxes into 3D neurons (IoU across Z). Exports NeuroPAL GUI `.mat` for MATLAB.

```bash
python mip_centroids_iou_color_fuse.py \
  --summary "${OUT_DIR}/infer_conf045/predictions_summary.json" \
  --volume "${VOLUME}" \
  --out_png "${OUT_DIR}/fused_mip.png" \
  --stretch_mip \
  --device gpu \
  --fuse-max-dz 1 \
  --iou-min 0.5 \
  --no-color-match \
  --crop-z-to-summary \
  --voxel-spacing-um 0.4 0.4 1.5 \
  --depth-sanity-ratio-cap 1.5 \
  --export-neuropal-gui-mat "${OUT_DIR}/fused_neuropal.mat"
```

**Outputs:**

| File | Use |
|------|-----|
| `fused_neuropal.mat` | Open in `visualize_light` (has `data`, `info`, `yolo_fused_ctr6`, …) |
| `fused_neuropal_ID.mat` | Auto-written sidecar (detection IDs) |
| `fused_mip.png` | QC image |

**Note:** This step does **not** apply L/W size filtering.

---

## Step 3 — L/W filter (post-fusion)

**Script:** `filter_fused_neurons_lw_um.py`

Reads the **same** `predictions_summary.json`, re-fuses with identical settings, then keeps fused clusters whose **XY envelope L and W** (µm) fall in band:

```
keep if  L_min ≤ L ≤ L_max  AND  W_min ≤ W ≤ W_max
```

Filter is on **fused XY size only** — Z is not band-filtered.

### Fixed band (recommended: [3.5, 7.5])

```bash
python filter_fused_neurons_lw_um.py \
  --summary "${OUT_DIR}/infer_conf045/predictions_summary.json" \
  --out-summary "${OUT_DIR}/predictions_summary_lw_3p5_7p5.json" \
  --out-fused-json "${OUT_DIR}/fused_lw_records.json" \
  --stats-json "${OUT_DIR}/lw_filter_stats.json" \
  --hist-png "${OUT_DIR}/lw_hist_3p5_7p5.png" \
  --fuse-mode iou-color \
  --fuse-max-dz 1 \
  --iou-min 0.5 \
  --no-color-match \
  --crop-z-to-summary \
  --voxel-spacing-um 0.4 0.4 1.5 \
  --filter-mode fixed \
  --min-l-um 3.5 --max-l-um 7.5 \
  --min-w-um 3.5 --max-w-um 7.5 \
  --mat-in "${OUT_DIR}/fused_neuropal.mat" \
  --mat-out "${OUT_DIR}/fused_neuropal_lw_filtered.mat"
```

**Outputs:**

| File | Contents |
|------|----------|
| `predictions_summary_lw_3p5_7p5.json` | Filtered summary (slice boxes from kept clusters only) |
| `fused_lw_records.json` | Per-neuron L/W, keep/reject reason |
| `lw_filter_stats.json` | Counts, cutoffs, percentiles |
| `fused_neuropal_lw_filtered.mat` | Same `.mat` structure, rows matching kept neurons |

Use **`fused_neuropal_lw_filtered.mat`** in MATLAB after filtering.

### Percentile band (per-worm adaptive)

```bash
python filter_fused_neurons_lw_um.py \
  --summary "${OUT_DIR}/infer_conf045/predictions_summary.json" \
  --out-summary "${OUT_DIR}/predictions_summary_lw_p25_75.json" \
  --fuse-mode iou-color --fuse-max-dz 1 --iou-min 0.5 --no-color-match \
  --crop-z-to-summary --voxel-spacing-um 0.4 0.4 1.5 \
  --filter-mode percentile --lw-p-lo 25 --lw-p-hi 75 \
  --mat-in "${OUT_DIR}/fused_neuropal.mat" \
  --mat-out "${OUT_DIR}/fused_neuropal_p25_75.mat"
```

### Other bands (from cohort analysis)

| Band (µm) | Pooled keep @ conf 0.45 | When to use |
|-----------|-------------------------|-------------|
| [2.5, 5] × [2.5, 5] | ~30% | Moderate QC |
| p25–p75 [4.1, 6.2] × [4.5, 6.9] | ~35% | Data-driven |
| **[3.5, 7.5] × [3.5, 7.5]** | **~67%** | **≥60% keep goal** |
| [2, 4] × [2, 4] | ~12% | Strict; hurts 981/714 |

---

## Step 4 (optional) — Re-fuse / viz on filtered summary

After filtering, run fusion viz again on the **filtered** summary for QC MIPs:

```bash
python mip_centroids_iou_color_fuse.py \
  --summary "${OUT_DIR}/predictions_summary_lw_3p5_7p5.json" \
  --volume "${VOLUME}" \
  --out_png "${OUT_DIR}/fused_mip_after_lw_filter.png" \
  --stretch_mip --device gpu \
  --fuse-max-dz 1 --iou-min 0.5 --no-color-match \
  --crop-z-to-summary --voxel-spacing-um 0.4 0.4 1.5
```

Or use the axis MIP grid script:

```bash
DEVICE=cpu CONF_SWEEP="0.45" L_BANDS="3.5:7.5" W_BANDS="3.5:7.5" \
  bash run_data16_pipeline.sh viz-grid sample 000715__000715_sub-20-YAaLR_anisotropic
```

---

## Batch (96 worms) via shell wrapper

```bash
# Infer all @ conf 0.45 (GPU node, DEVICE=0)
CONF=0.45 INFER_SUBDIR=infer_conf045 DEVICE=0 \
  bash run_data16_pipeline.sh infer all

# Cohort stats
INFER_SUBDIR=infer_conf045 bash run_data16_pipeline.sh stats all

# Verify keep rate for a band
CONF_SWEEP="0.45" L_BANDS="3.5:7.5" W_BANDS="3.5:7.5" \
  bash run_data16_pipeline.sh optimize all
```

Infer root: `results/infer_datasets_data16_all/<slug>/infer_conf045/`

---

## Pipeline diagram

```
.npy volume
    │
    ▼
infer_volume_slices_yolo.py          ← YOLO slice detections
    │  predictions_summary.json
    ▼
mip_centroids_iou_color_fuse.py      ← 3D IoU fusion + fused_neuropal.mat
    │
    ▼
filter_fused_neurons_lw_um.py        ← L/W µm filter + fused_neuropal_lw_filtered.mat
    │  predictions_summary_lw_*.json
    ▼
MATLAB visualize_light / downstream
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `device=gpu` fails on infer | Use `--device 0` (Ultralytics); `gpu` only works in `mip_centroids_*` / `viz_*` |
| CUDA not available | Run on GPU node (`srun --gres=gpu:1`), not login node |
| Filter removes too many | Widen band (e.g. [3.5, 7.5]); 981/714 need larger W than [2.5, 5] |
| `.mat` row count mismatch | Pass same `--mat-in` from step 2 to `--mat-out` in step 3 |
| Fusion/filter disagree | Use **identical** `--fuse-mode`, `--iou-min`, `--fuse-max-dz`, `--no-color-match`, `--voxel-spacing-um` |

---

## Related docs

- Full pipeline reference: `YOLO_PIPELINE.md`
- Cohort L/W analysis: `results/DATA16_LW_CONF_ANALYSIS.md`
- Filter script source: `filter_fused_neurons_lw_um.py`
