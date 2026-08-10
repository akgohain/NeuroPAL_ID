function test_tracking_result_adapter()
%TEST_TRACKING_RESULT_ADAPTER Verify canonical/legacy tracking conversion.

video_info = struct('nt', 5, 'nz', 4, 'ny', 10, 'nx', 12);
observations = table( ...
    [7; 7; 11], [0; 0; 7], [1; 4; 4], [2; 3; 1], [4; 5; 6], [7; 8; 9], ...
    [0.91; 0.82; 0.73], ["seed"; "ultrack"; "ultrack"], ...
    'VariableNames', {'track_id', 'parent_id', 't', 'z', 'y', 'x', ...
    'confidence', 'provenance'});

neurons = Tracking.ResultAdapter.toVideoNeurons( ...
    observations, video_info, ["AVA"; "Track 11"]);
assert(numel(neurons) == 2);
assert(strcmp(neurons(1).worldline.name, 'AVA'));
assert(neurons(1).tracking.track_id == 7);
assert(neurons(2).tracking.parent_id == 7);
assert(isempty(neurons(1).rois(2).x_slice));
assert(neurons(1).rois(4).confidence == observations.confidence(2));

roundtrip = Tracking.ResultAdapter.fromVideoNeurons(neurons, video_info);
expected = sortrows(observations, {'track_id', 't'});
assert(isequal(roundtrip.track_id, expected.track_id));
assert(isequal(roundtrip.parent_id, expected.parent_id));
assert(isequal(roundtrip.t, expected.t));
assert(isequal(roundtrip{:, {'z', 'y', 'x'}}, expected{:, {'z', 'y', 'x'}}));
assert(isequal(roundtrip.confidence, expected.confidence));
assert(isequal(roundtrip.provenance, expected.provenance));

legacy = rmfield(neurons, 'tracking');
legacy = rmfield(legacy, 'provenance');
legacy_observations = Tracking.ResultAdapter.fromVideoNeurons(legacy, video_info);
assert(isequal(unique(legacy_observations.track_id), [1; 2]));
assert(all(legacy_observations.parent_id == 0));
assert(isequal(legacy_observations.confidence, expected.confidence));
assert(all(legacy_observations.provenance == "legacy"));

empty_neurons = struct('provenance', {}, 'worldline', {}, 'rois', {});
empty_observations = Tracking.ResultAdapter.fromVideoNeurons(empty_neurons, video_info);
assert(height(empty_observations) == 0);
assert(isequal(empty_observations.Properties.VariableNames, ...
    {'track_id', 'parent_id', 't', 'z', 'y', 'x', 'confidence', 'provenance'}));

local_assert_error(@() Tracking.ResultAdapter.toVideoNeurons( ...
    observations, video_info, "only one"), 'Tracking:ResultAdapter:NameCount');
fprintf('TRACKING_RESULT_ADAPTER=PASS\n');
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
