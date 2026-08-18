function response = runSpotiflowCentroids(volume, scale_um_xyz, options)
%RUNSPOTIFLOWCENTROIDS Run the checkpoint-backed Spotiflow app bridge.

arguments
    volume
    scale_um_xyz double
    options.BundlePath (1,1) string = ""
    options.PythonExecutable (1,1) string = ""
    options.ProbabilityThreshold (1,1) double = NaN
    options.MinimumDistance (1,1) double = 1
    options.Device (1,1) string = "auto"
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = false
    options.ProgressFcn = []
end

readiness = Methods.MethodBundle.inspect('spotiflow_supervised', options.BundlePath);
if ~readiness.ready
    error('Wrapper:SpotiflowBundleUnavailable', '%s', readiness.summary);
end
checkpoint_path = Methods.MethodBundle.artifact(readiness, 'checkpoint');
model_manifest_path = Methods.MethodBundle.artifact(readiness, 'model_manifest');
config = readiness.manifest.configuration;
if exist(checkpoint_path, 'dir') ~= 7
    error('Wrapper:SpotiflowBundleUnavailable', ...
        'Spotiflow checkpoint must be a model folder: %s', checkpoint_path);
end
if isempty(volume) || size(volume, 4) ~= 4
    error('Wrapper:SpotiflowInvalidInput', ...
        'Spotiflow requires a nonempty Y,X,Z,RGBW volume with exactly four channels.');
end
scale = double(scale_um_xyz(:)');
if numel(scale) ~= 3 || any(~isfinite(scale)) || any(scale <= 0)
    error('Wrapper:SpotiflowInvalidInput', ...
        'Spotiflow scale_um_xyz must contain three finite positive values.');
end
if ~strcmpi(char(string(local_config(config, 'input_mode', 'rgbw'))), 'rgbw')
    error('Wrapper:SpotiflowBundleUnavailable', ...
        'This app adapter only supports Spotiflow bundles with input_mode "rgbw".');
end
if (~isnan(options.ProbabilityThreshold) && ...
        (options.ProbabilityThreshold < 0 || options.ProbabilityThreshold > 1)) || ...
        options.MinimumDistance < 1
    error('Wrapper:SpotiflowInvalidOptions', ...
        'ProbabilityThreshold must be NaN or in [0,1], and MinimumDistance must be at least 1.');
end

python_executable = local_pick_python(options.PythonExecutable);
if isempty(python_executable)
    error('Wrapper:SpotiflowUnavailable', ...
        'Could not resolve Python. Set NEUROPAL_SPOTIFLOW_PYTHON or choose it in method settings.');
end

output_dir = char(options.OutputDir);
if isempty(strtrim(output_dir))
    output_dir = tempname;
end
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end
cleanup = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts));

local_progress(options.ProgressFcn, 'Staging Spotiflow request...');
volume_path = fullfile(output_dir, 'spotiflow_volume.bin');
request_path = fullfile(output_dir, 'request.json');
response_path = fullfile(output_dir, 'response.json');
predictions_path = fullfile(output_dir, 'predictions.csv');
local_write_volume(volume_path, volume);

operating_threshold = options.ProbabilityThreshold;
if isnan(operating_threshold)
    operating_threshold = double(local_config(config, 'operating_score_threshold', 0.185));
end

request = struct( ...
    'volume_raw', volume_path, ...
    'volume_shape_yxzc', double(size(volume)), ...
    'volume_dtype', 'float32', ...
    'volume_order', 'F', ...
    'scale_um_xyz', scale, ...
    'checkpoint', checkpoint_path, ...
    'model_manifest', model_manifest_path, ...
    'which', local_config(config, 'which', 'last'), ...
    'normalizer_mode', local_config(config, 'normalizer_mode', 'per-channel'), ...
    'views', {local_cellstr(local_config(config, 'views', ...
        {'identity', 'flip-x', 'flip-y', 'flip-xy'}))}, ...
    'merge_radius_um', double(local_config(config, 'merge_radius_um', 2.0)), ...
    'candidate_probability', double(local_config(config, 'candidate_probability', 0.02)), ...
    'operating_score_threshold', operating_threshold, ...
    'support_power', double(local_config(config, 'support_power', 1.0)), ...
    'minimum_distance', round(options.MinimumDistance), ...
    'subpixel', logical(local_config(config, 'subpixel', true)), ...
    'peak_mode', char(string(local_config(config, 'peak_mode', 'fast'))), ...
    'deterministic', logical(local_config(config, 'deterministic', true)), ...
    'source_revision', char(string(local_config(config, 'source_revision', 'unknown'))), ...
    'device', char(options.Device), ...
    'output_csv', predictions_path);
