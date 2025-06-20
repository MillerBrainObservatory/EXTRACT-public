% ========================================================================
%  Main entry
% ========================================================================
function save_extract_outputs_h5(outputs, filename)
if nargin < 2, filename = 'output.h5'; end
filename = char(filename);                      % char-vector for HDF5
if exist(filename,'file'), delete(filename); end

fid = H5F.create(filename,'H5F_ACC_TRUNC','H5P_DEFAULT','H5P_DEFAULT');
H5F.close(fid);

% --- spatial ------------------------------------------------------------
if ~isempty(outputs.spatial_weights)
    h5create(filename,'/spatial_weights', size(outputs.spatial_weights));
    h5write (filename,'/spatial_weights', outputs.spatial_weights);
    h5writeatt(filename,'/','n_cells',size(outputs.spatial_weights,3));
else
    h5writeatt(filename,'/','n_cells',0);
end

% --- temporal -----------------------------------------------------------
if ~isempty(outputs.temporal_weights)
    h5create(filename,'/temporal_weights', size(outputs.temporal_weights));
    h5write (filename,'/temporal_weights', outputs.temporal_weights);
end

% --- nested structs -----------------------------------------------------
createGroupIfNotExist(filename,'/info');
saveStructToH5(filename,'/info',   outputs.info);

createGroupIfNotExist(filename,'/config');
saveStructToH5(filename,'/config', outputs.config);
end

% ========================================================================
%  Helpers (keep below or place in their own files on the MATLAB path)
% ========================================================================
function createGroupIfNotExist(fname, gpath)
fname = char(fname); gpath = char(gpath);
fid   = H5F.open(fname,'H5F_ACC_RDWR','H5P_DEFAULT');
try
    gid = H5G.open(fid, gpath); H5G.close(gid);
catch
    gid = H5G.create(fid, gpath,'H5P_DEFAULT','H5P_DEFAULT','H5P_DEFAULT');
    H5G.close(gid);
end
H5F.close(fid);
end

function saveStructToH5(fname, gpath, S)
fname = char(fname); gpath = char(gpath);
flds  = fieldnames(S);
for k = 1:numel(flds)
    key   = flds{k};
    value = S.(key);
    target = sprintf('%s/%s', gpath, key);

    if isstruct(value)
        createGroupIfNotExist(fname, target);
        saveStructToH5(fname, target, value);
    elseif isnumeric(value) || islogical(value)
        if ~any(size(value)==0)
            if islogical(value), value = uint8(value); end
            h5create(fname, target, size(value), 'Datatype', class(value));
            h5write (fname, target, value);
        end
    else                    % char, string, cellstr, etc. → JSON text
    jsonTxt = char(jsonencode(value));        % convert to char
    h5create(fname, target, [1 1], 'Datatype', 'string');
    h5write (fname, target, {jsonTxt});       % cellstr OK for h5write
end

end
end
