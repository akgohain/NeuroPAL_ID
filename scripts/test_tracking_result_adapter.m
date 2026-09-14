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
assert(isa(empty_observations{:, 1:7}, 'double'));
assert(isstring(empty_observations.provenance));
assert(isequal(size(empty_observations.provenance), [0, 1]));
assert(isequal(Tracking.ResultAdapter.fromVideoNeurons(struct(), video_info), ...
    empty_observations));

% Missing or nonfinite confidence retains the legacy default.
without_confidence = legacy;
for i = 1:numel(without_confidence)
    without_confidence(i).rois = rmfield(without_confidence(i).rois, 'confidence');
end
defaults = Tracking.ResultAdapter.fromVideoNeurons(without_confidence, video_info);
assert(all(defaults.confidence == 1));
assert(isequal(defaults{:, 1:6}, legacy_observations{:, 1:6}));
assert(isequal(defaults.provenance, legacy_observations.provenance));

mixed = legacy;
mixed(1).provenance = 'manual';
mixed(2).provenance = 'manual';
mixed(1).rois(1).confidence = NaN;
mixed(1).rois(4).confidence = [];
mixed(2).rois(4).confidence = single(0.5);
mixed(1).rois(1).x_slice = uint16(mixed(1).rois(1).x_slice);
mixed(1).rois(1).y_slice = single(mixed(1).rois(1).y_slice);
mixed(1).rois(2).x_slice = NaN;
mixed(1).rois(2).y_slice = 1;
mixed(1).rois(2).z_slice = 1;
mixed(1).rois(6) = mixed(1).rois(1);
converted = Tracking.ResultAdapter.fromVideoNeurons(mixed, video_info);
assert(isequal(converted{:, 1:6}, legacy_observations{:, 1:6}));
assert(isequal(converted.confidence, [1; 1; 0.5]));
assert(all(converted.provenance == "manual"));
assert(isa(converted{:, 1:7}, 'double'));

invalid = legacy;
invalid(1).rois(1).confidence = 2;
local_assert_error(@() Tracking.ResultAdapter.fromVideoNeurons(invalid, video_info), ...
    'Tracking:JobContract:InvalidConfidence');

% A complete movie retains coordinates, ordering, lineage, and provenance.
movie_info = struct('nt', 200, 'nz', 4, 'ny', 10, 'nx', 60);
track_ids = repelem((1:50)', movie_info.nt);
frames = repmat((1:movie_info.nt)', 50, 1);
parent_ids = zeros(size(track_ids));
parent_ids(track_ids > 1) = 1;
movie_observations = table(track_ids, parent_ids, frames, ...
    1 + mod(frames, movie_info.nz), 1 + mod(frames, movie_info.ny), ...
    track_ids, mod(frames, 11) / 10, repmat("tracked", numel(frames), 1), ...
    'VariableNames', observations.Properties.VariableNames);
movie_neurons = Tracking.ResultAdapter.toVideoNeurons(movie_observations, movie_info);
assert(numel(movie_neurons) == 50);
movie_roundtrip = Tracking.ResultAdapter.fromVideoNeurons(movie_neurons(end:-1:1), movie_info);
assert(isequal(movie_roundtrip, movie_observations));

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
