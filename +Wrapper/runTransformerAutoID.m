function predictions = runTransformerAutoID(nwb_path, options)
%RUNTRANSFORMERAUTOID Run Anshita GAT/transformer auto-ID inference.

arguments
    nwb_path (1,1) string
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
    options.JobToken (1,1) string = ""
    options.CancelFcn = []
    options.TimeoutSeconds (1,1) double = 10800
    options.ProgressFcn = []
end
job = Program.HeavyJob.acquire('runTransformerAutoID', options.JobToken);
job_cleanup = onCleanup(@() delete(job));

if exist(nwb_path, 'file') ~= 2
    error('Wrapper:MissingNWB', 'NWB file not found: %s', nwb_path);
end
local_progress(options.ProgressFcn, 'Checking transformer files...');
[repo_dir, checkpoint_path] = Methods.ModelSetup.transformer( ...
    options.RepoDir, options.CheckpointPath, 'run_inference.py');
script_path = fullfile(repo_dir, 'run_inference.py');

context=Runtime.Resolver.require('anshita_gat',struct('python',char(options.PythonExecutable),'source',repo_dir,'checkpoint',checkpoint_path),options.CancelFcn);
python_executable=context.python;
if isempty(python_executable)
    error('Wrapper:NoPython', 'Could not resolve Python. Open Tools > Models & runtimes to select the required Python installation.');
end

local_progress(options.ProgressFcn, 'Staging NWB for transformer preprocessing...');
test_dir = tempname;
mkdir(test_dir);
cleanup = onCleanup(@() local_cleanup(test_dir));
checkpoint_path=Runtime.Checkpoint.stage(checkpoint_path,fullfile(test_dir,'checkpoint'));
[~, name, ext] = fileparts(nwb_path);
dataset_id = char(strtrim(options.DatasetID));
if isempty(dataset_id)
    dataset_id = '000981';
end
staged_name = sprintf('%s__%s%s', dataset_id, name, ext);
local_stage_nwb(nwb_path, fullfile(test_dir, staged_name));

command_parts = { ...
    python_executable, script_path, ...
    '--checkpoint_path', checkpoint_path, ...
    '--test_dir', test_dir, ...
    '--batch_size', num2str(round(options.BatchSize)), ...
    '--num_workers', num2str(round(options.NumWorkers)), ...
    '--preprocess_workers', num2str(round(options.PreprocessWorkers)), ...
    '--min_neighbors', num2str(round(options.MinNeighbors)), ...
    '--mc_samples', num2str(round(options.MCSamples)), ...
    '--confidence_threshold', num2str(options.ConfidenceThreshold), ...
    '--uncertainty_threshold', num2str(options.UncertaintyThreshold), ...
    '--quality_threshold', num2str(options.QualityThreshold), ...
    '--output_name', char(options.OutputName)};
if strlength(options.Device) > 0
    command_parts(end+1:end+2) = {'--device', char(options.Device)};
end

local_progress(options.ProgressFcn, 'Running transformer preprocessing and inference...');
[status, output] = Wrapper.runPythonProcess(command_parts, ...
    'JobToken', job.Token, 'ProgressFcn', options.ProgressFcn, ...
    'CancelFcn', options.CancelFcn, 'TimeoutSeconds', options.TimeoutSeconds, 'WorkingDirectory', repo_dir);
local_emit_progress_lines(options.ProgressFcn, output);
if status ~= 0
    friendly_message = local_transformer_failure_message(output, checkpoint_path);
    if ~isempty(friendly_message)
        error('Wrapper:TransformerUnavailable', '%s', friendly_message);
    end
    error('Wrapper:TransformerCommandFailed', 'Transformer auto-ID failed (%d):\n%s', status, output);
end

local_progress(options.ProgressFcn, 'Reading transformer predictions...');
run_dir = checkpoint_path;
if exist(run_dir, 'file') == 2
    run_dir = fileparts(run_dir);
end

csv_path = fullfile(run_dir, char(options.OutputName));
if exist(csv_path, 'file') ~= 2
    error('Wrapper:MissingTransformerPredictions', 'Prediction CSV missing: %s', csv_path);
end

predictions = readtable(csv_path, 'TextType', 'string');
local_progress(options.ProgressFcn, sprintf('Transformer auto-ID finished: %d predictions.', height(predictions)));
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

function local_cleanup(test_dir)
if exist(test_dir, 'dir') == 7
    try
        rmdir(test_dir, 's');
    catch
    end
end
end

function local_stage_nwb(source_path, staged_path)
source_path = char(string(source_path));
staged_path = char(string(staged_path));
if isunix
    [status, ~] = system(sprintf('ln -s %s %s', ...
        local_shell_quote(source_path), local_shell_quote(staged_path)));
    if status == 0 && exist(staged_path, 'file') == 2
        return
    end
end
copyfile(source_path, staged_path);
end



function out = local_shell_quote(value)
value = char(string(value));
out = ['''', strrep(value, '''', '''"''"'''), ''''];
end
