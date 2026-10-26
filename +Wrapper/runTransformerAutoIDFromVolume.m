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
    options.JobToken (1,1) string = ""
    options.CancelFcn = []
    options.TimeoutSeconds (1,1) double = 10800
    options.ProgressFcn = []
end
job = Program.HeavyJob.acquire('runTransformerAutoIDFromVolume', options.JobToken);
job_cleanup = onCleanup(@() delete(job));

if isempty(volume_yxzc)
    error('Wrapper:TransformerEmptyVolume', 'Cannot run transformer auto-ID with an empty volume.');
end
if isempty(positions_yxz)
    error('Wrapper:TransformerNoCentroids', 'Cannot run transformer auto-ID before neurons are detected.');
end

[repo_dir, checkpoint_path] = Methods.ModelSetup.transformer(options.RepoDir, options.CheckpointPath);
script_path = fullfile(repo_dir, 'run_app_volume_inference.py');
context=Runtime.Resolver.require('anshita_gat',struct('python',char(options.PythonExecutable),'source',repo_dir,'checkpoint',checkpoint_path),options.CancelFcn);
python_executable=context.python;
if isempty(python_executable)
    error('Wrapper:NoPython', 'Could not resolve Python. Open Tools > Models & runtimes to select the required Python installation.');
end

output_dir = char(options.OutputDir);
if isempty(strtrim(output_dir))
    output_dir = tempname;
end
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end

cleanup = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts));
checkpoint_path=Runtime.Checkpoint.stage(checkpoint_path,fullfile(output_dir,'checkpoint'));
local_progress(options.ProgressFcn, 'Staging app volume request for transformer auto-ID...');

request_path = fullfile(output_dir, 'transformer_stage_request.mat');
request = struct();
request.volume = volume_yxzc;
request.positions_yxz = positions_yxz;
request.scale_um_xyz = scale_um_xyz(:)';
request.labels = cellstr(string(options.Labels(:)));
request.animal_id = 'neuropal_app_volume';
save(request_path, '-struct', 'request', '-v7');

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

[status, output] = Wrapper.runPythonProcess(command_parts, ...
    'JobToken', job.Token, 'ProgressFcn', options.ProgressFcn, ...
    'CancelFcn', options.CancelFcn, 'TimeoutSeconds', options.TimeoutSeconds, 'WorkingDirectory', repo_dir);
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
if contains(output_text, 'no module named') || contains(output_text, 'modulenotfounderror')
    message = ['Transformer dependencies are not available in the selected Python environment. ' ...
        'Open Tools > Models & runtimes to select the required Python installation.'];
    return
end
if contains(output_text, 'checkpoint') || contains(output_text, 'best_model.pt') || ...
        contains(output_text, 'no such file') || contains(output_text, 'filenotfounderror')
    message = sprintf(['Transformer checkpoint could not be loaded from %s. ' ...
        'Point the method settings to a checkpoint directory containing best_model.pt.'], checkpoint_path);
end
end


function out = local_shell_quote(value)
value = char(string(value));
out = ['''', strrep(value, '''', '''"''"'''), ''''];
end
