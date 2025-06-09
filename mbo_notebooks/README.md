# Miller Brain Observatory: EXTRACT Pipeline

This pipeline accepts h5 timeseries as inputs.

The red spots in the output masks are bright values:
- rather than black (low intensity) -> white (high intensity), 
the high intensity values are red.
- this is a *red-to-gray* colormap

## Key Parameters

- Low SNR: Increase spatial corruption threshold (up to 5.0)
- cellfind_min_snr: Lowering this will pick up more low-SNR cells