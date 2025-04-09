function save_extract_outputs_h5(outputs, filename)
    if nargin < 2, filename = 'output.h5'; end
    if exist(filename, 'file')
        delete(filename);
    end
    h5create(filename, '/spatial_weights', size(outputs.spatial_weights));
    h5write(filename, '/spatial_weights', outputs.spatial_weights);
    h5create(filename, '/temporal_weights', size(outputs.temporal_weights));
    h5write(filename, '/temporal_weights', outputs.temporal_weights);
    createGroupIfNotExist(filename, '/info');
    saveStructToH5(filename, '/info', outputs.info);
    createGroupIfNotExist(filename, '/config');
    saveStructToH5(filename, '/config', outputs.config);
end

function createGroupIfNotExist(filename, groupPath)
    file_id = H5F.open(filename, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
    try
        gid = H5G.open(file_id, groupPath);
        H5G.close(gid);
    catch
        gid = H5G.create(file_id, groupPath, 'H5P_DEFAULT', 'H5P_DEFAULT', 'H5P_DEFAULT');
        H5G.close(gid);
    end
    H5F.close(file_id);
end

function saveStructToH5(filename, groupPath, s)
    fields = fieldnames(s);
    for i = 1:numel(fields)
        key = fields{i};
        value = s.(key);
        target = sprintf('%s/%s', groupPath, key);
        if isstruct(value)
            createGroupIfNotExist(filename, target);
            saveStructToH5(filename, target, value);
        else
            if isnumeric(value) || islogical(value)
                dims = size(value);
                if any(dims == 0)
                    continue
                end
                % h5create(filename, target, dims, 'Datatype', class(value), 'ChunkSize', ones(1, numel(dims)));
                datatype = class(value);
                if strcmp(datatype, 'logical')
                    datatype = 'uint8';
                    value = uint8(value);
                end
                h5create(filename, target, size(value), 'Datatype', datatype);
                h5write(filename, target, value);

                % h5create(filename, target, dims, 'Datatype', class(value));
                % h5write(filename, target, value);
            elseif ischar(value) || isstring(value)
                v = string(value);
                dims = [1 1];
                h5create(filename, target, dims, 'Datatype', 'string');
                h5write(filename, target, v);
            else
                jsonStr = string(jsonencode(value));
                dims = [1 1];
                h5create(filename, target, dims, 'Datatype', 'string');
                h5write(filename, target, jsonStr);
            end
        end
    end
end
