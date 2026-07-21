function run_neuropal_id_request(request_path, output_csv, ~)
%RUN_NEUROPAL_ID_REQUEST Deterministic test double for the CRF bundle API.

request = load(request_path, 'neuron_idx');
n = numel(request.neuron_idx);
predicted_class = repmat("AVA", n, 1);
confidence = linspace(0.9, 0.7, n)';
predictions = table(request.neuron_idx, predicted_class, confidence, ...
    'VariableNames', {'neuron_idx', 'predicted_class', 'confidence'});
writetable(predictions, output_csv);
end
