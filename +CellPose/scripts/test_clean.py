from pynwb import NWBHDF5IO
import os
import glob
import argparse
import time

import numpy as np
from cellpose import models, core, io

from utils import load_raw_data, load_clean_data

def main(args):
    #Calculate runtime of cellpose and save results in npy file
    start_time = time.time()

    if args.use_clean_data:
        test_data, img_data = load_clean_data(args.dataset, args.output_prefix)
    else:
        test_data, img_data = load_raw_data(args.dataset)

    io.logger_setup() # run this to get printing of progress

    #Check if colab notebook instance has GPU access
    if core.use_gpu()==False:
        raise ImportError("No GPU access, change your runtime")

    if args.model_path:
        model = models.CellposeModel(pretrained_model=args.model_path, gpu=True)
    else:
        model = models.CellposeModel(gpu=True)

    # 1. computes flows from 2D slices and combines into 3D flows to create masks
    masks, flows, _ = model.eval(
        img_data,
        z_axis=2,          
        channel_axis=3,   
        do_3D=True,
        flow3D_smooth=1,
        batch_size=4,
    )

    end_time = time.time()
    runtime_seconds = end_time - start_time
    print(f"Cellpose 3D Method runtime: {runtime_seconds/60:.2f} minutes")

    # 2. computes masks in 2D slices and stitches masks in 3D based on mask overlap
    print('running cellpose 2D + stitching masks')
    masks_stitched, flows_stitched, _ = model.eval(img_data,
                                                z_axis=2,
                                                channel_axis=3,
                                                batch_size=4,
                                                do_3D=False,
                                                stitch_threshold=0.5)

    end_time = time.time()
    runtime_seconds = end_time - start_time
    print(f"Cellpose Stiching Method runtime: {runtime_seconds/60:.2f} minutes")


    print(f"Input  shape: {len(img_data)}")     
    print(f"Masks  shape: {len(masks)}")   

    np.save(f"results/{args.output_prefix}_cellpose_neuropal.npy", {"masks": masks,
                                            "flows": flows, 
                                            "masks_stitched": masks_stitched, 
                                            "flows_stitched": flows_stitched,
                                            "subject": [d['subject'] for d in test_data],
                                            "dataset": [d['dataset'] for d in test_data]})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_prefix", help="Prefix for output file")
    parser.add_argument("--use_clean_data", action="store_true", help="Whether to use cleaned .npy files instead of raw NWB files")
    parser.add_argument("--dataset", choices=["000715", "000981"], help="Specify dataset (000715 or 000981)")
    parser.add_argument("--model_path", default=None, help="Path to cellpose model (optional)")
    args = parser.parse_args()
    main(args)