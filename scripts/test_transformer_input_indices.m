function test_transformer_input_indices()
% Check that staged-volume predictions retain the current neuron order.
predictions = table([2; 0; 1], ["AVAL"; "AVAR"; "FAILED"], [.8; .9; NaN], ...
    'VariableNames', {'neuron_idx', 'predicted_class', 'confidence'});
predictions.coord_x_um = [900; 800; 700];
predictions.coord_y_um = predictions.coord_x_um;
predictions.coord_z_um = predictions.coord_x_um;
normalized = Methods.TransformerAutoId.normalizeInputPredictions(predictions, 3);
assert(isequal(normalized.neuron_idx, [3; 1; 2]));
assert(normalized.confidence(3) == 0);
assert(isequal(Methods.TransformerAutoId.normalizeInputPredictions(normalized, 3), normalized));
neurons = Neurons.Image([], 'Head');
for i = 1:3
    neuron = Neurons.Neuron();
    neuron.position = [i i i];
    neuron.annotation = 'Manual';
    neurons.neurons(i) = neuron;
end
app = struct('image_neurons', neurons);
[indices, stats] = Methods.TransformerAutoId.matchPredictionRows(app, normalized);
assert(isequal(indices, [3; 1; 2]) && strcmp(stats.strategy, 'index'));
applied = Methods.TransformerAutoId.applyPredictions(app, normalized);
assert(applied.matched == 3 && applied.assigned_neurons == 2);
assert(applied.unassigned_neurons == 1 && applied.failed_predictions == 1);
assert(strcmp(neurons.neurons(1).deterministic_id, 'AVAR'));
assert(isempty(neurons.neurons(2).deterministic_id));
assert(strcmp(neurons.neurons(3).deterministic_id, 'AVAL'));
assert(all(strcmp({neurons.neurons.annotation}, 'Manual')));
failed = normalized;
failed.predicted_class(:) = "FAILED";
failed.confidence(:) = 0;
applied = Methods.TransformerAutoId.applyPredictions(app, failed);
assert(applied.assigned_neurons == 0 && applied.unassigned_neurons == 3);
assert(all(cellfun(@isempty, {neurons.neurons.deterministic_id})));
assert(all(strcmp({neurons.neurons.annotation}, 'Manual')));
bad = predictions; bad.neuron_idx(2) = 2;
expect(@() Methods.TransformerAutoId.normalizeInputPredictions(bad, 3));
expect(@() Methods.TransformerAutoId.normalizeInputPredictions(predictions(1:2,:), 3));
assert(strlength(Methods.TransformerAutoId.resolveNWBPath(struct(), "")) == 0);
fprintf('TRANSFORMER_CURRENT_INPUT_INDICES=PASS\n');
end

function expect(callback)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, 'Methods:TransformerAutoId:InputIndices'), ME.message);
    return
end
error('test:MissingError', 'Expected incomplete/duplicate input indices to fail.');
end
