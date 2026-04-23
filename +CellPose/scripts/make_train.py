import os, argparse
import numpy as np
from cellpose import io, transforms


def main():
    parser = argparse.ArgumentParser(
        description='Extract all 2D slices from a 3D annotation image across YX, ZY, and ZX planes. '
                    'Assumes image is ZXYC unless specified otherwise using --channel_axis and --z_axis.'
    )

    input_img_args = parser.add_argument_group("input image arguments")
    input_img_args.add_argument('--dir', default=[], type=str,
                                help='folder containing annotation images to slice.')
    input_img_args.add_argument('--image_path', default=[], type=str,
                                help='path to a single annotation image.')
    input_img_args.add_argument('--look_one_level_down', action='store_true',
                                help='run processing on all subdirectories of current folder.')
    input_img_args.add_argument('--img_filter', default=[], type=str,
                                help='end string filter for images to run on.')
    input_img_args.add_argument('--channel_axis', default=-1, type=int,
                                help='axis corresponding to image channels.')
    input_img_args.add_argument('--z_axis', default=0, type=int,
                                help='axis corresponding to the Z dimension.')
    input_img_args.add_argument('--n_samples', default=None, type=int,
                                help='number of random slices to save per plane per image.')

    args = parser.parse_args()

    # --- Collect image paths ---
    imf = args.img_filter if len(args.img_filter) > 0 else None

    if len(args.dir) > 0:
        image_names = io.get_image_files(args.dir, "_masks", imf=imf,
                                         look_one_level_down=args.look_one_level_down)
        dirname = args.dir
    else:
        if os.path.exists(args.image_path):
            image_names = [args.image_path]
            dirname = os.path.split(args.image_path)[0]
        else:
            raise ValueError(f"ERROR: no file found at {args.image_path}")

    # --- Output folder ---
    if len(image_names) == 1:
        name0 = os.path.splitext(os.path.split(image_names[0])[-1])[0]
        out_dir = os.path.join(dirname, f'train_annotations_{name0}/')
        os.makedirs(out_dir, exist_ok=True)
    else:
        out_dir = os.path.join(dirname, 'train_annotations/')
        os.makedirs(out_dir, exist_ok=True)

    # Plane definitions: transpose order and name
    pm  = [(0, 1, 2, 3), (2, 0, 1, 3), (1, 0, 2, 3)]
    npm = ["YX",          "ZY",          "ZX"        ]

    for name in image_names:
        name0 = os.path.splitext(os.path.split(name)[-1])[0]

        # Read 3D annotation volume
        if 'clean' in name:
            data = np.load(name).astype(np.float32)   # (X, Y, Z, C)
            # Drop W channel (index 3)
            img0 = data[:, :, :, :3]
        else:
            img0 = io.imread_3D(name)
        try:
            img0 = transforms.convert_image(img0, channel_axis=args.channel_axis,
                                            z_axis=args.z_axis, do_3D=True)
        except ValueError:
            print(f"Error converting {name0}. Check --channel_axis and --z_axis.")
            continue

        for p in range(3):
            img = img0.transpose(pm[p]).copy()  # shape: (N_slices, Ly, Lx, C)
            n_slices = img.shape[0]
            print(f"{name0} | plane={npm[p]} | slices={n_slices} | shape={img[0].shape}")

            if args.n_samples:
                print(f"Randomly sampling {args.n_samples} slices from {n_slices} total slices.")
                n_slices_random = np.random.choice(n_slices, min(args.n_samples, n_slices), replace=False)
            else:
                n_slices_random = range(n_slices)

            for k in n_slices_random:
                out_path = os.path.join(out_dir, f"{name0}_{npm[p]}_{k}.tif")
                io.imsave(out_path, img[k].squeeze())  # squeeze removes trailing C dim if size=1

    print(f"\nDone. All slices saved to: {out_dir}")


if __name__ == '__main__':
    main()