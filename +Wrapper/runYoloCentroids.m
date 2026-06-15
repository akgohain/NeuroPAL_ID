function response = runYoloCentroids(volume, scale_um_xyz, options)
%RUNYOLOCENTROIDS Execute Swetha YOLO detection and fused centroid export.

arguments
    volume
    scale_um_xyz double
    options.PythonExecutable (1,1) string = ""
    options.WeightsPath (1,1) string = "/Users/adamg/neuroPAL/artifacts/swetha_yolo_inf/YOLO INF/best.pt"
    options.InferScript (1,1) string = "/Users/adamg/neuroPAL/neuroPAL-detection/yolov8-cell/infer_volume_slices_yolo.py"
    options.FuseScript (1,1) string = "/Users/adamg/neuroPAL/neuroPAL-detection/yolov8-cell/mip_centroids_iou_color_fuse.py"
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = false
    options.Conf (1,1) double = 0.25
    options.ImgSize (1,1) double = 640
    options.BoxMinPx (1,1) double = 2
    options.BoxMaxPx (1,1) double = 80
    options.Device (1,1) string = ""
    options.StretchSlices (1,1) logical = true
    options.StretchMIP (1,1) logical = true
    options.PLo (1,1) double = 2
    options.PHi (1,1) double = 98
    options.FuseMaxDz (1,1) double = 1
    options.IoUMin (1,1) double = 0.5
    options.ColorMatch (1,1) logical = true
    options.ColorDotMin (1,1) double = 0.8
    options.DepthSanity (1,1) logical = true
    options.DepthSanityRatioCap (1,1) double = 1.5
    options.Radius (1,1) double = 2
    options.LineWidth (1,1) double = 2
    options.ProgressFcn = []
end

scale_um_xyz = double(scale_um_xyz(:)');
if numel(scale_um_xyz) ~= 3
    error('Wrapper:InvalidScale', 'scale_um_xyz must contain exactly 3 values.');
end

default_weights_path = "/Users/adamg/neuroPAL/artifacts/swetha_yolo_inf/YOLO INF/best.pt";
default_infer_script = "/Users/adamg/neuroPAL/neuroPAL-detection/yolov8-cell/infer_volume_slices_yolo.py";
default_fuse_script = "/Users/adamg/neuroPAL/neuroPAL-detection/yolov8-cell/mip_centroids_iou_color_fuse.py";

weights_option = options.WeightsPath;
if strlength(weights_option) == 0
    weights_option = default_weights_path;
end
infer_option = options.InferScript;
if strlength(infer_option) == 0
    infer_option = default_infer_script;
end
fuse_option = options.FuseScript;
if strlength(fuse_option) == 0
    fuse_option = default_fuse_script;
end

python_executable = local_pick_python(char(options.PythonExecutable));
if isempty(python_executable)
    error('Wrapper:NoPython', 'Could not resolve Python. Set NEUROPAL_YOLO_PYTHON or pass PythonExecutable.');
end

weights_path = local_existing_file(weights_option, 'YOLO weights', 'Wrapper:MissingYoloWeights', ...
    ['YOLO weights were not found. Put best.pt at the configured path, ' ...
     'set the YOLO weights path in method settings, or set the WeightsPath option.']);
infer_script = local_existing_file(infer_option, 'YOLO inference script', 'Wrapper:MissingYoloScript', ...
    'YOLO inference script was not found. Check the neuroPAL-detection checkout path.');
fuse_script = local_existing_file(fuse_option, 'YOLO fusion script', 'Wrapper:MissingYoloScript', ...
    'YOLO fusion script was not found. Check the neuroPAL-detection checkout path.');

output_dir = char(options.OutputDir);
if isempty(strtrim(output_dir))
    output_dir = tempname;
end
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end

volume_path = fullfile(output_dir, 'request_volume.mat');
request_path = fullfile(output_dir, 'request.json');
response_path = fullfile(output_dir, 'response.json');
cleanup_obj = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts)); %#ok<NASGU>

request = struct();
request.volume = volume;
save(volume_path, '-struct', 'request', '-v7');

manifest = struct( ...
    'volume_mat', volume_path, ...
    'scale_um_xyz', scale_um_xyz, ...
    'weights', weights_path, ...
    'infer_script', infer_script, ...
    'fuse_script', fuse_script, ...
    'output_dir', output_dir, ...
    'conf', clamp(options.Conf, 0, 1), ...
    'imgsz', round(clamp(options.ImgSize, 64, 4096)), ...
    'box_min_px', clamp(options.BoxMinPx, 0, 2048), ...
    'box_max_px', clamp(options.BoxMaxPx, 1, 4096), ...
    'device', char(options.Device), ...
    'stretch_slices', logical(options.StretchSlices), ...
    'stretch_mip', logical(options.StretchMIP), ...
    'p_lo', clamp(options.PLo, 0, 100), ...
    'p_hi', clamp(options.PHi, 0, 100), ...
    'fuse_max_dz', round(clamp(options.FuseMaxDz, 0, 25)), ...
    'iou_min', clamp(options.IoUMin, 0, 1), ...
    'color_match', logical(options.ColorMatch), ...
    'color_dot_min', clamp(options.ColorDotMin, 0, 1), ...
    'depth_sanity', logical(options.DepthSanity), ...
    'depth_sanity_ratio_cap', clamp(options.DepthSanityRatioCap, 0.1, 20), ...
    'radius', round(clamp(options.Radius, 0, 50)), ...
    'line_width', round(clamp(options.LineWidth, 1, 20)));

