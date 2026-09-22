# NeuroPAL ID

MATLAB software for viewing NeuroPAL images, detecting neuron centers, assigning and editing neuron identities, and tracking calcium activity through time.

**Current source for this fork: [akgohain/NeuroPAL_ID · main](https://github.com/akgohain/NeuroPAL_ID/tree/main).** This fork builds on [Yemini-Lab/NeuroPAL_ID](https://github.com/Yemini-Lab/NeuroPAL_ID). The instructions below launch the source version with the recent manual-ID, image-processing, and tracking fixes.

[Quick start](#quick-start) · [Manual identification](#manual-identification) · [Save and export](#save-and-export) · [Other workflows](#other-workflows) · [Documentation](#documentation)

## Quick start

### Requirements

The current source has been tested with **MATLAB R2024a on macOS**. Compatibility with older MATLAB releases and other operating systems has not been revalidated for the current changes.

Install these MATLAB toolboxes used by the app:

- Image Processing Toolbox
- Statistics and Machine Learning Toolbox
- Optimization Toolbox
- Parallel Computing Toolbox — optional for supported parallel operations

Bio-Formats, MatNWB, and mlapptools are included under `External_Dependencies`; startup adds them and the bundled reference data to the MATLAB path.

**Manual annotation does not require MoE or GAT checkpoints.** Python environments and external models are needed for the corresponding automated methods, video workers, and some importer fallbacks. See [Optional automated methods](#optional-automated-methods) when using those features.

### Download and launch

In a terminal:

```sh
git clone --branch main https://github.com/akgohain/NeuroPAL_ID.git
cd NeuroPAL_ID
```

Alternatively, use **Code → Download ZIP** on this fork's `main` branch and extract it.

In MATLAB, set **Current Folder** to the extracted or cloned `NeuroPAL_ID` directory, then run:

```matlab
run(fullfile('scripts', 'launch_visualize_light.m'))
```

On macOS or Linux, the terminal launcher is also available:

```sh
./scripts/launch_visualize_light.sh
```

It uses `MATLAB_BIN` when set, checks the standard macOS R2024a location, then looks for `matlab` on `PATH`. To select another installation:

```sh
MATLAB_BIN="/path/to/matlab" ./scripts/launch_visualize_light.sh
```

[Upstream compiled releases](https://github.com/Yemini-Lab/NeuroPAL_ID/releases) are a separate distribution and may not include this fork's changes. Use the source instructions above for this version.

### Update an existing checkout

Confirm that `git remote -v` points to **akgohain/NeuroPAL_ID** for `origin`, then, with a clean working tree:

```sh
git switch main
git pull --ff-only origin main
```

Restart the app after updating so MATLAB loads the new callbacks.

## Manual identification

1. Open a structural image through **File → Open** and use the **NeuroPAL ID** tab. Recent checks covered NeuroPAL MAT files, NWB, ND2, CZI, and TIFF/OME-TIFF examples; supported dimensions and metadata vary by importer.
2. Check the animal's body region, sex, age, and channel assignments. Confirm physical spacing when the importer asks for it. Use the Z slider and channel controls to inspect the image.
3. Select an existing neuron marker, or double-click an unmarked location in the slice viewer to add a center. Detection and **Neurons → Import neurons from…** are optional ways to populate centers.
4. Enter the name in **Neuron ID** beside **Review**, then click **Assign**. Select the neuron again to correct its name. A trailing `?`, such as `AVAL?`, records an uncertain identification.
5. Continue through the volume. Use **Help → Keyboard Shortcuts** for navigation and editing shortcuts.

Assigning names saves the annotation state to the companion `<image>_ID.mat` file. Reopen the image to resume. Keep the converted image MAT file and its `_ID.mat` companion together when moving your working session.

## Save and export

| Purpose | Control or file | Result |
| --- | --- | --- |
| Resume editing | `<image>_ID.mat`, saved during annotation edits | Neuron centers, manual IDs, predictions, and detector parameters; used with the image MAT file. |
| Share a table of IDs | **Save: IDs**, or **Analysis → Save ID Info** | A CSV beside the image, using the same basename, with IDs, positions, and color measurements. |
| Share an annotated image | **Analysis → Save ID Image** | An illustration export for the selected slices/slabs. |
| Export an NWB file | **Analysis → Save .NWB** | Image and selected annotation content, with acquisition metadata entered in the save dialog. |

The CSV export asks whether to rerun Auto-ID first. Choose **No** to export the current manual annotations without running a model. The `_ID.mat` file is the editable annotation state; the CSV is an analysis/export table. Auto-ID-dependent columns may be unavailable when no Auto-ID has been run.

Image import can create a converted `.mat` file alongside the source. Use a writable working folder with room for that conversion and subsequent exports. See [large-file handling](LARGE_FILE_IO.md) for memory, disk, and format limits.

## Other workflows

| Tab | Workflow | Guide |
| --- | --- | --- |
| **NeuroPAL ID** | Detect centers, run optional Auto-ID, and review or assign identities manually. | [Method integration](AUTO_ID_INTEGRATION.md) |
| **Image Processing** | Inspect channels and histograms; preview processing and geometry changes; save the processed image and associated annotations. | [Processing and large-file behavior](LARGE_FILE_IO.md#main-image-loading-and-processing) |
| **Video Tracking** | Detect reference neurons → track with ZephIR → review coordinates and extract/export activity. | [Calcium workflow](docs/bedant-reference-detection.md) |
| **Log** | Inspect messages and errors from the current session. | Include relevant messages when reporting a problem. |

For recordings with both structural NeuroPAL and calcium data, see the [paired NeuroPAL/calcium workflow](docs/paired-neuropal-calcium.md). It covers reference detection, Auto-ID, alignment, named tracking, and activity export.

### Optional automated methods

Choose a method in the app and configure its interpreter/model paths through **Settings…**. Checkpoint-backed methods need their model assets installed separately; cloning this repository does not install those weights.

- **MoE detection:** [installation, bundle requirements, and validation](MOE_INTEGRATION.md).
- **Other detectors and Auto-ID:** [adapter configuration and method status](AUTO_ID_INTEGRATION.md), plus [model bundle manifests](method_bundles/README.md).
- **ZephIR and activity extraction:** [calcium workflow and validation](docs/bedant-reference-detection.md).

Python requirements depend on the selected method. The repository includes [general requirements](requirements.txt), [macOS requirements](requirements-macos.txt), [detection requirements](requirements-detection.txt), and [MoE requirements](requirements-moe.txt); use the relevant method guide and a dedicated environment. Review model suggestions and tracks before interpreting them biologically.

## Documentation

- [Bundled software instructions](Data/Documents/Instructions.pdf) and [keyboard shortcuts](Data/Documents/Keyboard.pdf).
- [Earlier interface screenshots and guide](docs/legacy-interface-guide.md) — retained for reference; some menus have changed.
- [Large-file conversion and export](LARGE_FILE_IO.md).
- [Performance notes](PERFORMANCE.md).
- [UI development](UI_DEVELOPMENT.md).
- [Contributing](CONTRIBUTIONS.md) and [code of conduct](CONDUCT.md).

### NeuroPAL references and example data

- [Quick Start Guide to NeuroPAL](https://www.dropbox.com/s/t8c0tv073z8p9c8/README%201st%20-%20Quick%20Start%20Guide%20to%20NeuroPAL%20v1.pdf?dl=0)
- [NeuroPAL Software Manual](https://www.dropbox.com/s/idjkptbwrysj6t1/NeuroPAL%20Software%20Manual%20v1.pdf?dl=0)
- [Configuring Your Microscope for NeuroPAL](https://www.dropbox.com/s/8ku51tg7oc00ah6/Configuring%20Your%20Microscope%20for%20NeuroPAL%20v3.pdf?dl=0)
- [NeuroPAL Reference Manual](https://www.dropbox.com/s/pxnvow2464m5pcu/NeuroPAL%20Reference%20Manual%20v1.pdf?dl=0)
- [OH15500 ID Reference Manual](https://www.dropbox.com/s/swhb063ybjbdls1/OH15500%20ID%20Reference%20Manual%20v1.pdf?dl=0)
- [NeuroPAL microscope settings](https://www.dropbox.com/s/eerdh8ef294vq1l/NeuroPAL%20Microscope%20Settings.zip?dl=0)
- [Reporters and neuron colors](https://www.yeminilab.com/s/NeuroPAL-Colors-dd2t.pdf), [tested reporters](https://www.yeminilab.com/s/Reporters-Tested-for-NeuroPAL-v2.pdf), and [fluorophore landmarks](https://www.dropbox.com/s/vo2br4q527lymwt/Landmarks.zip?dl=0)
- [Metabotropic receptor reporters](https://www.dropbox.com/s/qiptk26yqkncyq0/Metabotropic-Receptors.zip?dl=0) and [panneuronal GCaMP6s/TagRFP-T reporters](https://www.dropbox.com/s/aumzqge4b60jmqj/Panneuronal.zip?dl=0)
- [Practice images from the manuals](https://zenodo.org/record/4516558), [NeuroPAL example volumes](https://zenodo.org/record/3906530), and the [NeuroPAL Zenodo community](https://zenodo.org/communities/neuropal/)
- [3D NeuroPAL atlas](https://www.opensourcebrain.org/projects/neuropal)

## Citation and credits

Please cite [Yemini et al., *NeuroPAL: A Multicolor Atlas for Whole-Brain Neuronal Identification in C. elegans*, Cell (2021)](https://doi.org/10.1016/j.cell.2020.12.012). Software citation metadata is available in [CITATION.cff](CITATION.cff).

```bibtex
@article{Yemini2021NeuroPAL,
  title = {NeuroPAL: A Multicolor Atlas for Whole-Brain Neuronal Identification in {C. elegans}},
  author = {Yemini, Eviatar and Lin, Albert and Nejatbakhsh, Amin and Varol, Erdem and Sun, Ruoxi and Mena, Gonzalo E. and Samuel, Aravinthan D. T. and Paninski, Liam and Venkatachalam, Vivek and Hobert, Oliver},
  journal = {Cell},
  year = {2021},
  volume = {184},
  number = {1},
  pages = {272--288.e11},
  doi = {10.1016/j.cell.2020.12.012}
}
```

See the [upstream contributors](https://github.com/Yemini-Lab/NeuroPAL_ID/graphs/contributors) and [contributors to this fork](https://github.com/akgohain/NeuroPAL_ID/graphs/contributors).

Additional contributions acknowledged by the original project:

- **Venkatachalam Lab:** James Yu, Vivek Venkatachalam, Maedeh Seyedolmohadesin.
- **Kimura Lab:** Chentao Wen, Koutarou D. Kimura.

Related methods: [3DeeCellTracker](https://elifesciences.org/articles/59187) and [ZephIR](https://www.biorxiv.org/content/10.1101/2022.07.18.500485v1).

## License

[Creative Commons Attribution-NonCommercial-ShareAlike 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). See [LICENSE.txt](LICENSE.txt).
