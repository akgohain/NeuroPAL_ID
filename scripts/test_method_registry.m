function test_method_registry()
%TEST_METHOD_REGISTRY Fast contract checks for product-facing method adapters.

[detect_names, detect_ids] = Methods.MethodRegistry.uiChoices('detection');
assert(isequal(size(detect_names), size(detect_ids)));
assert(any(strcmp(detect_ids, 'yolo')));
assert(any(strcmp(detect_ids, 'spotiflow_supervised')));
assert(~any(strcmp(detect_ids, 'detection_moe')));

[id_names, id_ids] = Methods.MethodRegistry.uiChoices('identity');
assert(any(strcmp(id_names, 'Anshita GAT')));
assert(any(strcmp(id_ids, 'legacy_atlas')));
assert(any(strcmp(id_ids, 'crf_cellid_2')));

template_bundle = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'method_bundles', 'spotiflow_supervised');
readiness = Methods.MethodBundle.inspect('spotiflow_supervised', template_bundle);
assert(~readiness.ready);
assert(any(strcmp(readiness.missing, 'method_bundle.json')));

fixture_bundle = fullfile(fileparts(mfilename('fullpath')), ...
    'fixtures', 'crfid2_bundle');
readiness = Methods.MethodBundle.inspect('crf_cellid_2', fixture_bundle);
assert(readiness.ready, readiness.summary);
assert(exist(Methods.MethodBundle.artifact(readiness, 'adapter'), 'file') == 2);

detection = table(1, 2, 3, 0.9, ...
    'VariableNames', {'x_um', 'y_um', 'z_um', 'score'});
Methods.MethodContract.detection(detection);

identity = table(1, "AVA", 0.8, ...
    'VariableNames', {'neuron_idx', 'predicted_class', 'confidence'});
Methods.MethodContract.identity(identity);
duplicate_identity = [identity; identity];
local_assert_error(@() Methods.MethodContract.identity(duplicate_identity), ...
    'Methods:MethodContract:DuplicateNeuronIndex');

manifest = struct( ...
    'schema_version', 1, ...
    'method_id', 'spotiflow_supervised', ...
    'display_name', 'Unsafe fixture', ...
    'configuration', struct(), ...
    'artifacts', struct('role', 'checkpoint', 'path', '../outside', 'required', true));
local_assert_error(@() Methods.MethodBundle.validateManifest( ...
    'spotiflow_supervised', manifest), 'Methods:MethodBundle:UnsafeArtifactPath');

image_neurons = Neurons.Image([]);
image_neurons.neurons(1) = Neurons.Neuron();
image_neurons.neurons(1).deterministic_id = 'AVA';
image_neurons.neurons(1).probabilistic_ids = {'AVA', 'AVB'};
image_neurons.neurons(1).probabilistic_probs = [0.8, 0.2];
image_neurons.neurons(1).rank = 1;
snapshot = Methods.TransformerAutoId.captureModelIDs(image_neurons);
image_neurons.delete_model_IDs();
Methods.TransformerAutoId.restoreModelIDs(image_neurons, snapshot);
assert(strcmp(image_neurons.neurons(1).deterministic_id, 'AVA'));
assert(isequal(image_neurons.neurons(1).probabilistic_probs, [0.8, 0.2]));

fprintf('METHOD_REGISTRY_SMOKE=PASS\n');
end

function local_assert_error(callback, expected_identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, expected_identifier), ...
        'Expected %s, received %s.', expected_identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', ...
    'Expected callback to throw %s.', expected_identifier);
end
