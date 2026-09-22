function test_h5_video_axes()
%TEST_H5_VIDEO_AXES Compare metadata-driven slices with native array coordinates.
old_path = path;
addpath(fullfile(fileparts(mfilename('fullpath')), 'fixtures'));
folder = tempname;
mkdir(folder);
app = VideoViewTestApp();
cleanup = onCleanup(@() finish(app, folder, old_path));
data = reshape(uint16(1:5*7*4*2*3), 5, 7, 4, 2, 3);
metadata = struct('shape_t', 3, 'shape_c', 2, 'shape_z', 4, 'shape_y', 5, 'shape_x', 7);
fid = fopen(fullfile(folder, 'metadata.json'), 'w');
fprintf(fid, '%s', jsonencode(metadata)); fclose(fid);
for swapped = [false true]
    file = fullfile(folder, sprintf('axes%d.h5', swapped));
    raw = data;
    if swapped, raw = permute(raw, [2 1 3 4 5]); end
    h5create(file, '/data', size(raw), 'Datatype', 'uint16');
    h5write(file, '/data', raw);
    info = Program.Helpers.h5_video_info(file);
    assert(info.ny == 5 && info.nx == 7 && info.transpose_xy == swapped);
    app.video_info = info;
    for t = [1 3]
        assert(isequal(Program.Helpers.read_h5_video_frame(info, t), data(:, :, :, :, t)));
        for z = [1 4]
            plane = Program.Helpers.read_h5_video_plane(info, t, z, 2);
            slice = Program.Helpers.read_h5_video_slice(info, t, z);
            assert(isequal(plane, data(:, :, z, 2, t)));
            assert(isequal(slice, reshape(data(:, :, z, :, t), 5, 7, 2)));
            view = Program.Helpers.video_render_views(app, t, z, 2, 6, false);
            assert(isequal(view.xy, slice));
            assert(isequal(view.xz, reshape(data(:, 6, :, :, t), 5, 4, 2)));
            assert(isequal(view.yz, reshape(data(2, :, :, :, t), 7, 4, 2)));
        end
        view = Program.Helpers.video_render_views(app, t, 1, 1, 1, true);
        assert(isequal(view.xy, reshape(max(data(:, :, :, :, t), [], 3), 5, 7, 2)));
    end
end

% A derivative's own axes take precedence over an unchanged sidecar.
file = fullfile(folder, 'derivative.h5');
h5create(file, '/data', [4 3 1 1 1], 'Datatype', 'uint8');
h5writeatt(file, '/data', 'axes', 'TCZXY');
info = Program.Helpers.h5_video_info(file);
assert(info.ny == 4 && info.nx == 3 && info.nt == 1 && info.nz == 1);
assert(isequal(size(Program.Helpers.read_h5_video_slice(info, 1, 1)), [4 3]));
fprintf('H5_VIDEO_AXES_SLICES_PROJECTIONS_SINGLETON=PASS\n');
end

function finish(app, folder, old_path)
delete(app);
rmdir(folder, 's');
path(old_path);
end
