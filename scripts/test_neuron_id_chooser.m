function test_neuron_id_chooser(app)
%TEST_NEURON_ID_CHOOSER Keep individual atlas names available outside model ranks.
herm = Program.GUI.NeuronIDChooser.names('XX');
male = Program.GUI.NeuronIDChooser.names('XO');
assert(isequal(herm, Annotations.Catalog.names('XX')));
assert(isequal(male, Annotations.Catalog.names('XO')));
assert(numel(Program.GUI.NeuronIDChooser.names('Unknown')) == 395);
assert(isequal(Program.GUI.NeuronIDChooser.names(''), Annotations.Catalog.names('')));
assert(all(ismember({'IL1L', 'IL1R', 'CANL', 'CANR'}, herm)));
assert(all(ismember({'CEMDL', 'CEMDR', 'CEMVL', 'CEMVR'}, male)));

% Group suggestions must expose all individuals, without selecting a side.
groups = {'IL1', 'IL2', 'CEP', 'RMD', 'AS'};
counts = [6, 6, 4, 6, 11];
for i = 1:numel(groups)
    names = Program.GUI.NeuronIDChooser.matchingNames(herm, groups(i), 'Suggested classes', '');
    assert(numel(names) == counts(i));
end
names = Program.GUI.NeuronIDChooser.matchingNames(herm, "IL1", 'Suggested classes', ' il1l ');
assert(isequal(names, {'IL1L'}));
names = Program.GUI.NeuronIDChooser.matchingNames(herm, 'IL1', 'Suggested classes', '');
assert(numel(names) == 6);
names = Program.GUI.NeuronIDChooser.matchingNames(herm, {'IL1L'}, 'Suggested classes', '');
assert(isequal(names, {'IL1L'}));
assert(isempty(Program.GUI.NeuronIDChooser.matchingNames(herm, {'UNKNOWN'}, 'Suggested classes', '')));
assert(isempty(Program.GUI.NeuronIDChooser.matchingNames(herm, {}, 'Suggested classes', '')));
assert(isequal(Program.GUI.NeuronIDChooser.matchingNames(herm, {}, 'All neurons', ''), herm));
assert(isequal(Program.GUI.NeuronIDChooser.matchingNames(male, {'R1'}, 'Suggested classes', ''), ...
    {'R1AL'; 'R1AR'; 'R1BL'; 'R1BR'}));
assert(isequal(Program.GUI.NeuronIDChooser.matchingNames(herm, {'AQR'}, 'Suggested classes', ''), {'AQR'}));
assert(isequal(Program.GUI.NeuronIDChooser.matchingNames(male, {'CA'}, 'Suggested classes', ''), ...
    arrayfun(@(i) sprintf('CA%d', i), (1:9)', 'UniformOutput', false)));
assert(isequal(Program.GUI.NeuronIDChooser.matchingNames(herm, {}, 'All neurons', 'AS01'), {'AS1'}));
[~, model] = Annotations.Catalog.modelMembers('gat-20260601-v1', 'IL1');
mapping = struct('bundle_id', model.bundle_id, 'vocabulary_version', model.vocabulary_version);
assert(numel(Program.GUI.NeuronIDChooser.matchingNames(herm, {'IL1'}, 'Suggested classes', '', mapping)) == 6);
assert(isempty(Program.GUI.NeuronIDChooser.matchingNames(herm, {'CAN'}, 'Suggested classes', '', mapping)));
mapping.bundle_id = 'unknown-bundle';
assert(isempty(Program.GUI.NeuronIDChooser.matchingNames(herm, {'IL1'}, 'Suggested classes', '', mapping)));
mapping.bundle_id = model.bundle_id; mapping.vocabulary_version = 'other-vocabulary';
assert(isempty(Program.GUI.NeuronIDChooser.matchingNames(herm, {'IL1'}, 'Suggested classes', '', mapping)));

% Auto Name may fill an individual ID, never an unresolved class or artifact.
assert(strcmp(Program.GUI.NeuronIDChooser.individualName(' il1l ', 'XX'), 'IL1L'));
assert(strcmp(Program.GUI.NeuronIDChooser.individualName('ALA', 'XX'), 'ALA'));
assert(strcmp(Program.GUI.NeuronIDChooser.individualName('CEMDL', 'XO'), 'CEMDL'));
for name = {'IL1', 'AVA', 'ARTIFACT', 'NAN', '', 'CEMDL'}
    assert(isempty(Program.GUI.NeuronIDChooser.individualName(name{1}, 'XX')));
end

if nargin > 0
    % Filtering must also disable Use ID when no visible row remains.
    window = uifigure('Visible', 'off');
    cleanup = onCleanup(@() delete(window));
    list = uilistbox(window, 'Items', herm);
    use = uibutton(window);
    Program.GUI.NeuronIDChooser.filter(list, use, herm, {'IL1'}, 'Suggested classes', '');
    assert(numel(list.Items) == 6 && isempty(list.Value) && strcmp(use.Enable, 'off'));
    list.Value = {'IL1R'};
    Program.GUI.NeuronIDChooser.filter(list, use, herm, {'IL1'}, 'All neurons', 'IL1');
    assert(isequal(list.Value, {'IL1R'}) && strcmp(use.Enable, 'on'));
    Program.GUI.NeuronIDChooser.filter(list, use, herm, {'IL1'}, 'All neurons', 'not-a-neuron');
    assert(isempty(list.Items) && strcmp(use.Enable, 'off'));
    Program.GUI.NeuronIDChooser.filter(list, use, herm, {}, 'All neurons', 'CANL');
    assert(isempty(list.Value) && strcmp(use.Enable, 'off'));
    list.Value = {'CANL'};
    Program.GUI.NeuronIDChooser.filter(list, use, herm, {}, 'All neurons', 'CANL');
    assert(isequal(list.Value, {'CANL'}) && strcmp(use.Enable, 'on'));

    if ~isempty(app.image_neurons) && ~isempty(app.selected_neuron)
        index = app.selected_neuron; neuron = app.image_neurons.neurons(index);
        assert(Program.GUI.NeuronIDChooser.selectionMatches(app, index, app.image_file, neuron));
        assert(~Program.GUI.NeuronIDChooser.selectionMatches(app, index, [app.image_file '.other'], neuron));
        assert(~Program.GUI.NeuronIDChooser.selectionMatches(app, index, app.image_file, Neurons.Neuron()));
        count = numel(findall(groot, 'Type', 'figure'));
        annotations = app.image_neurons.get_annotations();
        Program.GUI.NeuronIDChooser.open(app);
        ui = Program.GUI.ManualIDController.ui(app);
        assert(numel(findall(groot, 'Type', 'figure')) == count);
        assert(strcmp(ui.panel.Visible, 'on'));
        assert(isempty(findall(groot, 'Tag', 'NeuronIDChooser')));
        assert(isequal(app.image_neurons.get_annotations(), annotations));
        Program.GUI.ManualIDController.close(app);
    end
end
fprintf('NEURON_ID_CHOOSER_FULL_ATLAS_GROUPS=PASS\n');
end