local_write_json(request_path, request);

bridge_path = fullfile(fileparts(mfilename('fullpath')), 'advanced_method_bridge.py');
command = local_join_quoted({python_executable, bridge_path, 'spotiflow', ...
    '--request', request_path, '--response', response_path});
local_progress(options.ProgressFcn, 'Running Spotiflow detector...');
[status, output] = system(command);
local_emit_progress(options.ProgressFcn, output);
if status ~= 0
    output_lower = lower(output);
    if contains(output_lower, 'no module named') || contains(output_lower, 'modulenotfounderror')
        error('Wrapper:SpotiflowUnavailable', ...
            ['Spotiflow dependencies are missing from %s. Install the bundle environment ' ...
             'or set NEUROPAL_SPOTIFLOW_PYTHON.\n\n%s'], python_executable, output);
    end
    error('Wrapper:SpotiflowCommandFailed', 'Spotiflow failed (%d):\n%s', status, output);
end
if exist(response_path, 'file') ~= 2
    error('Wrapper:MissingSpotiflowResponse', ...
        'Spotiflow did not write its response: %s', response_path);
end
response = jsondecode(fileread(response_path));
end

function local_write_volume(path_value, volume)
fid = fopen(path_value, 'w');
if fid < 0
    error('Wrapper:SpotiflowVolumeWriteFailed', 'Cannot write %s.', path_value);
end
cleanup = onCleanup(@() fclose(fid));
count = fwrite(fid, volume, 'single');
if count ~= numel(volume)
    error('Wrapper:SpotiflowVolumeWriteFailed', ...
        'Only wrote %d of %d volume values to %s.', count, numel(volume), path_value);
end
end

function value = local_config(config, field_name, default_value)
value = default_value;
if isstruct(config) && isfield(config, field_name)
    value = config.(field_name);
end
end

function values = local_cellstr(value)
if iscell(value)
    values = cellfun(@(item) char(string(item)), value, 'UniformOutput', false);
else
    values = cellstr(string(value));
end
values = values(:)';
end

function local_write_json(path_value, value)
fid = fopen(path_value, 'w');
if fid < 0
    error('Wrapper:SpotiflowRequestWriteFailed', 'Cannot write %s.', path_value);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(value, PrettyPrint=true), 'char');
end

function python = local_pick_python(explicit)
candidates = {char(explicit), getenv('NEUROPAL_SPOTIFLOW_PYTHON'), 'python3', 'python'};
python = '';
for i = 1:numel(candidates)
    candidate = strtrim(candidates{i});
    if isempty(candidate)
        continue
    end
    if contains(candidate, filesep) && exist(candidate, 'file') == 2
        python = candidate;
        return
    end
    [status, output] = system(sprintf('command -v %s', local_quote(candidate)));
    if status == 0
        python = strtrim(output);
        return
    end
end
end

function command = local_join_quoted(parts)
command = strjoin(cellfun(@local_quote, parts, 'UniformOutput', false), ' ');
end

function value = local_quote(value)
value = char(string(value));
value = ['''', strrep(value, '''', '''"''"'''), ''''];
end

function local_progress(callback, message)
if isempty(callback) || ~isa(callback, 'function_handle')
    return
end
try
    callback(char(string(message)));
catch
end
end

function local_emit_progress(callback, output)
lines = regexp(char(output), '\r\n|\n|\r', 'split');
for i = 1:numel(lines)
    if startsWith(lines{i}, 'NEUROPAL_PROGRESS:')
        local_progress(callback, extractAfter(lines{i}, 'NEUROPAL_PROGRESS:'));
    end
end
end

function local_cleanup(output_dir, keep_artifacts)
if ~keep_artifacts && exist(output_dir, 'dir') == 7
    try
        rmdir(output_dir, 's');
    catch
    end
end
end
