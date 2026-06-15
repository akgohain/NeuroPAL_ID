function predictions = runTransformerAutoIDFromVolume(volume_yxzc, positions_yxz, scale_um_xyz, options)
%RUNTRANSFORMERAUTOIDFROMVOLUME Stage app data as NWB and run transformer auto-ID.

arguments
    volume_yxzc
    positions_yxz double
    scale_um_xyz double
    options.Labels = strings(0, 1)
    options.PythonExecutable (1,1) string = ""
    options.RepoDir (1,1) string = "/Users/adamg/neuroPAL/GAT-NeuroPAL"
    options.CheckpointPath (1,1) string = "/Users/adamg/neuroPAL/artifacts/anshita_transformer"
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

cleanup = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts)); %#ok<NASGU>
local_progress(options.ProgressFcn, 'Staging app volume for transformer auto-ID...');

request_path = fullfile(output_dir, 'transformer_stage_request.mat');
staged_nwb_path = fullfile(output_dir, 'neuropal_app_transformer_stage.nwb');
request = struct();
request.volume = volume_yxzc;
request.positions_yxz = positions_yxz;
request.scale_um_xyz = scale_um_xyz(:)';
request.labels = cellstr(string(options.Labels(:)));
request.output_path = staged_nwb_path;
save(request_path, '-struct', 'request', '-v7');

python_executable = local_pick_python(char(options.PythonExecutable));
if isempty(python_executable)
    error('Wrapper:NoPython', 'Could not resolve Python. Set NEUROPAL_TRANSFORMER_PYTHON or pass PythonExecutable.');
end

script_path = fullfile(fileparts(mfilename('fullpath')), 'stage_transformer_nwb.py');
command_parts = {python_executable, script_path, '--request', request_path};
command = local_join_quoted_command(command_parts);
[status, output] = system(command);
local_emit_progress_lines(options.ProgressFcn, output);
if status ~= 0
    error('Wrapper:TransformerStageFailed', 'Could not stage transformer NWB (%d):\n%s', status, output);
end
if exist(staged_nwb_path, 'file') ~= 2
    error('Wrapper:TransformerMissingStage', 'Staged transformer NWB missing: %s', staged_nwb_path);
end

predictions = Wrapper.runTransformerAutoID(staged_nwb_path, ...
    'PythonExecutable', python_executable, ...
    'RepoDir', options.RepoDir, ...
    'CheckpointPath', options.CheckpointPath, ...
    'BatchSize', options.BatchSize, ...
    'NumWorkers', options.NumWorkers, ...
    'PreprocessWorkers', options.PreprocessWorkers, ...
    'MinNeighbors', options.MinNeighbors, ...
    'MCSamples', options.MCSamples, ...
    'ConfidenceThreshold', options.ConfidenceThreshold, ...
    'UncertaintyThreshold', options.UncertaintyThreshold, ...
    'QualityThreshold', options.QualityThreshold, ...
    'Device', options.Device, ...
    'DatasetID', options.DatasetID, ...
    'OutputName', options.OutputName, ...
    'ProgressFcn', options.ProgressFcn);
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
