function metadata = read_h5_metadata(h5_fullfile, loc)
% Reads metadata from an HDF5 file.
%
% Reads the metadata attributes from a specified location within an HDF5 file
% and returns them as a structured array. In particular, if the "image" attribute
% is present, its fields are merged into the output structure without overwriting
% any existing fields.
%
% Parameters
% ----------
% h5_fullfile : char
%     Full path to the HDF5 file from which to read metadata.
% loc : char, optional
%     Location within the HDF5 file from which to read attributes. Defaults to '/'.
%
% Returns
% -------
% metadata : struct
%     A structured array containing the metadata attributes and their values
%     read from the HDF5 file.
%
% Examples
% --------
% Read metadata from the root location of an HDF5 file:
%     metadata = read_h5_metadata('example.h5');
%
% Read metadata from a specific group within an HDF5 file:
%     metadata = read_h5_metadata('example.h5', '/group1');
%
% Notes
% -----
% The function uses `h5info` to retrieve information about the specified location
% within the HDF5 file and `h5readatt` to read attribute values. The attribute names
% are converted to valid MATLAB field names using `matlab.lang.makeValidName`.
% If the "image" attribute is present, its fields are merged into the metadata output
% without overwriting existing fields.

if ~exist('h5_fullfile', 'var'); h5_fullfile = uigetfile('Select a processed h5 dataset:'); end
if ~exist('loc', 'var'); loc = '/'; end

try
    h5_data = h5info(h5_fullfile, loc);
catch
    error("File %s does not exist with group %s.", h5_fullfile, loc);
end

metadata = struct();

% If no attributes are present at the specified location, warn the user.
if isempty(h5_data.Attributes)
    if ~strcmp(loc, "/")
        fprintf("WARNING: Attempted to read group '%s' but found no attributes.\n", loc);
        fprintf("Attempting to read from the root group '/'.\n");
        h5_data = h5info(h5_fullfile, "/");
        if isempty(h5_data.Attributes)
            error("No valid metadata found in the file: %s.", h5_fullfile);
        else
            fprintf("Metadata found in the root '/' group.\n");
        end
    else
        fprintf("No valid metadata in group '%s' for file:\n  %s\n", loc, h5_fullfile);
        return
    end
end

% Process and store all attributes found in the group.
for k = 1:numel(h5_data.Attributes)
    attr_name = h5_data.Attributes(k).Name;
    attr_value = h5readatt(h5_fullfile, h5_data.Name, attr_name);
    metadata.(matlab.lang.makeValidName(attr_name)) = attr_value;
end

% If the "image" attribute is present, merge its fields into metadata.
if isfield(metadata, 'image')
    attval = metadata.image;
    % Check if the "image" attribute is nonempty.
    if isempty(attval)
        warning('Attribute "image" exists but is empty in file: %s. Skipping merge.', h5_fullfile);
    else
        % Convert Python-style single quotes to valid JSON by replacing with double quotes,
        % converting tuple notation to array notation, and converting Python None to null.
        json_str = regexprep(attval, '''', '"');
        json_str = regexprep(json_str, '\((\s*\d+),\s*(\d+)\)', '[$1, $2]');
        json_str = regexprep(json_str, ':\s*None(?=,|})', ': null');
        
        try
            image_metadata = jsondecode(json_str);
        catch ME
            warning(ME.identifier, 'Failed to decode "image" metadata JSON: %s', ME.message);
            image_metadata = [];
        end
        
        % If valid JSON was decoded, merge fields (without overwriting existing ones)
        if ~isempty(image_metadata) && isstruct(image_metadata)
            image_fields = fieldnames(image_metadata);
            for i = 1:length(image_fields)
                fld = image_fields{i};
                if ~isfield(metadata, fld)
                    metadata.(fld) = image_metadata.(fld);
                end
            end
        end
    end
end

if isempty(fieldnames(metadata))
    error("No valid metadata found in file: %s (group: %s)", h5_fullfile, loc);
end
