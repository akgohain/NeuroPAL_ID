function predictions = runTransformerAutoIDFromVolume(volume_yxzc, positions_yxz, scale_um_xyz, options)
%RUNTRANSFORMERAUTOIDFROMVOLUME Run transformer auto-ID from app volume arrays.

arguments
    volume_yxzc
    positions_yxz double
    scale_um_xyz double
    options.Labels = strings(0, 1)
    options.PythonExecutable (1,1) string = ""
    options.RepoDir (1,1) string = ""
    options.CheckpointPath (1,1) string = ""
    options.BatchSize (1,1) double = 32
    options.NumWorkers (1,1) double = 0
    options.PreprocessWorkers (1,1) double = 0
    options.MinNeighbors (1,1) double = 2
    options.MCSamples (1,1) double = 20
    options.ConfidenceThreshold (1,1) double = 0.5
    options.UncertaintyThreshold (1,1) double = 0.05
    options.QualityThreshold (1,1) double = 0.3
    options.Device (1,1) string = ""
    options.DatasetID (1,1) string = "000981"
    options.OutputName (1,1) string = "neuropal_app_predictions.csv"
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = false
    options.ProgressFcn = []
end

if isempty(volume_yxzc)
    error('Wrapper:TransformerEmptyVolume', 'Cannot run transformer auto-ID with an empty volume.');
end
if isempty(positions_yxz)
    error('Wrapper:TransformerNoCentroids', 'Cannot run transformer auto-ID before neurons are detected.');
end

output_dir = char(options.OutputDir);
if isempty(strtrim(output_dir))
    output_dir = tempname;
end
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end

cleanup = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts));
local_progress(options.ProgressFcn, 'Staging app volume request for transformer auto-ID...');

request_path = fullfile(output_dir, 'transformer_stage_request.mat');
request = struct();
request.volume = volume_yxzc;
request.positions_yxz = positions_yxz;
request.scale_um_xyz = scale_um_xyz(:)';
request.labels = cellstr(string(options.Labels(:)));
request.animal_id = 'neuropal_app_volume';
save(request_path, '-struct', 'request', '-v7');

python_executable = local_pick_python(char(options.PythonExecutable));
if isempty(python_executable)
    error('Wrapper:NoPython', 'Could not resolve Python. Set NEUROPAL_TRANSFORMER_PYTHON or pass PythonExecutable.');
end

[repo_dir, checkpoint_path] = Wrapper.resolveTransformerAssets( ...
    options.RepoDir, options.CheckpointPath);
script_path = fullfile(repo_dir, 'run_app_volume_inference.py');
if exist(script_path, 'file') ~= 2
    error('Wrapper:MissingTransformerVolumeScript', 'run_app_volume_inference.py not found: %s', script_path);
end
if exist(checkpoint_path, 'file') ~= 2 && exist(checkpoint_path, 'dir') ~= 7
    error('Wrapper:MissingTransformerCheckpoint', ...
        ['Transformer checkpoint path not found: %s\n\n' ...
         'Set the transformer checkpoint path to a run directory containing best_model.pt, ' ...
         'Set NEUROPAL_GAT_CHECKPOINT or choose the checkpoint in method settings.'], checkpoint_path);
end

command_parts = { ...
    python_executable, script_path, ...
    '--checkpoint_path', checkpoint_path, ...
    '--request_mat', request_path, ...
    '--batch_size', num2str(round(options.BatchSize)), ...
    '--min_neighbors', num2str(round(options.MinNeighbors)), ...
    '--mc_samples', num2str(round(options.MCSamples)), ...
    '--confidence_threshold', num2str(options.ConfidenceThreshold), ...
    '--uncertainty_threshold', num2str(options.UncertaintyThreshold), ...
    '--quality_threshold', num2str(options.QualityThreshold), ...
    '--dataset_id', char(options.DatasetID), ...
    '--output_name', char(options.OutputName)};
if strlength(options.Device) > 0
    command_parts(end+1:end+2) = {'--device', char(options.Device)};
end

local_prepare_python_environment();
command = sprintf('cd %s && %s', local_shell_quote(repo_dir), local_join_quoted_command(command_parts));
[status, output] = system(command);
local_emit_progress_lines(options.ProgressFcn, output);
if status ~= 0
    friendly_message = local_transformer_failure_message(output, checkpoint_path);
    if ~isempty(friendly_message)
        error('Wrapper:TransformerUnavailable', '%s', friendly_message);
    end
    error('Wrapper:TransformerCommandFailed', 'Transformer app-volume auto-ID failed (%d):\n%s', status, output);
end

run_dir = checkpoint_path;
if exist(run_dir, 'file') == 2
    run_dir = fileparts(run_dir);
end
csv_path = fullfile(run_dir, char(options.OutputName));
if exist(csv_path, 'file') ~= 2
    error('Wrapper:MissingTransformerPredictions', 'Prediction CSV missing: %s', csv_path);
end
predictions = readtable(csv_path, 'TextType', 'string');
end

function local_cleanup(output_dir, keep_artifacts)
if keep_artifacts
    return
end
if exist(output_dir, 'dir') == 7
    try
        rmdir(output_dir, 's');
    catch
    end
end
end

function path_value = local_pick_python(candidate)
candidate_paths = {
    char(string(candidate))
    getenv('NEUROPAL_TRANSFORMER_PYTHON')
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

function message = local_transformer_failure_message(output, checkpoint_path)
message = '';
output_text = lower(char(string(output)));
if contains(output_text, 'no module named') || contains(output_text, 'modulenotfounderror') || ...
        contains(output_text, 'torch') || contains(output_text, 'pynwb')
    message = ['Transformer dependencies are not available in the selected Python environment. ' ...
        'Set NEUROPAL_TRANSFORMER_PYTHON to the GAT environment or install its requirements.'];
    return
end
if contains(output_text, 'checkpoint') || contains(output_text, 'best_model.pt') || ...
        contains(output_text, 'no such file') || contains(output_text, 'filenotfounderror')
    message = sprintf(['Transformer checkpoint could not be loaded from %s. ' ...
        'Point the method settings to a checkpoint directory containing best_model.pt.'], checkpoint_path);
end
end

function local_prepare_python_environment()
cache_roots = {
    'MPLCONFIGDIR', fullfile(tempdir, 'neuropal_matplotlib')
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
