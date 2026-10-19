function test_manual_id_selection(app)
% Exercise selection with model predictions while requiring an explicit save.
assert(numel(app.image_neurons.neurons)>=3);
folder = tempname; mkdir(folder);
neurons = app.image_neurons;
id_file = app.id_file;
saved=struct('selected',app.selected_neuron,'auto',app.AutoNameCheckBox.Value, ...
    'state',Program.GUI.ManualIDController.state(app), ...
    'after',getappdata(app.CELL_ID,'manual_id_after_commit'), ...
    'snapshot',getappdata(app.CELL_ID,'manual_id_file_snapshot'));
copy=Program.GUI.ManualIDService.copyImage(neurons);
copy.annotation_store=struct();
for i=1:numel(copy.neurons)
    copy.neurons(i).annotation=''; copy.neurons(i).annotation_confidence=-1;
    copy.neurons(i).annotation_id=''; copy.neurons(i).annotation_record=struct();
    copy.neurons(i).rank=i; copy.neurons(i).deterministic_id='AVA';
    copy.neurons(i).probabilistic_ids={'AVA','RIM'};
    copy.neurons(i).probabilistic_probs=[.8 .2];
end
Program.Handlers.neurons.unselect_neuron(false);
app.image_neurons = copy;
app.selected_neuron = [];
app.id_file = fullfile(folder, 'test_ID.mat');
app.AutoNameCheckBox.Value=false;
setappdata(app.CELL_ID,'manual_id_after_commit',@(~,~,~) []);
Program.GUI.ManualIDController.invalidate(app);
cleanup = onCleanup(@() restore_neurons(app, neurons, id_file, folder,saved));

unlabelled = find(arrayfun(@(n) isempty(n.annotation) && ...
    ~isempty(n.deterministic_id) && ~isempty(n.rank), app.image_neurons.neurons));
assert(numel(unlabelled) >= 3);
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

% Whitespace and native blur update the draft without persisting it.
names = {'AVAR', 'RIMR'};
for i = 1:2
    assert(isempty(app.image_neurons.find_user_id_neuron(names{i})));
    click_neuron(app, unlabelled(i));
    before=Annotations.Store.fingerprint(app.id_file);
    evidence=app.image_neurons.annotation_store.evidence;
    ui=Program.GUI.ManualIDController.ui(app);
    ui.input.ValueChangingFcn(ui.input, struct('Value', [names{i} ' ']));
    ui.input.Value=[names{i} ' ']; ui.input.ValueChangedFcn(ui.input,[]);
    assert(isempty(app.image_neurons.neurons(unlabelled(i)).annotation));
    assert(isequaln(before,Annotations.Store.fingerprint(app.id_file)));
    Program.GUI.ManualIDController.beginMouseGesture(app,'normal');
    result=Program.GUI.ManualIDInput.commit(app,[],unlabelled(i));
    assert(result.changed);
    assert(strcmp(app.image_neurons.neurons(unlabelled(i)).annotation, names{i}));
    assert(~app.is_saving_ID && isequal(app.selected_neuron,unlabelled(i)));
    assert(isequaln(evidence,app.image_neurons.annotation_store.evidence));
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

function restore_neurons(app, neurons, id_file, folder,saved)
Program.GUI.ManualIDController.close(app);
app.image_neurons = neurons;
app.id_file = id_file;
app.selected_neuron = saved.selected;
app.AutoNameCheckBox.Value=saved.auto;
setappdata(app.CELL_ID,'manual_id_after_commit',saved.after);
setappdata(app.CELL_ID,'manual_id_file_snapshot',saved.snapshot);
Program.GUI.ManualIDController.put(app,saved.state);
app.refreshAutoIDList();
Program.Routines.ID.hot_neuron_reset();
Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
rmdir(folder, 's');
end
