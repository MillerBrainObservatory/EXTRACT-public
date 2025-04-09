function outputs = load_extract_outputs_h5(filename)
    outputs = struct();
    outputs.spatial_weights = h5read(filename, '/spatial_weights');
    outputs.temporal_weights = h5read(filename, '/temporal_weights');
    outputs.info = loadStructFromH5(filename, '/info');
    outputs.config = loadStructFromH5(filename, '/config');
end

function s = loadStructFromH5(filename, groupPath)
    info = h5info(filename, groupPath);
    s = struct();

    for i = 1:length(info.Groups)
        subgroupName = info.Groups(i).Name;
        [~, key] = fileparts(subgroupName);
        s.(key) = loadStructFromH5(filename, subgroupName);
    end

    for i = 1:length(info.Datasets)
        dset = info.Datasets(i);
        dname = dset.Name;
        fullPath = [groupPath '/' dname];
        val = h5read(filename, fullPath);

        if iscellstr(val) || isstring(val)
            try
                decoded = jsondecode(val{1});
                s.(dname) = decoded;
            catch
                s.(dname) = val{1};
            end
        elseif ischar(val)
            try
                s.(dname) = jsondecode(val);
            catch
                s.(dname) = val;
            end
        else
            s.(dname) = val;
        end
    end
end
