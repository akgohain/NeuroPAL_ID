function [positions, labels] = readAnnoH5(path)
    if exist(path, 'file') ~= 2
        error('NeuroPAL_ID:MissingAnnotationFile', ...
            'Annotation file does not exist: %s', path);
    end

    [ppath, ~, ~] = fileparts(path);
    wl_path = fullfile(ppath, 'worldlines.h5');
    if exist(wl_path, 'file') ~= 2
        error('NeuroPAL_ID:MissingWorldlines', ...
            ['Unable to import annotations because worldlines.h5 is ' ...
            'missing. It must be in the same folder as the annotations file.']);
    end

    x = h5read(path, '/x');
    y = h5read(path, '/y');
    z = h5read(path, '/z');
    t = h5read(path, '/t_idx');
    worldline_id = h5read(path, '/worldline_id');

    wlid_key = struct();
    wlid_key.idx = h5read(wl_path, '/id');
    wlid_key.name = h5read(wl_path, '/name');

    positions = [x(:), y(:), z(:), double(t(:)) + 1];

    labels = cell(1, numel(worldline_id));
    [~, idx] = ismember(worldline_id(:), wlid_key.idx(:));
    for n = 1:numel(worldline_id)
        if idx(n) > 0
            labels{n} = local_string_value(wlid_key.name, idx(n));
        else
            labels{n} = 'Unknown';
        end
    end
end

function value = local_string_value(values, idx)
    if iscell(values)
        value = char(string(values{idx}));
    elseif isstring(values)
        value = char(values(idx));
    elseif ischar(values)
        value = deblank(values(idx, :));
    else
        value = char(string(values(idx)));
    end
end
