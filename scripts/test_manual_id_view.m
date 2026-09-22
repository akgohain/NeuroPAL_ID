function test_manual_id_view(app)
% Exercise the package-to-app calls used while reopening an annotated image.
assert(~isempty(app.image_data) && ~isempty(app.image_neurons));
nodes = app.GanglionTree.SelectedNodes;
labels = app.show_labels;
cleanup = onCleanup(@() restore_view(app, nodes, labels));
positions = app.image_neurons.get_positions();
annotations = app.image_neurons.get_annotations();
head = app.GanglionTree.Children(strcmp({app.GanglionTree.Children.Text}, 'Head'));
assert(~isempty(head));
for node = [head; head.Children(1)]'
    app.GanglionTree.SelectedNodes = node;
    expected = app.ganglionNeurons(node);
    assert(~isempty(expected));
    Program.Routines.ID.hot_neuron_reset();
    assert(~isempty(app.IDdNeuronsListBox.Items) || ~isempty(app.UnIDdNeuronsListBox.Items));
end
app.show_labels = true;
Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
assert(isequal(app.image_neurons.get_positions(), positions));
assert(isequal(app.image_neurons.get_annotations(), annotations));

try
    fail_save(app);
catch ME
    assert(strcmp(ME.identifier, 'NeuroPAL:TestSaveFailure'));
end
assert(~app.is_saving_ID);
fprintf('MANUAL_ID_VIEW=PASS\n');

end

function fail_save(app)
app.is_saving_ID = true;
guard = onCleanup(@() Program.Handlers.neurons.finish_id_save(app));
error('NeuroPAL:TestSaveFailure', 'Injected save failure.');
end

function restore_view(app, nodes, labels)
app.GanglionTree.SelectedNodes = nodes;
app.show_labels = labels;
Program.Routines.ID.hot_neuron_reset();
Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
end
