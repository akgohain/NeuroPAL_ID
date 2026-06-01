function info = h5_video_info(path)
%H5_VIDEO_INFO Inspect supported video H5 layouts without loading the movie.

root = h5info(path);
if isempty(root.Datasets)
    dataset_names = strings(1, 0);
else
    dataset_names = string({root.Datasets.Name});
end

if any(dataset_names == "data")
    data_info = h5info(path, '/data');
    dims = data_info.Dataspace.Size;
    if numel(dims) < 5
        dims(5) = 1;
    end

    info = struct();
    info.file = data_info.Filename;
    info.h5_layout = 'data';
    info.ny = dims(1);
    info.nx = dims(2);
    info.nz = dims(3);
    info.nc = dims(4);
    info.nt = dims(5);
    info.aspect_ratio = info.ny / info.nx;
    info.ChunkSize = data_info.ChunkSize;
    info.cached = 1;
    info.bitDepth = Program.Helpers.h5_video_bit_depth(path, '/data', [1 1 1 1 1], [1 1 1 1 1]);
    return
end

if isempty(root.Groups)
    group_names = strings(1, 0);
else
    group_names = string({root.Groups.Name});
end
time_group_names = group_names(~cellfun(@isempty, regexp(cellstr(group_names), '/t\d+$', 'once')));
if ~isempty(time_group_names)
    time_indices = arrayfun(@(name) local_numeric_suffix(name, '/t'), time_group_names);
    time_indices = sort(time_indices);
    first_group = sprintf('/t%d', time_indices(1));
    first_info = h5info(path, first_group);
    channel_names = string({first_info.Datasets.Name});
    channel_names = channel_names(~cellfun(@isempty, regexp(cellstr(channel_names), '^c\d+$', 'once')));
    if isempty(channel_names)
        error('Program:Helpers:H5VideoInfo:InvalidGroupedH5', ...
            'Grouped H5 layout has time groups but no c* channel datasets.');
    end
    channel_indices = sort(arrayfun(@(name) local_numeric_suffix(name, 'c'), channel_names));
    sample_dataset = sprintf('%s/c%d', first_group, channel_indices(1));
    sample_info = h5info(path, sample_dataset);
    dims = sample_info.Dataspace.Size;
    if numel(dims) ~= 3
        error('Program:Helpers:H5VideoInfo:InvalidGroupedH5', ...
            'Expected grouped H5 channel volumes to be 3-D [z y x], got %s.', mat2str(dims));
    end

    info = struct();
    info.file = path;
    info.h5_layout = 'grouped-tc';
    % MATLAB reports the ASCENT [z y x] HDF5 dataset as [x y z].
    % h5read with [1 1 z] / [nx ny 1] returns the visible XY plane.
    info.ny = dims(1);
    info.nx = dims(2);
    info.nz = dims(3);
    info.nc = numel(channel_indices);
    info.nt = numel(time_indices);
    info.aspect_ratio = info.ny / info.nx;
    info.ChunkSize = sample_info.ChunkSize;
    info.cached = 1;
    info.time_indices = time_indices;
    info.channel_indices = channel_indices;
    info.bitDepth = Program.Helpers.h5_video_bit_depth(path, sample_dataset, [1 1 1], [1 1 1]);
    return
end

error('Program:Helpers:H5VideoInfo:UnsupportedH5', ...
    '.h5 file structure is invalid: expected /data or grouped /t*/c* datasets.');
end

function idx = local_numeric_suffix(value, prefix)
text = char(value);
token = regexp(text, [regexptranslate('escape', prefix) '(\d+)$'], 'tokens', 'once');
if isempty(token)
    idx = NaN;
else
    idx = str2double(token{1});
end
end
