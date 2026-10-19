function saved = write_processing_colormap_to_file(app)
% Save pixels, metadata, and neuron annotations as one recoverable operation.
if nargin < 1 || isempty(app), app = Program.app; end
saved = false;
if ~strcmp(app.VolumeDropDown.Value, 'Colormap'), return; end
context = Program.Helpers.processing_colormap_context(app);
if isempty(context.path) || ~isfile(context.path)
    error('NeuroPAL:ProcessingSave', 'The image backing file is no longer available.');
end
Program.Helpers.sync_main_display_from_processing(app, false);
[folder, name] = fileparts(context.path);
id_file = fullfile(folder, [name '_ID.mat']);
snapshot = Program.ProcessingSession.get(app);
if ~isempty(snapshot) && strcmp(snapshot.path, context.path) && ~isempty(snapshot.id_file)
    id_file = snapshot.id_file;
end
if isfolder(id_file) || strcmp(id_file, context.path)
    error('NeuroPAL:ProcessingSave', 'The neuron ID destination is not a valid file: %s', id_file);
end
expected_image = Annotations.Store.fingerprint(context.path);
payload = struct();
if isfile(id_file)
    [payload, expected_id, issues] = Annotations.Store.loadValidated(id_file);
    unsafe = ~strcmp({issues.code}, 'evidence-unavailable');
    if any(unsafe)
        error('Annotations:ReadOnly', 'Resolve the existing ID recovery issue before saving image changes: %s', ...
            strjoin({issues(unsafe).message}, ' '));
    end
else
    expected_id = Annotations.Store.fingerprint(id_file);
    if isfile([id_file '.annotations.lineage.json']) || isfile([id_file '.processing.pending.json'])
        error('Annotations:ReadOnly', 'ID recovery metadata exists without a usable ID file. Reconcile it before saving image changes.');
    end
end
if ~isempty(snapshot) && isfield(snapshot, 'id_fingerprint') && strcmp(snapshot.id_file, id_file)
    baseline = snapshot.id_fingerprint;
    if baseline.exists ~= expected_id.exists || ~strcmp(baseline.sha256, expected_id.sha256) || ...
            baseline.generation ~= expected_id.generation
        error('Annotations:StaleSave', 'The original ID file changed after this processing session began. Reload or reconcile that save before publishing image changes.');
    end
end
if ~isempty(snapshot) && isa(snapshot.neurons, 'Neurons.Image') && ...
        isfield(snapshot.neurons.annotation_store, 'generation') && isfield(payload, 'annotation_store')
    baseline = snapshot.neurons.annotation_store;
    if baseline.generation ~= payload.annotation_store.generation || ...
            ~strcmp(baseline.source_id, payload.annotation_store.source_id)
        error('Annotations:StaleSave', 'The original identities changed after this processing preview began. Reload or reconcile that save before publishing the image changes.');
    end
end
if ~isempty(app.image_neurons) && ~isempty(app.image_neurons.annotation_read_only_reason)
    error('Annotations:ReadOnly', '%s', app.image_neurons.annotation_read_only_reason);
end
if isempty(app.image_neurons), app.image_neurons = Neurons.Image([]); end
if isempty(fieldnames(app.image_neurons.annotation_store)) && isfield(payload, 'annotation_store')
    app.image_neurons.annotation_store = payload.annotation_store;
end
store = Program.GUI.ManualIDService.ensure(app);
geometry = Program.GUI.ManualIDService.digest(struct('positions', app.image_neurons.get_positions(), ...
    'scale', app.image_um_scale));
for i = 1:numel(app.image_neurons.neurons)
    index = strcmp({store.owners.owner_id}, app.image_neurons.neurons(i).annotation_id);
    if nnz(index) ~= 1
        error('Annotations:Ownership', 'The processing preview has no stable annotation owner for a neuron. Reopen or reconcile its identity source.');
    end
    store.owners(index).geometry_revision = geometry;
end
store.context.geometry_revision = geometry;
store.context.sex = app.worm.sex;
payload.annotation_store = store;
payload.neurons = Program.GUI.ManualIDService.copyImage(app.image_neurons);
Program.GUI.ManualIDService.apply(payload.neurons, store);
payload.version = Program.ProgramInfo.version;
payload.mp_params = app.mp_params;
payload.mp_params.k = numel(app.image_neurons.neurons);
staging = tempname(folder); mkdir(staging);
cleanup = onCleanup(@() Program.ProcessingSession.removeFolder(staging));
image_temp = fullfile(staging, 'image.mat');
[ok, message] = copyfile(context.path, image_temp);
if ~ok, error('NeuroPAL:ProcessingSave', 'Cannot stage the image: %s', message); end
prefs = app.image_prefs;
info = app.image_info;
info.scale = app.image_um_scale;
if ~isempty(app.image_data)
    output = matfile(image_temp, 'Writable', true);
    output.data = app.image_data;
    output.info = info;
    output.prefs = prefs;
    clear output
else
    save(image_temp, 'prefs', 'info', '-append');
end
[payload, fingerprint] = Annotations.IDWriters.publishPair(context.path, image_temp, ...
    id_file, payload, expected_image, expected_id);
app.id_file = id_file;
Program.GUI.ManualIDService.apply(app.image_neurons, payload.annotation_store);
setappdata(app.CELL_ID, 'manual_id_file_snapshot', struct('key', ...
    Program.GUI.ManualIDService.fileKey(app), 'fingerprint', fingerprint));
app.proc_image = matfile(context.path);
if isappdata(app.CELL_ID, 'proc_runtime_dirty'), rmappdata(app.CELL_ID, 'proc_runtime_dirty'); end
Program.GUIHandling.clear_processing_preview_cache(app);
saved = true;
end
