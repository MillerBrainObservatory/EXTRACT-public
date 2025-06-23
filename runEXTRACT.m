function runEXTRACT(rootDir, savePlots, userCfg)
% runEXTRACT  Run EXTRACT on every “planeN.h5” under rootDir.
%
%   runEXTRACT(rootDir)                        – analyse and save H5 outputs only
%   runEXTRACT(rootDir, savePlots)            – also save PNG cell-maps
%   runEXTRACT(rootDir, savePlots, userCfg)   – provide partial cfg override

if nargin < 2, savePlots = true; end
if nargin < 3, userCfg = struct(); end

files = dir(fullfile(rootDir, '**', 'plane*.h5'));
files = files(~contains({files.name}, 'output', 'IgnoreCase', true));
fprintf('Found %d plane files\n', numel(files));

for f = files'
    h5_file  = fullfile(f.folder, f.name);
    planeStr = erase(f.name, '.h5');
    saveDir  = fullfile(f.folder, 'outputs');
    if ~exist(saveDir, 'dir'), mkdir(saveDir); end
    saveFile = fullfile(saveDir, planeStr + "_outputs.h5");

    cfg = get_defaults([]);
    userFields = fieldnames(userCfg);
    for i = 1:numel(userFields)
        field = userFields{i};
        if isfield(cfg, field)
            cfg.(field) = userCfg.(field);
        end
    end

    M = permute(h5read(h5_file, '/mov'), [2 1 3]);   % (X,Y,T)
    out = extractor(M, cfg);
    save_extract_outputs_h5(out, saveFile);
    fprintf('Finished %s → %s\n', f.name, saveFile);

    if savePlots
        fig = figure('Visible','off','Units','pixels','Position',[100 100 1600 1600]);
        plot_output_cellmap(out, 0);
        pngFile = fullfile(saveDir, planeStr + "_masks.png");
        exportgraphics(fig, pngFile, 'Resolution', 600);
        close(fig);
    end
end
end
