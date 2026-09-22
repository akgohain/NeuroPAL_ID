function test_neuron_csv_import(app)
%TEST_NEURON_CSV_IMPORT Reject invalid rows without partially adding neurons.
assert(contains(app.image_file, 'audit'), 'Use a disposable image fixture.');
folder = tempname; mkdir(folder);
original = app.image_neurons;
id_file = app.id_file;
cleanup = onCleanup(@() finish(app, original, id_file, folder));
file = fullfile(folder, 'centers.csv');
rows = table([0; 1], [0; 0], [2; 3], [10; 15], [20; 25], ...
    'VariableNames', {'TRACK_ID', 'Frame', 'Z', 'Y', 'X'});
count = numel(original.neurons);
bad = rows; bad.X(2) = NaN; writetable(bad, file);
expect(@() Program.Helpers.import_neuron_csv(app, file), 'Program:ImportNeurons:Coordinates');
assert(numel(app.image_neurons.neurons) == count);
bad = rows; bad.Z(2) = 0; writetable(bad, file);
expect(@() Program.Helpers.import_neuron_csv(app, file), 'Program:ImportNeurons:Coordinates');
bad = rows; bad.Frame(2) = 1; writetable(bad, file);
expect(@() Program.Helpers.import_neuron_csv(app, file), 'Program:ImportNeurons:Frames');
writetable(removevars(rows, 'Z'), file);
expect(@() Program.Helpers.import_neuron_csv(app, file), 'Program:ImportNeurons:Columns');
writetable(rows, file);
assert(Program.Helpers.import_neuron_csv(app, file) == 2);
assert(numel(app.image_neurons.neurons) == count+2);
assert(isequal(app.image_neurons.neurons(end).position, [15 25 3]));
saved = load(id_file, 'neurons');
assert(numel(saved.neurons.neurons) == count+2);
fprintf('CSV_IMPORT_VALIDATION_AND_SAVE=PASS\n');
end

function expect(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), ME.message);
    return
end
error('test:MissingError', 'Expected %s.', identifier);
end

function finish(app, original, id_file, folder)
app.image_neurons = original;
app.id_file = id_file;
app.selected_neuron = [];
Program.Handlers.neurons.save_id_file();
app.refreshAutoIDList();
Program.Routines.ID.hot_neuron_reset();
rmdir(folder, 's');
end
