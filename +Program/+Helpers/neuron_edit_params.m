function params = neuron_edit_params(params, scale)
%NEURON_EDIT_PARAMS Keep manual editing available after any detector or import.

if ~isstruct(params) || ~isscalar(params), params = struct(); end
scale = double(scale(:)');
if numel(scale) ~= 3 || any(~isfinite(scale) | scale <= 0)
    error('Program:NeuronEdit:Scale', 'Neuron editing requires three positive voxel spacings.');
end
if ~isfield(params, 'hnsz') || ~isnumeric(params.hnsz) || numel(params.hnsz) ~= 3 || ...
        any(~isfinite(params.hnsz(:)) | params.hnsz(:) < 0 | params.hnsz(:) ~= round(params.hnsz(:)))
    params.hnsz = round(round(3 ./ scale) / 2) * 2 + 1;
else
    params.hnsz = double(params.hnsz(:)');
end
if ~isfield(params, 'k'), params.k = 0; end
if ~isfield(params, 'exclusion_radius'), params.exclusion_radius = 1.5; end
if ~isfield(params, 'min_eig_thresh'), params.min_eig_thresh = 0.1; end
end
