%% 1. First run of planes 2, 7, 14

current_plane = 7;

pstr = sprintf("plane_0%d", current_plane);
data_path = fullfile('D:\W2_DATA\kbarber\2025_03_01\assembled\h5');
h5_file = fullfile(data_path, pstr + ".h5");

metadata = read_h5_metadata(h5_file, '/');
save_path = fullfile(data_path, '../extract_v2');
mkdir(save_path);

M = h5read(h5_file, '/mov');

%%

config=[];
config = get_defaults(config); 
config.avg_cell_radius=7;
config.num_partitions_x = 1;
config.num_partitions_y = 1;
config.visualize_cellfinding = 1;
config.hyperparameter_tuning_flag = 1;
config.max_iter = 5;
config.cellfind_max_steps = 500; % 1000 takes ~10min
config.cellfind_min_snr=1;
config.thresholds.T_min_snr=4;
output=extractor(M,config);
%% Save results
sname = fullfile(save_path, pstr + "_outputs" + ".h5");
save_extract_outputs_h5(output, sname)
%% Load and test loaders/savers
plot_output_cellmap(output,[],[],'clim_scale',[0, 0.999])
output2match = load_extract_outputs_h5(sname);
plot_output_cellmap(output2match,[],[],'clim_scale',[0, 0.999])

%% 2. Trying to get the highly overlapping pixels to merge

current_plane = 14;

pstr = sprintf("plane_%d", current_plane);
data_path = fullfile('D:\W2_DATA\kbarber\2025_03_01\assembled\h5');
h5_file = fullfile(data_path, pstr + ".h5");

metadata = read_h5_metadata(h5_file, '/');
save_path = fullfile(data_path, '../extract_v2');
mkdir(save_path);

M = h5read(h5_file, '/mov');

config = get_defaults([]);
config.downsample_time_by = 4;
config.spatial_lowpass_cutoff = 1;
config.use_gpu = 0;
config.max_iter = 10;
config.cellfind_min_snr = 0;
config.thresholds.T_min_snr = 3.2;
config.thresholds.spatial_corrupt_thresh = 5;
config.thresholds.T_dup_corr_thresh = 0.8;
config.adaptive_kappa = 2;
config.kappa_std_ratio = 1;
output = extractor(M,config);

sname = fullfile(save_path, pstr + "_outputs_v2" + ".h5");
save_extract_outputs_h5(output, sname)
