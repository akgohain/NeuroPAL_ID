function count = import_neuron_nwb(app, file)
%IMPORT_NEURON_NWB Validate and append NWB annotations before saving the ID file.
Program.HeavyJob.assertIdle();
if isempty(app.image_data)
    error('Program:ImportNeurons:NoImage', 'Open an image before importing neuron centers.');
end
imported = DataHandling.Helpers.read_nwb_annotations(file, app.image_um_scale);
if isempty(imported)
    [positions, labels] = DataHandling.Helpers.read_nwb_centers(file);
else
    positions = imported.get_positions();
end
dimensions = size(app.image_data, 1:3);
if isempty(positions) || any(~isfinite(positions), 'all') || any(positions < 1 | positions > dimensions, 'all')
    error('Program:ImportNeurons:Coordinates', ...
        'NWB neuron centers lie outside the loaded image. Open the matching volume before importing.');
end
replacement = Program.ProcessingSession.copyNeurons(app.image_neurons);
if isempty(imported)
    readout = Methods.ColorReadout(app.image_data, app.image_prefs.RGBW);
    readout = readout.prepare();
    for index = 1:size(positions, 1)
        replacement.add_neuron(readout, positions(index, :), app.mp_params.hnsz, app.image_um_scale);
        name = upper(erase(labels{index}, ' '));
        if ~isempty(name) && app.neuron_info.isCell(name)
            [name, enabled] = app.neuron_info.stripOnOff(name);
            replacement.neurons(end).annotation = char(name);
            replacement.neurons(end).is_annotation_on = enabled;
            replacement.neurons(end).annotation_confidence = 1;
        end
    end
else
    replacement.neurons = [replacement.neurons imported.neurons];
end
previous = app.image_neurons;
app.image_neurons = replacement;
try
    Program.Handlers.neurons.save_id_file();
catch ME
    app.image_neurons = previous;
    rethrow(ME);
end
count = size(positions, 1);
app.selected_neuron = [];
Program.GUIHandling.gui_lock(app, 'enable', 'neuron_gui');
app.refreshAutoIDList();
Program.Routines.ID.hot_neuron_reset();
Program.Routines.ID.render();
end
