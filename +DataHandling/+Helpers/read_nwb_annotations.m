function [neurons, parameters] = read_nwb_annotations(file, scale)
%READ_NWB_ANNOTATIONS Restore annotations saved by NeuroPAL ID.

neurons = [];
parameters = [];
base = '/processing/NeuronAnnotations/';
try
    h5info(file, [base 'NeuronAnnotations']);
catch
    return
end

annotations = [base 'NeuronAnnotations/'];
properties = [base 'NeuronProperties/'];
positions = h5read(file, [properties 'positions']);
format2 = contains(string(h5readatt(file, [base 'NeuronProperties'], 'description')), '(format 2)');
if format2, positions = positions'; end
names = cellstr(string(h5read(file, [annotations 'user_annotation'])));
count = numel(names);
assert(isequal(size(positions), [count 3]), ...
    'DataHandling:NWBExport:Annotations', 'Invalid annotation position dimensions.');
neurons = Neurons.Image([], 'scale', scale);
values = struct();
fields = {'colors', 'color_readouts', 'baselines', 'covariances', 'aligned_xyzRGB'};
for index = 1:numel(fields)
    values.(fields{index}) = h5read(file, [properties fields{index}]);
    if format2, values.(fields{index}) = values.(fields{index})'; end
end
confidence = h5read(file, [annotations 'annotation_confidence']);
enabled = h5read(file, [annotations 'is_annotation_on']);
emphasis = h5read(file, [annotations 'is_emphasized']);
if iscell(emphasis), emphasis = strcmpi(string(emphasis), 'TRUE'); end
deterministic = cellstr(string(h5read(file, [annotations 'deterministic_id'])));
candidates = cellstr(string(h5read(file, [annotations 'probabilistic_ids'])));
probabilities = h5read(file, [annotations 'probabilistic_probs']);
if format2, probabilities = probabilities'; end
ranks = h5read(file, [annotations 'rank']);
for index = 1:count
    neuron = Neurons.Neuron();
    neuron.position = positions(index, :);
    neuron.color = values.colors(index, :);
    neuron.color_readout = values.color_readouts(index, :);
    neuron.baseline = values.baselines(index, :);
    neuron.covariance = reshape(values.covariances(index, :), 3, 3);
    neuron.aligned_xyzRGB = values.aligned_xyzRGB(index, :);
    neuron.annotation = names{index};
    neuron.annotation_confidence = confidence(index);
    neuron.is_annotation_on = enabled(index);
    neuron.is_emphasized = logical(emphasis(index));
    neuron.deterministic_id = deterministic{index};
    if ~isempty(candidates{index})
        neuron.probabilistic_ids = strsplit(candidates{index}, '|');
        width = numel(neuron.probabilistic_ids);
        if width > size(probabilities, 2)
            error('DataHandling:NWBExport:Annotations', ...
                'The NWB contains fewer probabilities than candidate identities.');
        end
        neuron.probabilistic_probs = probabilities(index, 1:width);
    end
    neuron.rank = ranks(index);
    neurons.neurons(end+1) = neuron;
end

DataHandling.Helpers.NWBIdentityExchange.restore(file, neurons);

has_atlas = true;
try
    h5info(file, '/processing/NeuronAnnotations/AtlasVersion');
catch
    has_atlas = false;
end
if has_atlas
    atlas = h5read(file, '/processing/NeuronAnnotations/AtlasVersion/version');
    if iscell(atlas), atlas = atlas{1}; end
    neurons.atlas_version = atlas;
end

base = '/processing/DetectionParameters/DetectionParameters/';
try
    h5info(file, base);
catch
    return
end
names = cellstr(string(h5read(file, [base 'parameter_name'])));
values = cellstr(string(h5read(file, [base 'parameter_value'])));
parameters = struct();
for index = 1:numel(names)
    if ~isvarname(names{index}), continue; end
    try
        parameters.(names{index}) = jsondecode(values{index});
        continue
    catch
    end
    text = regexprep(values{index}, '[\[\],;]', ' ');
    value = sscanf(text, '%f').';
    if ~isempty(value) || isempty(strtrim(values{index}))
        parameters.(names{index}) = value;
    end
end
end
