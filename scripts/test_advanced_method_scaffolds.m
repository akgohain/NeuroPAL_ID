function test_advanced_method_scaffolds()
%TEST_ADVANCED_METHOD_SCAFFOLDS Check adapters that do not require weights.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() local_cleanup(root));

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

function local_cleanup(root)
if exist(root, 'dir') == 7
    rmdir(root, 's');
end
end
