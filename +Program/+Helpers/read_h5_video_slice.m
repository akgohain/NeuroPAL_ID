function slice = read_h5_video_slice(info, t, z)
%READ_H5_VIDEO_SLICE Read all channels of one XY plane.
layout = 'data';
if isfield(info,'h5_layout'), layout = char(info.h5_layout); end
if strcmp(layout,'data')
    dims = [info.ny info.nx];
    swapped = isfield(info, 'transpose_xy') && info.transpose_xy;
    if swapped, dims = fliplr(dims); end
    slice = h5read(char(info.file), '/data', [1 1 z 1 t], [dims 1 info.nc 1]);
    slice = reshape(slice, [dims info.nc]);
    if swapped, slice = permute(slice, [2 1 3]); end
else
    first = Program.Helpers.read_h5_video_plane(info,t,z,1);
    slice = zeros(info.ny,info.nx,info.nc,'like',first);
    slice(:,:,1) = first;
    for c = 2:info.nc
        slice(:,:,c) = Program.Helpers.read_h5_video_plane(info,t,z,c);
    end
end
end
