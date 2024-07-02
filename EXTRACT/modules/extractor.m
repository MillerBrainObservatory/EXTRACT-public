function output = extractor(M, config)
% Wrapper for EXTRACT for processing large movies

%This warning is not required thanks to Hakan's implementation of the preprocessing module.
%dispfun('Warning: If the input movie is in dfof form, please make sure to add 1 to the whole movie before running EXTRACT. \n',1)


% Get start time
start_time = posixtime(datetime);
io_time = 0;

ABS_TOL = 1e-6;
SIGNAL_LOWER_THRESHOLD = 1e-6;
PARTITION_SIDE_LEN = 512;

% Update config with defaults
config = get_defaults(config);

if ~exist('config', 'var') || ~isfield(config, 'avg_cell_radius') || ~isnumeric(config.avg_cell_radius)
    error('"config.avg_cell_radius" must be specified.');
end

if (config.parallel_cpu || config.multi_gpu) && ~(ischar(M) || iscell(M))
    error('Please input the movie as either a string or cell array.')
end

if (config.regression_only && isempty(config.S_init))
    error('If using EXTRACT as a post-processing tool, initialize the cell profiles within config.S_init.')
end

list_solvers = {'no_constraint','baseline_adjusted',...
'nonneg','least_squares','nonnegative_least_squares','none'};

if ~any(strcmp(list_solvers,config.trace_output_option))
    config.trace_output_option = "baseline_adjusted";
    warning('Chosen solver is not part of the available options. Using baseline_adjusted solver instead.')
end

%if ~exist('config', 'var') || ~isfield(config, 'trace_output_option')
%    error('"config.trace_output_option" must be specified. Pick "nonneg" for nonnegative output, pick "raw" for raw output.');
%end


do_auto_partition=1;
if isfield(config, 'num_partitions_x') && ...
        isfield(config, 'num_partitions_y')
    do_auto_partition=0;
end
partition_overlap = ceil(config.avg_cell_radius * 2);

num_workers = 0;

% Delete existing parpool if using multi-gpu
%if config.multi_gpu
%    p = gcp('nocreate');
%    delete(p);
%end

% Override the gpu flag if necessary + handle multi-gpu case
if config.use_gpu && ~config.use_default_gpu && ~config.skip_parpool_calculations
    dispfun(sprintf('%s: Getting GPU information... \n', datestr(now)),...
        config.verbose ~= 0);
    max_mem = 0;
    min_mem = inf;
    idx_max_mem = 0;
    c = gpuDeviceCount;
    if c == 0
        warning('No GPU device was detected -- Setting use_gpu = 0 ');
        config.use_gpu = 0;
    else
        gpuDevice([]);
        for idx_gpu = 1:c
            d = gpuDevice(idx_gpu);
            mem = d.AvailableMemory;
            dispfun(sprintf(...
                '\t \t \t GPU Device %d - %s: Available Memory: %.1f Gb\n', ...
                idx_gpu, d.Name, mem / 2^30), config.verbose ~= 0);
            min_mem = min(mem, min_mem);
            if mem > max_mem
                max_mem = mem;
                idx_max_mem = idx_gpu;
            end
        end
        if config.multi_gpu && c > 1
            avail_mem = min_mem;
            if isfield(config, 'num_workers')
                num_workers = min(c,config.num_workers);
            else
                num_workers = c;
            end
            % De-select last selected GPU
            gpuDevice([]);
            p = gcp('nocreate');
            if ~isempty(p)
                if p.NumWorkers ~=num_workers
                    delete(p);
                    parpool('local', num_workers);
                end
            else
                parpool('local', num_workers);    
            end
            dispfun(sprintf('%s: Using %d GPUs \n', ...
                datestr(now),num_workers), config.verbose ~= 0);
        else
            avail_mem = max_mem;
            if isempty(config.pick_gpu)
                gpuDevice(idx_max_mem);
            else
                gpuDevice(config.pick_gpu)
            end
            dispfun(sprintf('\t \t \t - Selecting GPU device %d \n', ...
                idx_max_mem), config.verbose ~= 0);
            config.multi_gpu = 0;
        end
    end
end

