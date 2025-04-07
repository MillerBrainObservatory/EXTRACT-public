% setupEXTRACT();


clc;
M = 
config=[];
config = get_defaults(config); 
config.avg_cell_radius=7;
config.trace_output_option='no_constraint';
config.num_partitions_x=1;
config.num_partitions_y=1; 
config.use_gpu=0; 
config.max_iter = 10; 
config.cellfind_min_snr=0;
config.thresholds.T_min_snr=10;
output=extractor(M,config);