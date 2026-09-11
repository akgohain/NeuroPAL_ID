function response = runMoECentroids(volume, scale_um_xyz, options)
%RUNMOECENTROIDS Run frozen nonlinear MoE on native YXZ RGBW image data.
arguments
    volume
    scale_um_xyz double
    options.BundlePath (1,1) string = ""
    options.PythonExecutable (1,1) string = ""
    options.DatasetID (1,1) string = "unknown"
    options.Device (1,1) string = "cpu"
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = true
    options.ProgressFcn = []
    options.CancelFcn = []
    options.TimeoutSeconds (1,1) double = 10800
end
if ~isfinite(options.TimeoutSeconds) || options.TimeoutSeconds <= 0
    error('Wrapper:MoEInvalidTimeout', 'TimeoutSeconds must be finite and positive.');
end
readiness = Methods.MethodBundle.inspect('detection_moe', options.BundlePath);
if ~readiness.ready
    error('Wrapper:MoEBundleUnavailable', '%s', readiness.summary);
end
if isempty(volume) || size(volume, 4) ~= 4 || ndims(volume) > 4 || any(~isfinite(volume), 'all')
    error('Wrapper:MoEInvalidVolume', 'MoE requires finite, native-intensity YXZ RGBW image data.');
end
scale = double(scale_um_xyz(:)');
if numel(scale) ~= 3 || any(~isfinite(scale)) || any(scale <= 0)
    error('Wrapper:MoEInvalidSpacing', 'Supply three positive voxel spacings in XYZ micrometers.');
end
python = char(options.PythonExecutable);
if isempty(python), python = getenv('NEUROPAL_MOE_PYTHON'); end
if isempty(python) && isfield(readiness.manifest.configuration, 'python_executable')
    python = char(readiness.manifest.configuration.python_executable);
end
if isempty(python) || exist(python, 'file') ~= 2
    error('Wrapper:MoEPythonUnavailable', 'Set the MoE Python interpreter in Settings or NEUROPAL_MOE_PYTHON.');
end
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
    'volume_raw', raw_path, 'volume_shape_yxzc', [size(volume,1), size(volume,2), size(volume,3), 4], ...
    'volume_dtype', 'float32', 'scale_um_xyz', scale, ...
    'dataset_id', char(options.DatasetID), 'device', char(options.Device));
request_path = fullfile(output, 'request.json');
response_path = fullfile(output, 'response.json');
fid = fopen(request_path, 'w');
if fid < 0, error('Wrapper:MoEWriteFailed', 'Cannot write request.'); end
file_cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(request), 'char');
clear file_cleanup
bridge = fullfile(fileparts(mfilename('fullpath')), 'moe_inference.py');
command = java.util.ArrayList;
parts = {python, '-u', bridge, 'run', '--request', request_path, '--response', response_path};
for i = 1:numel(parts), command.add(java.lang.String(parts{i})); end
builder = java.lang.ProcessBuilder(command);
builder.redirectErrorStream(true);
log_path = fullfile(output, 'inference.log');
builder.redirectOutput(java.io.File(log_path));
process = builder.start();
process_cleanup = onCleanup(@() local_stop(process));
started = tic;
last_text = '';
while process.isAlive()
    if ~isempty(options.CancelFcn) && options.CancelFcn()
        error('Wrapper:MoECancelled', 'Detection canceled; existing annotations were preserved.');
    end
    if toc(started) > options.TimeoutSeconds
        error('Wrapper:MoETimeout', 'Detection timed out. See %s.', log_path);
    end
    if exist(log_path, 'file') == 2
        content = fileread(log_path);
        tokens = regexp(content, 'NEUROPAL_PROGRESS:([^\r\n]+)', 'tokens');
        if ~isempty(tokens) && ~strcmp(last_text, tokens{end}{1})
            last_text = tokens{end}{1};
            if ~isempty(options.ProgressFcn), options.ProgressFcn(last_text); end
        end
    end
    drawnow limitrate;
    pause(0.2);
end
if process.exitValue() ~= 0
    detail = fileread(log_path);
    detail = detail(max(1, end-4000):end);
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
        any(centers >= bounds+1,'all') || any(~isfinite(scores) | scores < 0 | scores > 1)
    error('Wrapper:MoEInvalidResponse', 'Detector returned invalid centers or scores.');
end
response.centroids_yxz = centers;
response.output_dir = output;
end

function local_stop(process)
if process.isAlive()
    process.destroy();
end
end

function local_cleanup(path, keep)
if ~keep && exist(path, 'dir') == 7, rmdir(path, 's'); end
end
