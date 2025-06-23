# Miller Brain Observatory: EXTRACT Pipeline Demo

This demo shows how to use the MBO Utilities pipeline to run EXTRACT on multi-plane imaging data.
It assumes your data is stored in HDF5 format, with each z-plane saved separately.

This pipeline accepts h5 timeseries as inputs.

## Installation

First, install `mbo_utilities` by following the guide [here](https://millerbrainobservatory.github.io/mbo_utilities/install.html).
Next, install EXTRACT-public via their [installation instructions](https://github.com/MillerBrainObservatory/EXTRACT-public?tab=readme-ov-file#installation).

## Data Extraction

Organize your dataset so that each z-plane is saved as a separate HDF5 file in the same folder.

Example:

```
D:/tests/data/EXTRACT/
├── plane1.h5
├── plane2.h5
├── ...
```

## Running the Pipeline

### Prep data

EXTRACT takes planar timeseries in `.h5` format as input.

The easiest way to get raw scanimage `.tif` into this format is using [mbo_utilities](https://millerbrainobservatory.github.io/mbo_utilities/install.html). 
This requires python, though its a simple installation and is well documented (see the [user-guide](https://millerbrainobservatory.github.io/mbo_utilities/assembly.html) on converting tiffs using these python utilities))

``` python
# Option 1: Stitch the roi's before saving
import mbo_utilities as mbo
volume = mbo.imread(r"path/to/raw_tiffs")
volume.shape
Out[4]: (5632, 14, 448, 448)
mbo.imwrite(volume, "D://extract_demo//stitched_rois", planes=[4, 7, 11, 14], ext="h5")
# Option 1: Save individual rois (will save every plane in an roiN folder)
volume.roi = 2
volume.shape
Out[7]: (5632, 14, 448, 224)
mbo.imwrite(volume, "D://extract_demo", planes=[4, 7, 11, 14], ext="h5")
```

![image](../docs/_images/demo1.png)
![image](../docs/_images/demo2.png)

### Run Extract

Open `runEXTRACT.m` and set the path to your data folder:

```matlab
data_path = "D://extract_demo//";
runEXTRACT(data_path);
```

Use double backslashes (`\\`) on Windows.

## Key Parameters

- Low SNR: Increase spatial corruption threshold (up to 5.0)
- cellfind_min_snr: Lowering this will pick up more low-SNR cells

## Output

Results, including demixed components and summaries, will be saved alongside your data, organized by ROI and z-plane.

## Figures

The output plot showing segmentation results and masks looks atypical compared to other pipelines you may have seen.

There are red bright spots across the FOV.

- The red spots in the output masks are bright values.
- rather than black (low intensity) -> white (high intensity)
- the high intensity values are red.
- this is a *red-to-gray* colormap
