function test_npal_mat_source()
%TEST_NPAL_MAT_SOURCE Verify metadata-only access and bounded materialization.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
previous_limit = getenv('NEUROPAL_IMAGE_MAX_MIB');
environment_cleanup = onCleanup(@() setenv('NEUROPAL_IMAGE_MAX_MIB', previous_limit));
setenv('NEUROPAL_IMAGE_MAX_MIB', '');
assert(DataHandling.Helpers.npal_mat.materialization_limit_bytes() == 512 * 1024^2);

path = fullfile(root, 'fixture.mat');
version = Program.ProgramInfo.version;
data = reshape(uint16(1:420), [5 7 3 4]);
info = struct('scale', [0.4 0.4 1.5], 'gamma', 0.8);
prefs = struct('RGBW', [1 2 3 4], 'DIC', NaN, 'GFP', NaN, ...
    'gamma', 0.8, 'rotate', struct('horizontal', false, 'vertical', false));
worm = struct('body', 'Head', 'age', 'Adult', 'sex', 'XX', 'strain', '', 'notes', '');
unrelated = zeros(1024, 1024, 8, 'uint8');
save(path, 'version', 'data', 'info', 'prefs', 'worm', 'unrelated', '-v7.3');
clear unrelated

source = DataHandling.Helpers.npal_mat.open_source(path);
assert(isa(source.reader, 'matlab.io.MatFile'));
assert(source.supports_partial);
assert(isequal(source.dims, size(data)));
assert(strcmp(source.source_class, 'uint16'));
assert(source.bytes == numel(data) * 2);
assert(~isfield(source.metadata, 'data') && ~isfield(source.metadata, 'unrelated'));
assert(isequal(source.metadata.info, info));
assert(isequal(source.read_plane(2, 3), data(:, :, 2, 3)));
fields = DataHandling.Helpers.npal_mat.load_fields(path, true);
assert(isequal(sort(fieldnames(fields)), sort({'data'; 'version'; 'info'; 'prefs'; 'worm'})));
assert(isequal(fields.data, data));
assert(strcmp(DataHandling.NeuroPALImage.prepare(path), path));
[loaded, loaded_info] = DataHandling.NeuroPALImage.open(path);
assert(isequal(loaded, data) && isequal(loaded_info, info));

% Metadata and slice access remain available when whole-image loading is denied.
setenv('NEUROPAL_IMAGE_MAX_MIB', '0.0001');
assert_error(@() DataHandling.NeuroPALImage.open(path), ...
    'DataHandling:NeuroPALImage:MaterializationLimit');
source = DataHandling.Helpers.npal_mat.open_source(path);
assert(isequal(source.read_plane(1, 4), data(:, :, 1, 4)));
assert(strcmp(DataHandling.NeuroPALImage.prepare(path), path));
setenv('NEUROPAL_IMAGE_MAX_MIB', 'not-a-number');
assert(DataHandling.Helpers.npal_mat.materialization_limit_bytes() == 512 * 1024^2);

% Optional legacy fields remain optional, and migration still runs on full open.
legacy_path = fullfile(root, 'legacy.mat');
prefs.body_part = 'Head';
save(legacy_path, 'data', 'info', 'prefs', '-v7.3');
legacy_source = DataHandling.Helpers.npal_mat.open_source(legacy_path);
assert(~isfield(legacy_source.metadata, 'version'));
[legacy_data, ~, legacy_prefs, legacy_worm] = DataHandling.NeuroPALImage.open(legacy_path);
assert(isequal(legacy_data, data));
assert(~isfield(legacy_prefs, 'body_part'));
assert(strcmp(legacy_worm.body, 'Head'));
updated = DataHandling.Helpers.npal_mat.load_fields(legacy_path, false);
assert(updated.version == Program.ProgramInfo.version);
assert(~isfield(updated, 'data'));
fprintf('NPAL_MAT_SOURCE=PASS\n');
end

function assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), 'Expected %s; received %s.', identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', 'Expected %s.', identifier);
end
