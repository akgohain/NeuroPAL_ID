function test_neuropal_image_loader()
%TEST_NEUROPAL_IMAGE_LOADER Exercise path and metadata sanitization behavior.

root = fullfile(tempname, 'folder.with.mat.and.nwb.tokens');
mkdir(root);
cleanup = onCleanup(@() local_cleanup(fileparts(root)));
image_file = fullfile(root, 'animal.sample.mat');
id_file = fullfile(root, 'animal.sample_ID.mat');

version = Program.ProgramInfo.version;
data = zeros(5, 7, 3, 3, 'uint16');
info = struct('scale', [0.4, 0.4, 1.5], 'gamma', 0.8);
prefs = struct( ...
    'RGBW', [99, -1], ...
    'DIC', [20, 2], ...
    'GFP', 42, ...
    'gamma', 0.8, ...
    'rotate', struct('horizontal', false, 'vertical', false));
worm = struct('body', 'Head', 'age', 'Adult', 'sex', 'XX', ...
    'strain', '', 'notes', '');
save(image_file, 'version', 'data', 'info', 'prefs', 'worm', '-v7.3');

[loaded, ~, sanitized, ~, mp, neurons, np_file, resolved_id] = ...
    DataHandling.NeuroPALImage.open(image_file);
assert(isequal(loaded, data));
assert(strcmp(np_file, image_file));
assert(strcmp(resolved_id, id_file));
assert(all(sanitized.RGBW >= 1 & sanitized.RGBW <= size(data, 4)));
assert(numel(sanitized.RGBW) == 4);
assert(isscalar(sanitized.DIC) && sanitized.DIC == 2);
assert(isnan(sanitized.GFP));
assert(isstruct(mp) && isfield(mp, 'hnsz'));
assert(isempty(neurons));

[~, ~, ~, ~, ~, ~, np_from_id, resolved_from_id] = ...
    DataHandling.NeuroPALImage.open(id_file);
assert(strcmp(np_from_id, image_file));
assert(strcmp(resolved_from_id, id_file));

missing = fullfile(root, 'missing.mat');
local_assert_error(@() DataHandling.NeuroPALImage.open(missing), ...
    'DataHandling:NeuroPALImage:MissingFile');

clear cleanup
local_cleanup(fileparts(root));
fprintf('NEUROPAL_IMAGE_LOADER=PASS\n');
end

function local_assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), ...
        'Expected %s, received %s.', identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', 'Expected %s.', identifier);
end

function local_cleanup(root)
if exist(root, 'dir') == 7
    rmdir(root, 's');
end
end
