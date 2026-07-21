function test_method_registry()
%TEST_METHOD_REGISTRY Fast contract checks for product-facing method adapters.

[detect_names, detect_ids] = Methods.MethodRegistry.uiChoices('detection');
assert(isequal(size(detect_names), size(detect_ids)));
assert(any(strcmp(detect_ids, 'yolo')));
assert(~any(strcmp(detect_ids, 'spotiflow_supervised')));

[id_names, id_ids] = Methods.MethodRegistry.uiChoices('identity');
assert(any(strcmp(id_names, 'Anshita GAT')));
assert(any(strcmp(id_ids, 'legacy_atlas')));
assert(~any(strcmp(id_ids, 'crf_cellid_2')));

detection = table(1, 2, 3, 0.9, ...
    'VariableNames', {'x_um', 'y_um', 'z_um', 'score'});
Methods.MethodContract.detection(detection);

identity = table(1, "AVA", 0.8, ...
    'VariableNames', {'neuron_idx', 'predicted_class', 'confidence'});
Methods.MethodContract.identity(identity);

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
