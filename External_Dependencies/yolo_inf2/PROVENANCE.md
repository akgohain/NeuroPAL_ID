# YOLO INF 2 Snapshot

This directory vendors the YOLO detection implementation from:

```text
/groups/troidl/home/gohaina/neuropal/YOLO INF 2.zip
```

Zip SHA256:

```text
32b95ec66ee14cb99e9383341ea737f9188d9319e6f0277cca36c0875885c7f3
```

## Files From The Zip

| File | SHA256 |
| --- | --- |
| `MATLAB_PIPELINE_RUN.md` | `bbce52d97f0bf87ff757facfec13c8150762a0f084f468e6e6e1c22ef3a8c4de` |
| `best.pt` | `987d66691f0d6ae3f3b0ae514bc11443d8ec41832c522c0ebb9ee918123f610f` |
| `filter_fused_neurons_lw_um.py` | `b0b55e7e895e0532899439ee91ddb2e8470e1b14afd3b1abc09a756a5d3bc5a4` |
| `infer_volume_slices_yolo.py` | `a0b89925fdfaa37f5828167af4cc5df74c0905eefbb897d18a4fde37eb26cc88` |
| `mip_centroids_iou_color_fuse.py` | `f6601b3ac7ff296f658e82268b1ffcc23fcecfb53fee956af0dd71d3420289cc` |

## Support Files

The zip's `filter_fused_neurons_lw_um.py` dynamically imports helper modules
that were not included in the archive. To make the snapshot runnable from this
benchmark repo, these helper files were copied from:

```text
/groups/troidl/home/gohaina/neuropal/neuroPAL-detection/yolov8-cell
```

| File | SHA256 |
| --- | --- |
| `mip_centroids_from_predictions_summary.py` | `362eec88b43b67d4018d6df8b7a1ffb0508c606ac9a7efb6b5911ffd64259226` |
| `viz_mip_merged_yellow_boxes.py` | `02a22063e8b346f4101cc922a3465d02f46a75c59a6bf36e86ed9e7a05a0d698` |

Use `scripts/run_yolo_inf2.sh provenance` to re-check the vendored snapshot.