% Set num_workers for parallel computation on CPUs
if ~config.use_gpu && config.parallel_cpu == 1 && ~config.skip_parpool_calculations
    % Default # of parallel workers is # cores -1
    num_workers = feature('numCores') - 1;
    if isfield(config, 'num_workers')
        if config.num_workers > num_workers + 1
            try
            num_workers = config.num_workers;
                p = gcp('nocreate');
                if ~isempty(p)
                    if p.NumWorkers ~=num_workers
                        delete(p);
                        parpool('local', num_workers);
                    end
                else
                    parpool('local', num_workers);    
                end
            catch
                warning(['More parallel CPU workers than # of available ', ...
                    'cores requested -- Using max available = %d'], ...
                    feature('numCores'));
                num_workers = feature('numCores') - 1;
            end
        else
            num_workers = config.num_workers;
            dispfun(sprintf('%s: Setting up a pool with %d CPU workers... \n', datestr(now),num_workers),...
            config.verbose ~= 0);
        end
    end
    % Delete existing parpool if specs are different
    p = gcp('nocreate');
    if ~isempty(p)
        if p.NumWorkers ~=num_workers
            delete(p);
            parpool('local', num_workers);
        end
    else
        parpool('local', num_workers);    
    end
end

% Prevent plots when in parallel mode
if num_workers > 1
    config.plot_loss = 0;
    config.visualize_cellfinding = 0;
end

[h, w, ~] = get_movie_size(M);

npt = config.num_frames;
% Determine the movie partitions
if ~do_auto_partition
    npx = config.num_partitions_x;
    npy = config.num_partitions_y;
else
    % Account for downsampling
    dss = config.downsample_space_by;
    if strcmp(dss, 'auto') || isempty(dss)
        dss = max(round(config.avg_cell_radius / ...
            config.min_radius_after_downsampling), 1);
    end
    % If estimation of full S is desired after downsampling, set dss = 1
    if config.reestimate_S_if_downsampled
        dss = 1;
    end
    config.downsample_space_by = dss;
    h_adjusted = h / dss;
    w_adjusted = w / dss;
    npx = max(ceil(w_adjusted / PARTITION_SIDE_LEN), 1);
    npy = max(ceil(h_adjusted / PARTITION_SIDE_LEN), 1);
end

% Get a circular mask (for movies with GRIN)
if config.crop_circular
    if ischar(M) || iscell(M)
        error('To use the circular cropping feature, load the movie onto memory before calling EXTRACT.');
    else
        circular_mask = get_circular_mask(M);
        if isempty(config.movie_mask)
        	config.movie_mask = circular_mask;
        else
            % Apply user mask AND circular mask
            config.movie_mask = circular_mask & config.movie_mask;
        end
    end
end

if config.arbitrary_mask
    config.movie_mask = get_arbitrary_mask(M);
end


num_partitions = npx * npy;
fov_occupation_total = zeros(h, w);
summary_image = zeros(h,w);
F_per_pixel = zeros(h,w);
max_image = zeros(h,w);

summary = {};
S = {};
T = {};

time_upload = zeros(1,num_partitions);
time_run = zeros(1,num_partitions);

