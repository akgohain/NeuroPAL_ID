function plane = read_h5_video_plane(video_info, t, z, c)
%READ_H5_VIDEO_PLANE Read one XY plane from a supported H5 video layout.

file = char(video_info.file);
layout = 'data';
if isfield(video_info, 'h5_layout') && ~isempty(video_info.h5_layout)
    layout = char(video_info.h5_layout);
end

switch layout
    case 'data'
        plane = squeeze(h5read(file, '/data', ...
            [1 1 z c t], [video_info.ny video_info.nx 1 1 1]));
        plane = reshape(plane, video_info.ny, video_info.nx);
    case 'grouped-tc'
        time_idx = local_index_value(video_info, 'time_indices', t);
        channel_idx = local_index_value(video_info, 'channel_indices', c);
        dataset = sprintf('/t%d/c%d', time_idx, channel_idx);
        % MATLAB sees ASCENT [z y x] datasets as [x y z].
        plane = squeeze(h5read(file, dataset, ...
            [1 1 z], [video_info.ny video_info.nx 1]));
        plane = reshape(plane, video_info.ny, video_info.nx);
    otherwise
        error('Program:Helpers:ReadH5VideoPlane:UnsupportedLayout', ...
            'Unsupported H5 video layout: %s', layout);
end
end

function value = local_index_value(video_info, field_name, one_based_idx)
if isfield(video_info, field_name) && numel(video_info.(field_name)) >= one_based_idx
    value = video_info.(field_name)(one_based_idx);
else
    value = one_based_idx - 1;
end
end
