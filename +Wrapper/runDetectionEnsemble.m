function [predictions, response] = runDetectionEnsemble(spotiflow_csv, yolo_csv, nnunet_csv, options)
%RUNDETECTIONENSEMBLE Fuse three canonical expert prediction CSV files.

arguments
    spotiflow_csv (1,1) string
    yolo_csv (1,1) string
    nnunet_csv (1,1) string
    options.PythonExecutable (1,1) string = ""
    options.SpotiflowThreshold (1,1) double = 0.30
    options.YoloThreshold (1,1) double = 0.30
    options.NnunetThreshold (1,1) double = 0.30
    options.AgreementRadiusUm (1,1) double = 3.0
    options.IsolationRadiusUm (1,1) double = 2.5
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = false
end

paths = {spotiflow_csv, yolo_csv, nnunet_csv};
for i = 1:numel(paths)
    if exist(paths{i}, 'file') ~= 2
        error('Wrapper:MissingEnsembleExpert', ...
            'Ensemble expert predictions are missing: %s', paths{i});
    end
end
thresholds = [options.SpotiflowThreshold, options.YoloThreshold, options.NnunetThreshold];
if any(~isfinite(thresholds)) || any(thresholds < 0 | thresholds > 1) || ...
        ~isfinite(options.AgreementRadiusUm) || options.AgreementRadiusUm <= 0 || ...
        ~isfinite(options.IsolationRadiusUm) || options.IsolationRadiusUm < 0
    error('Wrapper:InvalidEnsembleOptions', ...
        'Expert thresholds must be in [0,1], with positive agreement and nonnegative isolation radii.');
end

python = local_pick_python(options.PythonExecutable);
if isempty(python)
    error('Wrapper:EnsemblePythonUnavailable', ...
        'Could not resolve Python for detection ensemble fusion.');
end
output_dir = char(options.OutputDir);
if isempty(strtrim(output_dir))
    output_dir = tempname;
end
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end
cleanup = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts));

request_path = fullfile(output_dir, 'ensemble_request.json');
response_path = fullfile(output_dir, 'ensemble_response.json');
output_csv = fullfile(output_dir, 'predictions.csv');
request = struct( ...
    'spotiflow_csv', char(spotiflow_csv), ...
    'yolo_csv', char(yolo_csv), ...
    'nnunet_csv', char(nnunet_csv), ...
    'spotiflow_threshold', options.SpotiflowThreshold, ...
    'yolo_threshold', options.YoloThreshold, ...
    'nnunet_threshold', options.NnunetThreshold, ...
    'agreement_radius_um', options.AgreementRadiusUm, ...
    'isolation_radius_um', options.IsolationRadiusUm, ...
    'output_csv', output_csv);
local_write_json(request_path, request);

bridge = fullfile(fileparts(mfilename('fullpath')), 'advanced_method_bridge.py');
command = strjoin(cellfun(@local_quote, ...
    {python, bridge, 'ensemble', '--request', request_path, '--response', response_path}, ...
    'UniformOutput', false), ' ');
[status, output] = system(command);
if status ~= 0
    error('Wrapper:EnsembleFusionFailed', ...
        'Detection ensemble fusion failed (%d):\n%s', status, output);
end
if exist(output_csv, 'file') ~= 2 || exist(response_path, 'file') ~= 2
    error('Wrapper:MissingEnsembleResponse', ...
        'Detection ensemble did not produce its canonical outputs.');
end
predictions = readtable(output_csv, 'TextType', 'string');
predictions = Methods.MethodContract.detection(predictions);
response = jsondecode(fileread(response_path));
end

function local_write_json(path_value, value)
fid = fopen(path_value, 'w');
if fid < 0
    error('Wrapper:EnsembleRequestWriteFailed', 'Cannot write %s.', path_value);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(value, PrettyPrint=true), 'char');
end

function python = local_pick_python(explicit)
candidates = {char(explicit), getenv('NEUROPAL_ENSEMBLE_PYTHON'), 'python3', 'python'};
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

function value = local_quote(value)
value = char(string(value));
value = ['''', strrep(value, '''', '''"''"'''), ''''];
end

function local_cleanup(output_dir, keep_artifacts)
if ~keep_artifacts && exist(output_dir, 'dir') == 7
    try
        rmdir(output_dir, 's');
    catch
    end
end
end