if config.parallel_cpu || config.multi_gpu
    dispfun(sprintf('%s: Signal extraction will run on %d partitions with %d parallel workers... \n', ...
            datestr(now), num_partitions,num_workers), config.verbose ~= 0);
    verbose_old = config.verbose;
    config.verbose = 0;
    fov_occupation_total_temp = zeros(h, w);
    if config.show_progress
        ppm = ParforProgressbar(num_partitions, 'progressBarUpdatePeriod', 60,'title', ...
            sprintf('Signal extraction will run on %d partitions with %d parallel workers... \n', ...
             num_partitions,num_workers));
    else
        ppm = [];
    end

    parfor (idx_partition = 1:num_partitions, num_workers)
        dispfun(sprintf('%s: Signal extraction on partition %d (of %d):\n', ...
            datestr(now), idx_partition, num_partitions), config.verbose ~= 0);
        
        
        dispfun(sprintf('\t \t \t Uploading the movie ... \n'), config.verbose == 2);

        start_upload = posixtime(datetime);
        % Get current movie partition from full movie
        [M_small, fov_occupation] = get_current_partition(...
            M, npx, npy, npt, partition_overlap, idx_partition);
        time_upload(idx_partition) = posixtime(datetime) - start_upload;
        
        % Sometimes partitions contain no signal. Terminate in that case
        std_M = nanstd(M_small(:));
        if std_M < SIGNAL_LOWER_THRESHOLD
            dispfun('\t \t \t No signal detected, terminating...\n', ...
                config.verbose ==2);
        end
        config_this = config;
        % If S_init is given, feed only part of it consistent with partition
        if ~isempty(config_this.S_init)
            S_init = config.S_init(fov_occupation(:), :);
            S_init(:, sum(S_init, 1)<=ABS_TOL) = [];
            config_this.S_init = S_init;
        end

        % If T_init is given, feed only part of it consistent with partition
        if ~isempty(config_this.T_init) && ~isempty(config_this.S_init)
            S_init_temp = config.S_init(fov_occupation(:), :);
            T_init = config.T_init;
            T_init(sum(S_init_temp, 1)<=ABS_TOL,:) = [];
            config_this.T_init = T_init;
        end

        % Distribute mask to partitions
        if ~isempty(config_this.movie_mask)
            [h_this, w_this, ~] = size(M_small);
            config_this.movie_mask = config_this.movie_mask(fov_occupation(:));
            config_this.movie_mask = reshape(config_this.movie_mask, h_this, w_this);
        end

        % Correct the F_per_pixel if it exists
        if isfield(config, 'F_per_pixel')
            [h_this, w_this, ~] = size(M_small);
            config_this.F_per_pixel = config_this.F_per_pixel(fov_occupation(:));
            config_this.F_per_pixel = reshape(config_this.F_per_pixel, h_this, w_this);
        end

        % Run EXTRACT for current partition
        [S_this, T_this, summary_this] = run_extract(M_small, config_this);
        dispfun(sprintf('\t \t \t Count: %d cells.\n', ...
            size(S_this, 2)), config.verbose == 2);

        % Un-trim the pixels
        if config.use_sparse_arrays
            S_temp = sparse(h * w, size(S_this, 2));
        else
            S_temp = zeros(h * w, size(S_this, 2), 'single');
        end
        S_temp(fov_occupation(:), :) = S_this;
        S_this = S_temp;

        % Update FOV-wide arrays, not possible for parallel cpu!
        %if isfield(summary_this, 'summary_image')
        %    F_per_pixel(fov_occupation(:)) = summary_this.config.F_per_pixel(:);
        %    summary_image(fov_occupation(:)) = summary_this.summary_image;
        %    max_image(fov_occupation(:)) = summary_this.max_image;
        %else
        %    summary_image(fov_occupation(:)) = max(M_small, [], 3);
        %    max_image(fov_occupation(:)) = max(M_small, [], 3);
        %end
        summary_this.fov_occupation = fov_occupation;
        summary{idx_partition} = summary_this;
        if ~isempty(S_this)
            S{idx_partition} = S_this;
            T{idx_partition} = T_this';
        end
        fov_occupation_total_temp = fov_occupation + fov_occupation_total_temp;
        time_run(idx_partition) = posixtime(datetime) - start_upload;
        dispfun(sprintf('\t \t %s: Partition %d finished. Upload time: %.1f mins. Total run time: %.1f mins. \n', datestr(now),...
            idx_partition,time_upload(idx_partition)/60,time_run(idx_partition)/60),...
            verbose_old ~= 0);
        if config.show_progress
            ppm.increment(); 
        end
    end
    if config.show_progress
        delete(ppm); 
    end
    fov_occupation_total  = fov_occupation_total_temp;
    config.verbose = verbose_old;

    if ~isfield(config, 'F_per_pixel')

        try
            for idx_partition_temp = 1:num_partitions
                summary_temp = summary{idx_partition_temp};
                fov_occupation_temp = summary_temp.fov_occupation;
                F_per_pixel(fov_occupation_temp(:)) = summary_temp.config.F_per_pixel(:);
                summary_image(fov_occupation_temp(:)) = summary_temp.summary_image;
                max_image(fov_occupation_temp(:)) = summary_temp.max_image;
            end
        catch
            dispfun(sprintf('%s: Summary image estimation failed. Moving on without one... \n', ...
                    datestr(now)), config.verbose ~= 0);
        end

    else

        try

            F_per_pixel = config.F_per_pixel;
            for idx_partition_temp = 1:num_partitions
                summary_temp = summary{idx_partition_temp};
                fov_occupation_temp = summary_temp.fov_occupation;
                summary_image(fov_occupation_temp(:)) = summary_temp.summary_image;
                max_image(fov_occupation_temp(:)) = summary_temp.max_image;
            end
        catch
            dispfun(sprintf('%s: Summary image estimation failed. Moving on without one... \n', ...
                    datestr(now)), config.verbose ~= 0);
        end


    end

