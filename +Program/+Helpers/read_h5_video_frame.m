function frame = read_h5_video_frame(info, t)
%READ_H5_VIDEO_FRAME Read one complete frame independently of HDF5 chunk size.
validateattributes(t, {'numeric'}, {'scalar', 'integer', 'positive', '<=', info.nt});
plane = Program.Helpers.read_h5_video_plane(info, t, 1, 1);
sample = whos('plane');
bytes = sample.bytes * info.nz * info.nc;
if bytes > DataHandling.Helpers.large_file.memory_budget_bytes()
    error('Program:Video:FrameTooLarge', 'This video frame exceeds the working-memory budget.');
end
frame = zeros(info.ny, info.nx, info.nz, info.nc, 'like', plane);
frame(:, :, 1, 1) = plane;
for channel = 1:info.nc
    for z = 1:info.nz
        if channel == 1 && z == 1, continue; end
        frame(:, :, z, channel) = Program.Helpers.read_h5_video_plane(info, t, z, channel);
    end
end
end
