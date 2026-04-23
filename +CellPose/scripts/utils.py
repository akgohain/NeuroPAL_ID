from pynwb import NWBHDF5IO
import os
import glob
import argparse
import time

import numpy as np
from cellpose import models, core, io
import random

MAX_ID = "20221014"
CLEAN_INPUT_DIR_ANISO  = "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/cleaned_data_run_4/anisotropic"
CLEAN_INPUT_DIR_ISO    = "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/cleaned_data_run_4/isotropic"
RAW_INPUT_DIR    = "/scratch/workspace/anshitagupta_umass_edu-ai-neuropal/dataset/"
random.seed(42)

def load_nwb_files(data_dir):

    """
    Returns a list[tuple[str, str, str]] - Each tuple is (dataset_id, subject_name, nwb_file_path).
    """

    all_nwb_files = []
 
    for subfolder in sorted(os.listdir(data_dir)):

        if not subfolder.startswith("sub-"):
            continue
        subfolder_path = os.path.join(data_dir, subfolder)

        subject_id = subfolder.split("-")[1]
        # Apply filter ONLY for 000981
        if "000981" in data_dir and int(subject_id) > int(MAX_ID):
            continue

        nwb_path = None
        for fname in os.listdir(subfolder_path):
            if fname.endswith(".nwb"):
                nwb_path = os.path.join(subfolder_path, fname)
                break
        if nwb_path:
            all_nwb_files.append((data_dir, subfolder, nwb_path))

    print(f"Found {len(all_nwb_files)} NWB files total\n")
    return all_nwb_files

def helper_load_and_standardize_dimension(nwb_path, dataset):

    """
    Returns
    -------
    data  : np.ndarray  shape (X, Y, Z, 4)  dtype from file
    """

    io = NWBHDF5IO(nwb_path, "r")
    nwb = io.read()
 
    imaging_data = nwb.acquisition["NeuroPALImageRaw"]
    data = imaging_data.data[...]
    rgbw_channels = imaging_data.RGBW_channels[:]
 
    io.close()
 
    if "000715" in dataset:
        # Already (X, Y, Z, channels) — just extract RGBW
        data = data[:, :, :, rgbw_channels]
    elif "000981" in dataset:
        # (channels, Z, X, Y)  - (X, Y, Z, channels)
        data = np.transpose(data, (2, 3, 1, 0))
        data = data[:, :, :, rgbw_channels]
 
    print(f"  Standardized shape (X, Y, Z, RGBW): {data.shape}")
 
    return data

def raw_to_uint8(data, dataset):
    if "000715" in dataset:
        scale = np.iinfo(np.uint8).max / np.iinfo(np.uint16).max
        return np.clip(
            np.round(data.astype(np.float32) * scale), 0, 255
        ).astype(np.uint8)
    return data.astype(np.uint8)

def load_raw_data(current_dataset, sample_size=None, display_stats=True):
    """
    Loads NWB files, extracts and standardizes imaging data to shape (X, Y, Z, RGBW).
    Returns:
    - test_data: list of dicts with keys 'dataset' and 'subject'
    - img_data: list of np.ndarrays with shape (X, Y, Z, RGB)
    """

    data_dir = f"{RAW_INPUT_DIR}/{current_dataset}"

    all_nwb_files = load_nwb_files(data_dir)

    test_data = []
    img_data = []

    if sample_size is not None:
        all_nwb_files = random.sample(all_nwb_files, min(sample_size, len(all_nwb_files)))
 
    for dataset, subfolder, nwb_path in all_nwb_files:
        print(f"[{dataset}] {subfolder}")
        data = helper_load_and_standardize_dimension(nwb_path, dataset)
        data = raw_to_uint8(data, dataset)
        # Drop W channel (index 3)
        data = data[:, :, :, :3]
        
        if display_stats:
            # Print dataset stats
            print(f"  Datatype:       {data.dtype}")
            print(f"  Shape:          {data.shape}")                          # (X, Y, Z, 3)
            print(f"  Min:            {data.min()}, Max: {data.max()}")

            # Statistical summaries
            print(f"  Mean:           {data.mean():.4f}")                     # Average intensity
            print(f"  Std Dev:        {data.std():.4f}")                      # Spread of intensity values
            print(f"  Median:         {np.median(data):.4f}")                 # Middle intensity value

            # Memory
            print(f"  Size (MB):      {data.nbytes / 1e6:.2f} MB")           # Memory footprint
            print(f"  Num Elements:   {data.size}")                           # Total number of voxels x channels
            print(f"  Ndim:           {data.ndim}")                           # Number of dimensions (should be 4)

        test_data.append(dict(dataset=current_dataset, subject=subfolder))
        img_data.append(data)

    return test_data, img_data
    

def load_clean_data(current_dataset, output_prefix, sample_size=None, display_stats=True):
    """
    Loads pre-extracted .npy files containing standardized imaging data.
    Returns:
    - test_data: list of dicts with keys 'dataset' and 'subject'
    - img_data: list of np.ndarrays with shape (X, Y, Z, RGB)
    """

    data_dir = CLEAN_INPUT_DIR_ANISO if "aniso" in output_prefix else CLEAN_INPUT_DIR_ISO
    
    # Discovering available files 
    all_npy_files = glob.glob(os.path.join(data_dir, "*.npy"))

    files_000715 = sorted([f for f in all_npy_files if "000715" in os.path.basename(f)])
    files_000981 = sorted([f for f in all_npy_files if "000981" in os.path.basename(f)])

    if "000715" in current_dataset:
        selected_files = files_000715
    else:
        selected_files = files_000981

    # Selecting samples 
    if sample_size is not None:
        selected_files = random.sample(selected_files, min(sample_size, len(selected_files)))

    test_data = []
    img_data = []

    for fpath in selected_files:
        basename = os.path.basename(fpath)
        parts    = basename.replace("_isotropic.npy", "").split("_", 1) if "_isotropic.npy" in basename else basename.replace("_anisotropic.npy", "").split("_", 1)
        dataset  = parts[0]
        subject  = parts[1] if len(parts) > 1 else basename

        print(f"[{dataset}] {subject}")

        data = np.load(fpath).astype(np.float32)   # (X, Y, Z, C)
        # Drop W channel (index 3)
        data = data[:, :, :, :3]

        if display_stats:
            # Print dataset stats
            print(f"  Datatype:       {data.dtype}")
            print(f"  Shape:          {data.shape}")                          # (X, Y, Z, 3)
            print(f"  Min:            {data.min()}, Max: {data.max()}")

            # Statistical summaries
            print(f"  Mean:           {data.mean():.4f}")                     # Average intensity
            print(f"  Std Dev:        {data.std():.4f}")                      # Spread of intensity values
            print(f"  Median:         {np.median(data):.4f}")                 # Middle intensity value

            # Memory
            print(f"  Size (MB):      {data.nbytes / 1e6:.2f} MB")           # Memory footprint
            print(f"  Num Elements:   {data.size}")                           # Total number of voxels x channels
            print(f"  Ndim:           {data.ndim}")                           # Number of dimensions (should be 4)
        test_data.append(dict(dataset=dataset, subject=subject))
        img_data.append(data)

    return test_data, img_data
