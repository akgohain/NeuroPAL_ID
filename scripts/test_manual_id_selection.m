function test_manual_id_selection(app)
% Exercise manual IDs with saved predictions and an empty prediction list.
assert(~isempty(app.image_neurons.neurons));
folder = tempname; mkdir(folder);
neurons = app.image_neurons;
id_file = app.id_file;
save(fullfile(folder, 'neurons.mat'), 'neurons');
copy = load(fullfile(folder, 'neurons.mat'), 'neurons');
Program.Handlers.neurons.unselect_neuron(false);
app.image_neurons = copy.neurons;
app.selected_neuron = [];
app.id_file = fullfile(folder, 'test_ID.mat');
cleanup = onCleanup(@() restore_neurons(app, neurons, id_file, folder));

unlabelled = find(arrayfun(@(n) isempty(n.annotation) && ...
    ~isempty(n.deterministic_id) && ~isempty(n.rank), app.image_neurons.neurons));
assert(numel(unlabelled) >= 3, 'Use an example with saved auto-ID predictions.');
first = unlabelled(1); second = unlabelled(2);
app.refreshAutoIDList();
assert(~isempty(app.UserNeuronIDsListBox.Items));
click_neuron(app, first);
assert(app.UserNeuronIDsListBox.Value == app.image_neurons.neurons(first).rank);

% Manual selection must also work before the prediction list is populated.
app.UserNeuronIDsListBox.Items = {};
app.UserNeuronIDsListBox.ItemsData = [];
click_neuron(app, second);
assert(isempty(app.UserNeuronIDsListBox.Value));
assert(strcmp(app.UserIDButton.Enable, 'on'));

% A missing prediction must not shift the ranks of the remaining rows.
app.image_neurons.neurons(first).probabilistic_ids = {};
app.image_neurons.neurons(first).probabilistic_probs = [];
app.refreshAutoIDList();
assert(~ismember(app.image_neurons.neurons(first).rank, app.UserNeuronIDsListBox.ItemsData));
assert(ismember(app.image_neurons.neurons(second).rank, app.UserNeuronIDsListBox.ItemsData));
app.UserNeuronIDsListBox.Value = app.image_neurons.neurons(second).rank;
Program.Handlers.neurons.unselect_neuron(false);
callback = app.UserNeuronIDsListBox.ValueChangedFcn;
callback(app.UserNeuronIDsListBox, []);
assert(app.selected_neuron == second);

% Save through the edit callback and continue to another unlabelled neuron.
names = {'AVAR', 'RIMR'};
for i = 1:2
    assert(isempty(app.image_neurons.find_user_id_neuron(names{i})));
    click_neuron(app, unlabelled(i));
    app.IDEditField.Tag = '';
    callback = app.IDEditField.ValueChangingFcn;
    callback(app.IDEditField, struct('Value', [names{i} ' ']));
    assert(strcmp(app.image_neurons.neurons(unlabelled(i)).annotation, names{i}));
    assert(~app.is_saving_ID && ~isempty(app.selected_neuron));
    saved = load(app.id_file, 'neurons');
    assert(strcmp(saved.neurons.neurons(unlabelled(i)).annotation, names{i}));
end

% Opening a detection-only image must clear the previous predictions.
for i = 1:numel(app.image_neurons.neurons)
    app.image_neurons.neurons(i).rank = [];
    app.image_neurons.neurons(i).deterministic_id = [];
    app.image_neurons.neurons(i).probabilistic_ids = {};
    app.image_neurons.neurons(i).probabilistic_probs = [];
end
app.refreshAutoIDList();
assert(isempty(app.UserNeuronIDsListBox.Items));
click_neuron(app, unlabelled(3));
assert(strcmp(app.UserIDButton.Enable, 'on'));
fprintf('MANUAL_ID_SELECTION=PASS\n');
end

function click_neuron(app, index)
Program.Handlers.neurons.unselect_neuron(false);
position = app.image_neurons.neurons(index).position;
z = round(position(3));
if app.image_prefs.is_Z_flip, z = size(app.image_data, 3) - z + 1; end
app.ZSlider.Value = z;
app.mouse_clicked.click = false;
app.NeuronClicked([], struct('IntersectionPoint', [position(2), position(1), 0], 'Button', 1));
assert(app.selected_neuron == index);
end

function restore_neurons(app, neurons, id_file, folder)
app.image_neurons = neurons;
app.id_file = id_file;
app.selected_neuron = [];
app.refreshAutoIDList();
Program.Routines.ID.hot_neuron_reset();
Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
rmdir(folder, 's');
end
