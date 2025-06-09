function runEXTRACT(rootDir, savePlots)
% runEXTRACT  Run EXTRACT on every “planeN.h5” under rootDir.
%
%   runEXTRACT(rootDir)              – analyse and save H5 outputs only
%   runEXTRACT(rootDir, true|false)  – also save PNG cell-maps (default: true)

if nargin < 2, savePlots = true; end

files = dir(fullfile(rootDir, '**', 'plane*.h5'));
files = files(~contains({files.name}, 'output', 'IgnoreCase', true));
fprintf('Found %d plane files\n', numel(files));

for f = files'
    h5_file  = fullfile(f.folder, f.name);
    planeStr = erase(f.name, '.h5');
    saveDir  = fullfile(f.folder, 'outputs');
    if ~exist(saveDir, 'dir'), mkdir(saveDir); end
    saveFile = fullfile(saveDir, planeStr + "_outputs.h5");

    % ---------- load & preprocess ---------------------------------------
    M = permute(h5read(h5_file, '/mov'), [2 1 3]);   % (X,Y,T)

    % ---------- configure EXTRACT ---------------------------------------
    cfg = get_defaults([]);
    cfg.avg_cell_radius            = 7;
    cfg.num_partitions_x           = 1;
    cfg.num_partitions_y           = 1;
    cfg.visualize_cellfinding      = 1;
    cfg.hyperparameter_tuning_flag = 1;
    cfg.max_iter                   = 5;
    cfg.cellfind_max_steps         = 500;
    cfg.cellfind_min_snr           = 0;
    cfg.thresholds.T_min_snr       = 3.5;
    cfg.thresholds.T_dup_corr_thresh = 0.8;

    % ---------- run & save ----------------------------------------------
    out = extractor(M, cfg);
    save_extract_outputs_h5(out, saveFile);
    fprintf('Finished %s → %s\n', f.name, saveFile);

    if savePlots
        figure('Visible', 'off');
        plot_output_cellmap(out, 0);
        pngFile = fullfile(saveDir, planeStr + "_masks.png");
        saveas(gcf, pngFile);
        close;
    end
end
end
