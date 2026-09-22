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
staging = tempname(folder); mkdir(staging);
cleanup = onCleanup(@() cleanup_staging(staging));
image_temp = fullfile(staging, 'image.mat');
id_temp = fullfile(staging, 'neurons.mat');
copyfile(context.path, image_temp);
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
neurons = app.image_neurons;
version = Program.ProgramInfo.version;
mp_params = app.mp_params;
if ~isempty(neurons), mp_params.k = numel(neurons.neurons); end
save(id_temp, 'neurons', 'version', 'mp_params');

% Retain the previous pair until both replacements have succeeded.
image_backup = fullfile(staging, 'previous_image.mat');
id_backup = fullfile(staging, 'previous_ID.mat');
image_moved = false; id_moved = false; id_published = false;
try
    checked_move(context.path, image_backup); image_moved = true;
    if isfile(id_file), checked_move(id_file, id_backup); id_moved = true; end
    checked_move(image_temp, context.path);
    checked_move(id_temp, id_file); id_published = true;
catch ME
    recovery_errors = {};
    try
        if image_moved, checked_move(image_backup, context.path); end
    catch recovery
        recovery_errors{end+1} = recovery.message;
    end
    try
        if id_moved
            checked_move(id_backup, id_file);
        elseif id_published && isfile(id_file)
            delete(id_file);
        end
    catch recovery
        recovery_errors{end+1} = recovery.message;
    end
    if ~isempty(recovery_errors)
        % Never delete the remaining backup if the filesystem also refuses recovery.
        error('NeuroPAL:ProcessingRecovery', ...
            'Save failed: %s. Recovery files remain in %s. %s', ...
            ME.message, staging, strjoin(recovery_errors, ' '));
    end
    rethrow(ME);
end
if isfile(image_backup), delete(image_backup); end
if isfile(id_backup), delete(id_backup); end
app.id_file = id_file;
app.proc_image = matfile(context.path);
if isappdata(app.CELL_ID, 'proc_runtime_dirty'), rmappdata(app.CELL_ID, 'proc_runtime_dirty'); end
Program.GUIHandling.clear_processing_preview_cache(app);
saved = true;
end

function cleanup_staging(folder)
if ~isfile(fullfile(folder, 'previous_image.mat')) && ~isfile(fullfile(folder, 'previous_ID.mat'))
    Program.ProcessingSession.removeFolder(folder);
end
end

function checked_move(source, target)
[ok, message] = movefile(source, target, 'f');
if ~ok, error('NeuroPAL:ProcessingSave', '%s', message); end
end