else
    dispfun(sprintf('%s: Signal extraction will run on %d partitions serially... \n', ...
            datestr(now), num_partitions), config.verbose ~= 0);
    if config.show_progress
        progressbar(sprintf('Running EXTRACT on %d partitions',num_partitions));
    end
    for idx_partition = num_partitions:-1:1
        verbose_old = config.verbose;
        if verbose_old == 3
            config.verbose = 0;
        end
        dispfun(sprintf('%s: Signal extraction on partition %d (of %d):\n', ...
            datestr(now), idx_partition, num_partitions), config.verbose ~= 0);
        
        dispfun(sprintf('\t \t \t Uploading the movie... \n'), config.verbose == 2);

        start_upload = posixtime(datetime);
        % Get current movie partition from full movie
        [M_small, fov_occupation] = get_current_partition(...
            M, npx, npy, npt, partition_overlap, idx_partition);
        time_upload(idx_partition) = posixtime(datetime) - start_upload;
        dispfun(sprintf('\t \t \t Upload finished in %.1f minutes ... \n', time_upload(idx_partition)/60),config.verbose == 2);
        io_time = io_time + time_upload(idx_partition);

        % Sometimes partitions contain no signal. Terminate in that case
        std_M = nanstd(M_small(:));
        if std_M < SIGNAL_LOWER_THRESHOLD
            dispfun('\t \t \t No signal detected, terminating...\n', ...
                config.verbose ==2);
        end
        config_this = config;
        % If S_init is given, feed only part of it consistent with partition
        if ~isempty(config_this.S_init)
            S_init = config.S_init(fov_occupation(:), :);
            S_init(:, sum(S_init, 1)<=ABS_TOL) = [];
            config_this.S_init = S_init;
        end
        % If T_init is given, feed only part of it consistent with partition
        if ~isempty(config_this.T_init) && ~isempty(config_this.S_init)
            S_init_temp = config.S_init(fov_occupation(:), :);
            T_init = config.T_init;
            T_init(sum(S_init_temp, 1)<=ABS_TOL,:) = [];
            config_this.T_init = T_init;
        end
        % Distribute mask to partitions
        if ~isempty(config_this.movie_mask)
            [h_this, w_this, ~] = size(M_small);
            config_this.movie_mask = config_this.movie_mask(fov_occupation(:));
            config_this.movie_mask = reshape(config_this.movie_mask, h_this, w_this);
        end

        % Correct the F_per_pixel if it exists
        if isfield(config, 'F_per_pixel')
            [h_this, w_this, ~] = size(M_small);
            config_this.F_per_pixel = config_this.F_per_pixel(fov_occupation(:));
            config_this.F_per_pixel = reshape(config_this.F_per_pixel, h_this, w_this);
        end

        % Run EXTRACT for current partition
        [S_this, T_this, summary_this] = run_extract(M_small, config_this);
        dispfun(sprintf('\t \t \t Count: %d cells.\n', ...
            size(S_this, 2)), config.verbose ~= 0);

        % Un-trim the pixels
        if config.use_sparse_arrays
            S_temp = sparse(h * w, size(S_this, 2));
        else
            S_temp = zeros(h * w, size(S_this, 2), 'single');
        end
        S_temp(fov_occupation(:), :) = S_this;
        S_this = S_temp;

        % Update FOV-wide arrays
        if isfield(summary_this, 'summary_image')
            F_per_pixel(fov_occupation(:)) = summary_this.config.F_per_pixel(:);
            summary_image(fov_occupation(:)) = summary_this.summary_image;
            max_image(fov_occupation(:)) = summary_this.max_image;
        else
            summary_image(fov_occupation(:)) = max(M_small, [], 3);
            max_image(fov_occupation(:)) = max(M_small, [], 3);
        end
        summary_this.fov_occupation = fov_occupation;
        summary{idx_partition} = summary_this;
        if ~isempty(S_this)
            S{idx_partition} = S_this;
            T{idx_partition} = T_this';
        end
        fov_occupation_total = fov_occupation_total + fov_occupation;


        time_run(idx_partition) = posixtime(datetime) - start_upload;
        if verbose_old == 3
            fprintf('\t \t %s: Partition %d finished. Upload time: %.1f mins. Run time: %.1f mins. \n', ...
                datestr(now),idx_partition,time_upload(idx_partition)/60,time_run(idx_partition)/60);
            config.verbose = 3;
        end
        if config.show_progress
            progressbar((num_partitions-idx_partition+1)/num_partitions);
        end
    end
