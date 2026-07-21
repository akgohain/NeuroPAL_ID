function run_neuropal_id_request(request_path, output_csv, bundle_path)
%RUN_NEUROPAL_ID_REQUEST Bundle adapter contract for CRF Cell-ID 2.0.
%
% Copy this file to run_neuropal_id_request.m inside the completed bundle.
% Load request_path, construct the selected CRF-ID 2.0 atlas/unary inputs
% using assets under bundle_path, run inference, and write exactly one row
% per request neuron with these required columns:
%
%   neuron_idx, predicted_class, confidence
%
% Optional top5_classes and top5_probs columns contain comma-separated
% ranked values and are imported by the shared auto-ID transaction layer.

request = load(request_path); %#ok<NASGU>
error('NeuroPAL:CRFID2:TemplateOnly', ...
    ['This is the adapter template, not a runnable CRF-ID 2.0 bundle. ' ...
     'Install the selected atlas and unary assets under %s.'], bundle_path);

% Example output shape only:
% predictions = table((1:n)', predicted_class, confidence, ...
%     'VariableNames', {'neuron_idx','predicted_class','confidence'});
% writetable(predictions, output_csv);
end