fid = fopen(request_path, 'w');
fwrite(fid, jsonencode(manifest), 'char');
fclose(fid);

wrapper_dir = fileparts(mfilename('fullpath'));
script_path = fullfile(wrapper_dir, 'yolo_centroids.py');
local_prepare_python_environment();
command = local_join_quoted_command({python_executable, script_path, '--request', request_path, '--response', response_path});
local_progress(options.ProgressFcn, 'Running YOLO detector...');
[status, output] = system(command);
local_emit_progress_lines(options.ProgressFcn, output);
if status ~= 0
    friendly_message = local_yolo_failure_message(output, weights_path);
    if ~isempty(friendly_message)
        error('Wrapper:YoloUnavailable', '%s', friendly_message);
    end
    error('Wrapper:YoloCommandFailed', 'YOLO command failed (%d):\n%s', status, output);
end
if exist(response_path, 'file') ~= 2
    error('Wrapper:MissingYoloResponse', 'YOLO response file missing: %s', response_path);
end
response = jsondecode(fileread(response_path));
end

function value = clamp(value, lo, hi)
value = min(max(double(value), lo), hi);
end

function path_value = local_existing_file(path_value, label, identifier, guidance)
path_value = char(string(path_value));
if exist(path_value, 'file') ~= 2
    error(identifier, '%s not found: %s\n\n%s', label, path_value, guidance);
end
end

function message = local_yolo_failure_message(output, weights_path)
message = '';
output_text = lower(char(string(output)));
if contains(output_text, 'no module named') || contains(output_text, 'modulenotfounderror') || ...
        contains(output_text, 'ultralytics') || contains(output_text, 'torch')
    message = ['YOLO dependencies are not available in the selected Python environment. ' ...
        'Install ultralytics/torch there or set NEUROPAL_YOLO_PYTHON to the environment that has them.'];
    return
end
if contains(output_text, 'no such file') || contains(output_text, 'filenotfounderror') || ...
        contains(output_text, 'best.pt')
    message = sprintf('YOLO could not load weights: %s', char(string(weights_path)));
end
end

function local_progress(progress_fcn, message)
if isempty(progress_fcn) || ~isa(progress_fcn, 'function_handle')
    return
end
try
    progress_fcn(char(string(message)));
catch
end
end

function local_emit_progress_lines(progress_fcn, output)
if isempty(output)
    return
end
lines = regexp(char(output), '\r\n|\n|\r', 'split');
for n = 1:numel(lines)
    line = strtrim(lines{n});
    prefix = 'NEUROPAL_PROGRESS:';
    if startsWith(line, prefix)
        local_progress(progress_fcn, strtrim(extractAfter(line, strlength(prefix))));
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

function path_value = local_pick_python(candidate)
candidate_paths = {
    char(string(candidate))
    getenv('NEUROPAL_YOLO_PYTHON')
    '/Users/adamg/neuroPAL/.venv-ai-pipeline/bin/python'
    'python3'
    'python'
    };
path_value = '';
for i = 1:numel(candidate_paths)
    resolved = local_realpath_interpreter(candidate_paths{i});
    if ~isempty(resolved)
        path_value = resolved;
        return
    end
end
end

function path_value = local_realpath_interpreter(path_value)
path_value = char(string(path_value));
if isempty(strtrim(path_value))
    path_value = '';
    return
end
if contains(path_value, filesep) && exist(path_value, 'file') == 2
    return
end
[status, output] = system(sprintf('command -v %s', local_shell_quote(path_value)));
if status == 0
    path_value = strtrim(output);
else
    path_value = '';
end
end

function command = local_join_quoted_command(parts)
quoted = cell(size(parts));
for i = 1:numel(parts)
    quoted{i} = local_shell_quote(parts{i});
end
command = strjoin(quoted, ' ');
end

function out = local_shell_quote(value)
value = char(string(value));
out = ['''', strrep(value, '''', '''"''"'''), ''''];
end

function local_prepare_python_environment()
cache_roots = {
    'MPLCONFIGDIR', fullfile(tempdir, 'neuropal_matplotlib')
    'YOLO_CONFIG_DIR', fullfile(tempdir, 'neuropal_ultralytics')
    'XDG_CONFIG_HOME', fullfile(tempdir, 'neuropal_config')
    };
for i = 1:size(cache_roots, 1)
    key = cache_roots{i, 1};
    value = cache_roots{i, 2};
    if isempty(strtrim(getenv(key)))
        setenv(key, value);
    else
        value = getenv(key);
    end
    if exist(value, 'dir') ~= 7
        mkdir(value);
    end
end
end
