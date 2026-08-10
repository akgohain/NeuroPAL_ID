function test_tracking_contracts()
%TEST_TRACKING_CONTRACTS Exercise backend-neutral job/result validation.

[names, ids] = Tracking.BackendRegistry.uiChoices();
assert(isequal(size(names), size(ids)));
assert(all(ismember({'zephir', 'ultrack', 'hoct'}, ids)));
assert(Tracking.BackendRegistry.find('zephir').runnable);
assert(~Tracking.BackendRegistry.find('ultrack').runnable);

request = struct( ...
    'schema_version', 1, ...
    'backend', 'zephir', ...
    'source', '/fixture/video.h5', ...
    'output_dir', '/fixture/output', ...
    'scale_zyx', [1.5, 0.4, 0.4], ...
    'time_step', 0.5, ...
    'segmentation', struct('kind', 'none', 'path', ''));
request = Tracking.JobContract.request(request);
assert(strcmp(request.backend, 'zephir'));

ultrack_request = request;
ultrack_request.backend = 'ultrack';
local_assert_error(@() Tracking.JobContract.request(ultrack_request), ...
    'Tracking:JobContract:SegmentationRequired');
ultrack_request.segmentation = struct('kind', 'labels', 'path', '/fixture/labels.zarr');
Tracking.JobContract.request(ultrack_request);

observations = table( ...
    [1; 1; 2], [0; 0; 1], [1; 2; 2], [2; 2; 3], [4; 5; 6], [7; 8; 9], ...
    [0.9; 0.8; 0.7], ["zephir"; "zephir"; "zephir"], ...
    'VariableNames', {'track_id', 'parent_id', 't', 'z', 'y', 'x', ...
    'confidence', 'provenance'});
video_info = struct('nt', 5, 'nz', 4, 'ny', 10, 'nx', 12);
Tracking.JobContract.observations(observations, video_info);

duplicate = [observations; observations(1, :)];
local_assert_error(@() Tracking.JobContract.observations(duplicate, video_info), ...
    'Tracking:JobContract:DuplicateObservation');
cyclic = observations;
cyclic.parent_id = [2; 2; 1];
local_assert_error(@() Tracking.JobContract.observations(cyclic, video_info), ...
    'Tracking:JobContract:LineageCycle');
outside = observations;
outside.x(1) = 13;
local_assert_error(@() Tracking.JobContract.observations(outside, video_info), ...
    'Tracking:JobContract:OutOfBounds');

fprintf('TRACKING_CONTRACTS=PASS\n');
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
