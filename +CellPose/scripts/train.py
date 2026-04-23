from pynwb import NWBHDF5IO
import os
import glob
import argparse
import time

import numpy as np
from cellpose import models, core, io, train
from pathlib import Path

def main(args):
    #Calculate runtime of cellpose and save results in npy file
    start_time = time.time()

    train_dir = args.train_dataset_path
    if not Path(train_dir).exists():
        raise FileNotFoundError("directory does not exist")

    test_dir = args.test_dataset_path # optionally you can specify a directory with test files (images and masks)

    masks_ext = args.masks_ext

    # list all image files
    files = [f for f in Path(train_dir).glob("*") if "_masks" not in f.name and "_flows" not in f.name and "_seg" not in f.name]

    if(len(files)==0):
        FileNotFoundError("No files found, did you specify the correct folder and extension?")
    else:
        print(f"{len(files)} files in folder:")

    for f in files:
        print(f.name)

    io.logger_setup() # run this to get printing of progress

    #Check if colab notebook instance has GPU access
    if core.use_gpu()==False:
        raise ImportError("No GPU access, change your runtime")

    if args.model_path:
        model = models.CellposeModel(pretrained_model=args.model_path, gpu=True)
    else:
        model = models.CellposeModel(gpu=True)

    model_name = args.save_model_name if args.save_model_name else args.train_dataset_path.split("/")[-1]
    print(f"Training Cellpose model with name: {model_name}")


    # default training params
    n_epochs = 100
    learning_rate = 1e-5
    weight_decay = 0.1
    batch_size = 1

    # get files
    output = io.load_train_test_data(train_dir, test_dir, mask_filter=masks_ext)
    train_data, train_labels, _, test_data, test_labels, _ = output
    # (not passing test data into function to speed up training)

    new_model_path, train_losses, test_losses = train.train_seg(model.net,
                                                                train_data=train_data,
                                                                train_labels=train_labels,
                                                                batch_size=batch_size,
                                                                n_epochs=n_epochs,
                                                                learning_rate=learning_rate,
                                                                weight_decay=weight_decay,
                                                                nimg_per_epoch=max(2, len(train_data)),
                                                                model_name=model_name)
    
    print(f"Model saved at: {new_model_path}")
    print(f"Training runtime: {(time.time() - start_time)/60:.2f} minutes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--train_dataset_path", help="Path to training dataset, with images and masks")
    parser.add_argument("--test_dataset_path", default=None, help="Path to test dataset, with images and masks (optional)")
    parser.add_argument("--model_path", default=None, help="Path to pretrained cellpose model (optional)")
    parser.add_argument("--save_model_name", default=None, help="Name to save cellpose model, saved in the models folder")
    parser.add_argument("--masks_ext", default="_seg.npy", help="Extension for mask files (default: _seg.npy)")
    args = parser.parse_args()
    main(args)