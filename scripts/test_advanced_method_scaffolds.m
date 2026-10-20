function test_advanced_method_scaffolds()
%TEST_ADVANCED_METHOD_SCAFFOLDS Check adapters that do not require weights.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() local_cleanup(root));
previous_python = getenv('NEUROPAL_ENSEMBLE_PYTHON');
python_cleanup = onCleanup(@() setenv('NEUROPAL_ENSEMBLE_PYTHON', previous_python));
setenv('NEUROPAL_ENSEMBLE_PYTHON', '');

spotiflow = table( ...
    ["spot_1"; "spot_low"], [0; 100], [0; 100], [0; 100], [0.9; 0.1], ...
    'VariableNames', {'pred_id', 'x_um', 'y_um', 'z_um', 'score'});
yolo = table( ...
    ["yolo_rescue"; "yolo_near"], [20; 0.5], [20; 0], [20; 0], [0.8; 0.8], ...
    'VariableNames', {'pred_id', 'x_um', 'y_um', 'z_um', 'score'});
nnunet = table( ...
    ["nn_rescue"; "nn_near"], [21; 0.7], [20; 0], [20; 0], [0.6; 0.7], ...
    'VariableNames', {'pred_id', 'x_um', 'y_um', 'z_um', 'score'});
spot_path = fullfile(root, 'spot.csv');
yolo_path = fullfile(root, 'yolo.csv');
nnunet_path = fullfile(root, 'nnunet.csv');
writetable(spotiflow, spot_path);
writetable(yolo, yolo_path);
writetable(nnunet, nnunet_path);

[ensemble, response] = Wrapper.runDetectionEnsemble( ...
    string(spot_path), string(yolo_path), string(nnunet_path), ...
    'OutputDir', string(fullfile(root, 'ensemble')), 'KeepArtifacts', true);
assert(height(ensemble) == 2);
assert(double(response.num_spotiflow) == 1);
assert(double(response.num_rescued) == 1);
assert(any(strcmp(string(ensemble.source), "yolo+nnunet")));

% Explicit and method-specific interpreters take precedence over the bundle.
unusable_python = fullfile(root, 'unusable-python');
fid = fopen(unusable_python, 'w'); assert(fid >= 0);
fwrite(fid, 'This file is not a Python executable.', 'char'); fclose(fid);
local_assert_failure(@() Wrapper.runDetectionEnsemble( ...
    string(spot_path), string(yolo_path), string(nnunet_path), ...
    'PythonExecutable', string(unusable_python)), 'Wrapper:EnsembleFusionFailed');
setenv('NEUROPAL_ENSEMBLE_PYTHON', unusable_python);
local_assert_failure(@() Wrapper.runDetectionEnsemble( ...
    string(spot_path), string(yolo_path), string(nnunet_path)), 'Wrapper:EnsembleFusionFailed');
setenv('NEUROPAL_ENSEMBLE_PYTHON', '');

fixture_bundle = fullfile(fileparts(mfilename('fullpath')), ...
    'fixtures', 'crfid2_bundle');
predictions = Wrapper.runCRFID2AutoID( ...
    [1 2 3; 4 5 6], ones(2, 4), [0.5 0.5 1.0], ...
    'BundlePath', string(fixture_bundle), ...
    'OutputDir', string(fullfile(root, 'crf')), 'KeepArtifacts', true);
assert(height(predictions) == 2);
assert(all(predictions.predicted_class == "AVA"));
assert(all(abs(double(predictions.confidence) - [0.9; 0.7]) < 1e-12));

fprintf('ADVANCED_METHOD_SCAFFOLDS=PASS\n');
end

function local_assert_failure(action, identifier)
try
    action();
catch failure
    assert(strcmp(failure.identifier, identifier), '%s', failure.message);
    return;
end
error('test:ExpectedFailure', 'Expected %s.', identifier);
end

function local_cleanup(root)
if exist(root, 'dir') == 7
    rmdir(root, 's');
end
end
