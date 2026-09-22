function test_legacy_detection_input()
%TEST_LEGACY_DETECTION_INPUT Use native pixels without a persistent z-score cache.
rng(17);
app = struct('image_data', uint16(randi(1000, 25, 35, 15, 4)), ...
    'image_prefs', struct('RGBW', [4 2 1 3]));
selected = app.image_data(:, :, :, [4 2 1 3]);
assert(isequal(Program.Helpers.legacy_detection_volume(app, true), selected));
normalized = Program.Helpers.legacy_detection_volume(app, false);
assert(isequaln(normalized, Methods.Preprocess.zscore_frame(selected)));
blank = app; blank.image_data(:) = 0;
expect(@() Program.Helpers.legacy_detection_volume(blank, true), 'Program:Detection:NoSignal');
bad = app; bad.image_prefs.RGBW = [1 2 3 5];
expect(@() Program.Helpers.legacy_detection_volume(bad, true), 'Program:Detection:Channels');
previous = getenv('NEUROPAL_IO_CHUNK_MIB');
cleanup = onCleanup(@() setenv('NEUROPAL_IO_CHUNK_MIB', previous));
setenv('NEUROPAL_IO_CHUNK_MIB', '8');
large = app; large.image_data = zeros(200, 200, 20, 4, 'uint8');
expect(@() Program.Helpers.legacy_detection_volume(large, true), 'Program:Detection:LegacyVolumeBudget');
fprintf('LEGACY_DETECTION_INPUT_AND_BUDGET=PASS\n');
end

function expect(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), ME.message);
    return
end
error('test:MissingError', 'Expected %s.', identifier);
end
