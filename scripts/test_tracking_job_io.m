function test_tracking_job_io()
%TEST_TRACKING_JOB_IO Exercise transactional worker interchange.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() local_cleanup(root));
source = fullfile(root, 'video.h5');
fid = fopen(source, 'w');
assert(fid >= 0);
fwrite(fid, uint8(1:8), 'uint8');
fclose(fid);

workspace = fullfile(root, 'job-001');
request = struct( ...
    'schema_version', 1, ...
    'backend', 'ultrack', ...
    'source', source, ...
    'output_dir', workspace, ...
    'scale_zyx', [1.5, 0.4, 0.4], ...
    'time_step', 0.5, ...
    'segmentation', struct('kind', 'labels', 'path', 'labels.zarr'));
assert(strcmp(Tracking.JobIO.stage(request), workspace));
assert(exist(fullfile(workspace, 'request.json'), 'file') == 2);
assert(exist(fullfile(workspace, 'state.json'), 'file') == 2);
staged_request = jsondecode(fileread(fullfile(workspace, 'request.json')));
assert(isfield(staged_request, 'source_signature'));
state = Tracking.JobIO.readState(workspace);
assert(strcmp(state.status, 'staged') && state.progress == 0);
state = Tracking.JobIO.updateState(workspace, 'running', 0.25, 'Segmenting.');
assert(strcmp(state.status, 'running') && state.progress == 0.25);
Tracking.JobIO.appendLog(workspace, 'info', 'segmentation', 'Frame batch ready.', ...
    struct('frames', [1, 2]));
assert(exist(fullfile(workspace, 'events.jsonl'), 'file') == 2);
local_assert_error(@() Tracking.JobIO.updateState( ...
    workspace, 'running', 0.2), 'Tracking:JobIO:ProgressRegression');
local_assert_error(@() Tracking.JobIO.stage(request), 'Tracking:JobIO:WorkspaceExists');

video_info = struct('nt', 5, 'nz', 4, 'ny', 10, 'nx', 12);
observations = table( ...
    [1; 1; 2], [0; 0; 1], [1; 2; 2], [2; 2; 3], [4; 5; 6], [7; 8; 9], ...
    [0.9; 0.8; 0.7], ["ultrack"; "ultrack"; "ultrack"], ...
    'VariableNames', {'track_id', 'parent_id', 't', 'z', 'y', 'x', ...
    'confidence', 'provenance'});
native_dir = fullfile(workspace, 'native');
mkdir(native_dir);
fid = fopen(fullfile(native_dir, 'tracks.sqlite'), 'w');
assert(fid >= 0);
fclose(fid);
mkdir(fullfile(native_dir, 'labels.zarr'));
manifest = Tracking.JobIO.writeResult(workspace, observations, video_info, ...
    ["native/tracks.sqlite"; "native/labels.zarr"]);
assert(strcmp(manifest.status, 'complete'));
assert(exist(fullfile(workspace, 'result.json'), 'file') == 2);
[loaded, loaded_manifest, loaded_request] = Tracking.JobIO.readResult(workspace, video_info);
assert(isequal(loaded.track_id, observations.track_id));
assert(double(loaded_manifest.observation_count) == height(observations));
assert(strcmp(loaded_request.backend, 'ultrack'));
state = Tracking.JobIO.readState(workspace);
assert(strcmp(state.status, 'complete') && state.progress == 1);
local_assert_error(@() Tracking.JobIO.updateState( ...
    workspace, 'running', 1), 'Tracking:JobIO:InvalidStateTransition');
local_assert_error(@() Tracking.JobIO.writeResult( ...
    workspace, observations, video_info), 'Tracking:JobIO:ResultExists');

invalid_workspace = fullfile(root, 'job-invalid');
invalid_request = request;
invalid_request.output_dir = invalid_workspace;
Tracking.JobIO.stage(invalid_request);
invalid = observations;
invalid.x(1) = video_info.nx + 1;
local_assert_error(@() Tracking.JobIO.writeResult( ...
    invalid_workspace, invalid, video_info), 'Tracking:JobContract:OutOfBounds');
assert(exist(fullfile(invalid_workspace, 'result.json'), 'file') ~= 2);
assert(exist(fullfile(invalid_workspace, 'observations.csv'), 'file') ~= 2);

cancel_workspace = fullfile(root, 'job-cancel');
cancel_request = request;
cancel_request.output_dir = cancel_workspace;
Tracking.JobIO.stage(cancel_request);
cancelled = Tracking.JobIO.requestCancellation(cancel_workspace);
assert(strcmp(cancelled.status, 'cancelled'));
assert(Tracking.JobIO.cancellationRequested(cancel_workspace));

running_cancel_workspace = fullfile(root, 'job-running-cancel');
running_cancel_request = request;
running_cancel_request.output_dir = running_cancel_workspace;
Tracking.JobIO.stage(running_cancel_request);
Tracking.JobIO.updateState(running_cancel_workspace, 'running', 0.4, 'Tracking.');
cancelling = Tracking.JobIO.requestCancellation(running_cancel_workspace);
assert(strcmp(cancelling.status, 'cancelling'));
Tracking.JobIO.updateState(running_cancel_workspace, 'cancelled', 0.4, 'Stopped.');
assert(Tracking.JobIO.cancellationRequested(running_cancel_workspace));

manifest_path = fullfile(workspace, 'result.json');
manifest_data = jsondecode(fileread(manifest_path));
manifest_data.observations_csv = '../outside.csv';
fid = fopen(manifest_path, 'w');
assert(fid >= 0);
file_cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(manifest_data), 'char');
clear file_cleanup
local_assert_error(@() Tracking.JobIO.readResult(workspace, video_info), ...
    'Tracking:JobIO:UnsafeArtifactPath');

changed_workspace = fullfile(root, 'job-source-changed');
changed_request = request;
changed_request.output_dir = changed_workspace;
Tracking.JobIO.stage(changed_request);
fid = fopen(source, 'a');
assert(fid >= 0);
fwrite(fid, uint8(9), 'uint8');
fclose(fid);
local_assert_error(@() Tracking.JobIO.writeResult( ...
    changed_workspace, observations, video_info), 'Tracking:JobIO:SourceChanged');

clear cleanup
local_cleanup(root);
fprintf('TRACKING_JOB_IO=PASS\n');
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
