function response = runMoECentroids(volume, scale_um_xyz, options)
%RUNMOECENTROIDS Run frozen nonlinear MoE on native YXZ RGBW image data.
arguments
    volume
    scale_um_xyz double
    options.Backend (1,1) string = "moe"
    options.InputMode (1,1) string = "rgbw"
    options.ScoreThreshold (1,1) double = NaN
    options.SourceMetadata (1,1) struct = struct()
    options.BundlePath (1,1) string = ""
    options.PythonExecutable (1,1) string = ""
    options.DatasetID (1,1) string = "unknown"
    options.Device (1,1) string = "cpu"
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = true
    options.ProgressFcn = []
    options.CancelFcn = []
    options.TimeoutSeconds (1,1) double = 10800
    options.JobToken (1,1) string = ""
end
job = Program.HeavyJob.acquire('MoE inference', options.JobToken);
job_cleanup = onCleanup(@() delete(job));
if ~isfinite(options.TimeoutSeconds) || options.TimeoutSeconds <= 0
    error('Wrapper:MoEInvalidTimeout', 'TimeoutSeconds must be finite and positive.');
end
if ~isnan(options.ScoreThreshold) && (~isfinite(options.ScoreThreshold) || options.ScoreThreshold<0 || options.ScoreThreshold>1)
    error('Wrapper:MoEInvalidThreshold', 'Use the model threshold or supply a finite score threshold from 0 to 1.');
end
if ~isnan(options.ScoreThreshold) && options.Backend~="moe"
    error('Wrapper:MoEInvalidThreshold', 'A router score threshold applies only to the MoE backend.');
end
readiness = Methods.ModelSetup.bundle('detection_moe', options.BundlePath);
if ~any(options.InputMode == ["rgbw", "single_channel"])
    error('Wrapper:MoEInvalidMode', 'Choose rgbw or single_channel.');
end
if options.InputMode=="single_channel" && options.DatasetID~="unknown"
    error('Wrapper:MoEDatasetMismatch', ...
        'Single-channel detection requires dataset_id "unknown". Set the dataset to unknown in MoE settings before running this adapted input.');
end
expected_channels = 4;
if options.InputMode == "single_channel", expected_channels = 1; end
if isempty(volume) || size(volume, 4) ~= expected_channels || ndims(volume) > 4 || any(~isfinite(volume), 'all')
    error('Wrapper:MoEInvalidVolume', 'MoE requires finite, native-intensity YXZ RGBW image data.');
end
scale = double(scale_um_xyz(:)');
if numel(scale) ~= 3 || any(~isfinite(scale)) || any(scale <= 0)
    error('Wrapper:MoEInvalidSpacing', 'Supply three positive voxel spacings in XYZ micrometers.');
end
context=Runtime.Resolver.require('detection_moe',struct('python',char(options.PythonExecutable),'bundle',readiness.bundle_path),options.CancelFcn);
python=context.python;
output = char(options.OutputDir);
if isempty(output), output = tempname; end
% Each request owns its directory; never delete a caller-owned directory.
if exist(output, 'dir') ~= 7, mkdir(output); end
output = tempname(output);
mkdir(output);
cleanup = onCleanup(@() local_cleanup(output, options.KeepArtifacts));
raw_path = fullfile(output, 'volume.bin');
fid = fopen(raw_path, 'w');
if fid < 0, error('Wrapper:MoEWriteFailed', 'Cannot write %s.', raw_path); end
file_cleanup = onCleanup(@() fclose(fid));
count = fwrite(fid, volume, 'single');
if count ~= numel(volume), error('Wrapper:MoEWriteFailed', 'Incomplete image export.'); end
clear file_cleanup
request = struct('bundle', readiness.bundle_path, 'output_dir', output, ...
    'backend', char(options.Backend), 'input_mode', char(options.InputMode), 'source_metadata', options.SourceMetadata, ...
    'volume_raw', raw_path, 'volume_shape_yxzc', [size(volume,1), size(volume,2), size(volume,3), expected_channels], ...
    'volume_dtype', 'float32', 'scale_um_xyz', scale, ...
    'dataset_id', char(options.DatasetID), 'device', char(options.Device));
if ~isnan(options.ScoreThreshold), request.score_threshold=options.ScoreThreshold; end
request_path = fullfile(output, 'request.json');
response_path = fullfile(output, 'response.json');
fid = fopen(request_path, 'w');
if fid < 0, error('Wrapper:MoEWriteFailed', 'Cannot write request.'); end
file_cleanup = onCleanup(@() fclose(fid));
fwrite(fid,unicode2native(jsonencode(request),'UTF-8'),'uint8');
clear file_cleanup
bridge = fullfile(fileparts(mfilename('fullpath')), 'moe_inference.py');
log_path = fullfile(output, 'inference.log');
try
    [status, detail] = Wrapper.runPythonProcess( ...
        {python, '-u', bridge, 'run', '--request', request_path, '--response', response_path}, ...
        'JobToken', job.Token, 'LogPath', log_path, ...
        'ProgressFcn', options.ProgressFcn, 'CancelFcn', options.CancelFcn, ...
        'TimeoutSeconds', options.TimeoutSeconds);
catch ME
    if strcmp(ME.identifier, 'Wrapper:ProcessCancelled')
        error('Wrapper:MoECancelled', 'Detection canceled; existing annotations were preserved.');
    elseif strcmp(ME.identifier, 'Wrapper:ProcessTimeout')
        error('Wrapper:MoETimeout', 'Detection timed out. See %s.', log_path);
    end
    rethrow(ME);
end
if status ~= 0
    error('Wrapper:MoEInferenceFailed', 'MoE inference failed. Log: %s\n%s', log_path, detail);
end
response = jsondecode(fileread(response_path));
centers = double(response.centroids_yxz);
scores = double(response.scores(:));
if isempty(centers), centers = zeros(0,3); end
bounds = [size(volume,1),size(volume,2),size(volume,3)];
if size(centers,2) ~= 3 || size(centers,1) ~= numel(scores) || ...
        size(centers,1) ~= response.num_centroids || ...
        any(~isfinite(centers),'all') || any(centers < 1,'all') || ...
        any(centers > bounds,'all') || any(~isfinite(scores) | scores < 0 | scores > 1)
    error('Wrapper:MoEInvalidResponse', 'Detector returned invalid centers or scores.');
end
response.centroids_yxz = centers;
response.output_dir = output;
end

function local_cleanup(path, keep)
if ~keep && exist(path, 'dir') == 7, rmdir(path, 's'); end
end
