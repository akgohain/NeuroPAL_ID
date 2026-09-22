function count = import_neuron_csv(app, file)
%IMPORT_NEURON_CSV Validate one frame of pixel centers before changing neurons.

Program.HeavyJob.assertIdle();
if isempty(app.image_data)
    error('Program:ImportNeurons:NoImage', 'Open an image before importing neuron centers.');
end
rows = readtable(file, 'VariableNamingRule', 'preserve');
names = upper(strtrim(string(rows.Properties.VariableNames)));
columns = zeros(1, 3);
axes = ["Y", "X", "Z"];
for axis = 1:3
    match = find(names == axes(axis));
    if numel(match) ~= 1
        error('Program:ImportNeurons:Columns', 'The CSV must contain X, Y, and Z pixel-coordinate columns.');
    end
    columns(axis) = match;
end
positions = rows{:, columns};
dimensions = size(app.image_data, 1:3);
if ~isnumeric(positions) || isempty(positions) || any(~isfinite(positions), 'all') || ...
        any(positions < 1 | positions > dimensions, 'all')
    error('Program:ImportNeurons:Coordinates', ...
        'Neuron centers must be finite, one-based pixel coordinates inside the loaded image.');
end
frame = find(names == "FRAME", 1);
if ~isempty(frame) && numel(unique(rows{:, frame})) > 1
    error('Program:ImportNeurons:Frames', 'Import a CSV containing one frame of neuron centers.');
end

replacement = Program.ProcessingSession.copyNeurons(app.image_neurons);
readout = Methods.ColorReadout(app.image_data, app.image_prefs.RGBW);
readout = readout.prepare();
for index = 1:size(positions, 1)
    replacement.add_neuron(readout, positions(index, :), app.mp_params.hnsz, app.image_um_scale);
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
