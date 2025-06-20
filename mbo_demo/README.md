# Miller Brain Observatory: EXTRACT Pipeline



# MBO Utilities – EXTRACT Demo Pipeline

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

Open `runEXTRACT.m` and set the path to your data folder:

```matlab
data_path = "D:\\tests\\data\\EXTRACT";
runEXTRACT(data_path);
```

Use double backslashes (`\\`) on Windows.

## Key Parameters

- Low SNR: Increase spatial corruption threshold (up to 5.0)
- cellfind_min_snr: Lowering this will pick up more low-SNR cells

## Output

Results, including demixed components and summaries, will be saved alongside your data, organized by ROI and z-plane.

See the mbo_utilities [documentation](https://millerbrainobservatory.github.io/mbo_utilities) for more details.

## Figures

The output plot showing segmentation results and masks looks atypical compared to other pipelines you may have seen.

There are red bright spots across the FOV.

- The red spots in the output masks are bright values.
- rather than black (low intensity) -> white (high intensity)
- the high intensity values are red.
- this is a *red-to-gray* colormap
