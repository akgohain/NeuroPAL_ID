function files = test_nwb_annotation_roundtrip(folder)
%TEST_NWB_ANNOTATION_ROUNDTRIP Preserve identities and arrays in portable NWB tables.
if nargin < 1
    folder = tempname; mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder, 's'));
elseif ~isfolder(folder)
    mkdir(folder);
end
files = {};
app = Program.app;
previous = app.mp_params;
parameter_cleanup = onCleanup(@() restore(app, previous));
app.mp_params = struct('hnsz', [7 7 3], 'enabled', true, ...
    'backend', 'MoE', 'settings', struct('threshold', 0.5), 'optional', []);
for count = [1 3]
    neurons = Neurons.Image([], 'scale', [0.4 0.5 1.5]);
    neurons.atlas_version = 'roundtrip-test';
    for index = 1:count
        neuron = Neurons.Neuron();
        neuron.position = [2.25 4.5 index];
        neuron.color = [1 2 3 4] * index;
        neuron.color_readout = [-1 0 1 2] * index;
        neuron.baseline = [4 3 2 1];
        neuron.covariance = reshape(1:9, 3, 3) * index;
        neuron.aligned_xyzRGB = (1:6) + index;
        neuron.annotation = 'AVAL';
        neuron.annotation_confidence = 0.5;
        neuron.is_annotation_on = 0;
        neuron.is_emphasized = true;
        neuron.deterministic_id = 'AVAR';
        neuron.probabilistic_ids = cellstr("candidate" + string(1:10));
        neuron.probabilistic_probs = (1:10) / 55;
        neuron.rank = index;
        neurons.neurons(end+1) = neuron;
    end
    context = struct('neurons', struct('image_neurons', neurons));
    module = DataHandling.writeNWB.create_neuron_annotations(context);
    nwb = NwbFile('identifier', sprintf('annotation-%d', count), ...
        'session_description', 'Software validation fixture', ...
        'session_start_time', datetime('now', 'TimeZone', 'local'));
    nwb.processing.set('NeuronAnnotations', module);
    nwb.processing.set('DetectionParameters', DataHandling.writeNWB.create_detection_params(context));
    file = fullfile(folder, sprintf('annotations-%d.nwb', count));
    nwbExport(nwb, file);
    shape = h5info(file, '/processing/NeuronAnnotations/NeuronProperties/positions');
    assert(isequal(shape.Dataspace.Size, [3 count]));
    shape = h5info(file, '/processing/NeuronAnnotations/NeuronAnnotations/probabilistic_probs');
    assert(isequal(shape.Dataspace.Size, [10 count]));
    [loaded, parameters] = DataHandling.Helpers.read_nwb_annotations(file, [0.4 0.5 1.5]);
    assert(isequal(parameters.hnsz, [7 7 3]) && parameters.enabled);
    assert(strcmp(parameters.backend, 'MoE') && parameters.settings.threshold == 0.5);
    assert(isempty(parameters.optional) && parameters.k == count);
    assert(numel(loaded.neurons) == count);
    assert(strcmp(loaded.atlas_version, neurons.atlas_version));
    fields = {'position', 'color', 'color_readout', 'baseline', 'covariance', ...
        'aligned_xyzRGB', 'annotation', 'annotation_confidence', 'is_annotation_on', ...
        'is_emphasized', 'deterministic_id', 'probabilistic_ids', 'probabilistic_probs', 'rank'};
    for index = 1:count
        for field = fields
            expected = neurons.neurons(index).(field{1});
            actual = loaded.neurons(index).(field{1});
            assert(isequaln(actual, expected), field{1});
        end
    end
    files{end+1} = file;
end
fprintf('NWB_ANNOTATIONS_SINGLE_MULTIPLE_FULL_PROBABILITIES=PASS\n');
end
function restore(app, parameters)
app.mp_params = parameters;
end