end

% Concatenate components from different partitions
S = cell2mat(S(~cellfun(@isempty, S)));
T = cell2mat(T(~cellfun(@isempty, T)));
summary = [summary{~cellfun(@isempty, summary)}];

try
    [cellcheck] = combine_metrics(summary);
catch
    %warning('cellcheck classification metrics have an issue 1/3.')
end


dispfun(sprintf('%s: Total of %d cells are found.\n', ...
    datestr(now),size(S,2)),config.verbose==2);

if config.remove_duplicate_cells
    dispfun(sprintf('%s: Removing duplicate cells...\n', ...
    datestr(now)), config.verbose == 2);
    
    
    if config.regression_only
        S_init = config.S_init;
        duplicate_flag = 1;
        cur_threshold = 1;
        while duplicate_flag == 1
            cur_threshold = cur_threshold - 0.01;
            if cur_threshold <0.01
                duplicate_flag = 0;
            end
            idx_match = match_sets(S_init,S,cur_threshold);
            if(size(idx_match,2) == size(S_init,2) )
                duplicate_flag = 0;
            end
        end
        S = S(:,idx_match(2,:));
        T = T(:,idx_match(2,:));
        dispfun(sprintf(...
        '%s: %d cells were retained after removing duplicates (cor_thresh = %.2f). \n', ...
        datestr(now), size(S, 2),cur_threshold), config.verbose ~=0);
    else
        overlap_idx = find(fov_occupation_total - 1);
        if ~isempty(S)
            idx_trash = find_duplicate_cells(S, T, overlap_idx,config.T_dup_thresh,config.T_corr_thresh,config.S_corr_thresh);
            S(:, idx_trash) = [];
            T(:, idx_trash) = [];
            try
                cellcheck.is_bad(idx_trash)=[];
                cellcheck.is_attr_bad(:,idx_trash)=[];
                cellcheck.metrics(:,idx_trash)=[];
            catch
                %warning('cellcheck classification metrics have an issue 2/3.')
            end
            
        end
        dispfun(sprintf(...
        '%s: %d cells were retained after removing duplicates.\n', ...
        datestr(now), size(S, 2)), config.verbose ~=0);
    end

    
end

% Get total runtime (minus time spent reading from disk)
end_time = posixtime(datetime);
total_runtime = end_time - start_time - io_time;

info.version = '1.3.0';
info.summary = summary;
info.runtime = total_runtime;
info.summary_image = summary_image;
info.F_per_pixel = F_per_pixel;
info.max_image = max_image;
info.upload_time = time_upload;
info.runtime_partition = time_run;
try
    info.cellcheck=cellcheck;
catch
    %warning('cellcheck classification metrics have an issue 3/3.')
end

if config.use_sparse_arrays
    % There are no 3-D sparse arrays -- use a FileExchange fn for storing
    S = ndSparse(S);
end
output.spatial_weights = reshape(S, h, w, size(S, 2));
output.temporal_weights = T;
output.info = info;
output.config = config;
dispfun(sprintf(...
        '%s: All done with EXTRACT! \n', ...
        datestr(now)), config.verbose ~=0);

end
