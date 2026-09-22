function test_nwb_singleton_image()
% Check bounded NWB conversion when MATLAB drops trailing singleton axes.
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
shapes = {[7 9 1 1], [7 9 3 1], [7 9 1 4], [1 1 1 1]};
for i = 1:numel(shapes)
    dims = shapes{i};
    source = fullfile(folder, sprintf('source%d.h5', i));
    target = fullfile(folder, sprintf('target%d.mat', i));
    data = reshape(uint16(1:prod(dims)), dims);
    h5create(source, '/data', dims, 'Datatype', 'uint16');
    h5write(source, '/data', data);
    info = struct('dims', dims, 'data_path', '/data', 'axes', 'CZXY');
    report = DataHandling.Helpers.nwb.stream_image_to_mat(source, info, target, struct());
    loaded = load(target, 'data');
    assert(isequal(loaded.data, data));
    assert(isequal(report.output_dims, dims));
end
fprintf('NWB_SINGLETON_IMAGE_CONVERSION=PASS\n');
end
