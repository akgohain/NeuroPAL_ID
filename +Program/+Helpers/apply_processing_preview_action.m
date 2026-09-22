function applied = apply_processing_preview_action(app, actions)
% Apply one or more processing actions to the shared in-memory colormap volume.

Program.HeavyJob.assertIdle();
if nargin < 1 || isempty(app)
    app = Program.app;
end

applied = false;
if ~strcmpi(char(string(app.VolumeDropDown.Value)), 'Colormap')
    return
end

actions = cellstr(lower(string(actions)));
actions = actions(~cellfun('isempty', actions));
if isempty(actions)
    return
end
pending = fieldnames(app.flags)';
actions = [setdiff(pending, actions, 'stable'), actions];
supported = {'zscore','histmatch','crop','hori','vert','mirrorz','rotate','cc','acc','ds','window','debleed'};
if any(~ismember(actions, supported))
    error('NeuroPAL:ProcessingAction', 'Unknown image-processing action.');
end

context = Program.Helpers.processing_colormap_context(app);
current_volume = context.volume;
if isempty(current_volume)
    if isfield(context, 'is_lazy') && context.is_lazy
        applied = local_apply_lazy_actions(app, context, actions);
    end
    return
end

source_dims = size(current_volume);
if numel(source_dims) < 4
    source_dims(end+1:4) = 1;
end

job = Program.HeavyJob.acquire('Image processing');
job_cleanup = onCleanup(@() delete(job));
Program.ProcessingSession.checkpointPixels(app);
neurons = Program.ProcessingSession.copyNeurons(app.image_neurons);
for n = 1:numel(actions)
    action = actions{n};
    dims = size(current_volume); dims(end+1:4) = 1;
    current_volume = Methods.ChunkyMethods.apply_vol(app, action, current_volume);
    output_dims = size(current_volume); output_dims(end+1:4) = 1;
    neurons = Program.Helpers.transform_processing_neurons(app, neurons, action, dims, output_dims);
end

app.image_data = current_volume;
Program.Helpers.update_processing_image_scale(app, actions, source_dims);
app.image_neurons = neurons;
app.selected_neuron = [];
if ~isempty(neurons), neurons.scale = app.image_um_scale; end
Program.ProcessingSession.stageIDs(app);
for n = 1:numel(actions)
    if isfield(app.flags, actions{n}), app.flags = rmfield(app.flags, actions{n}); end
end
app.image_data_zscored = [];
setappdata(app.CELL_ID, 'proc_runtime_dirty', true);

Program.GUIHandling.clear_processing_preview_cache(app);

render_dims = size(app.image_data);
render_dims(end+1:4) = 1;
Program.GUIHandling.set_gui_limits(app, 'soft', [render_dims(1:4) 1]);

current_z = min(max(round(app.proc_zSlider.Value), 1), render_dims(3));
Program.Helpers.configure_main_zslider(app, render_dims(3), current_z);
app.ZSlider.Value = current_z;
if isprop(app, 'ZSliderS') && isvalid(app.ZSliderS)
    app.ZSliderS.Value = current_z;
end

if isgraphics(app.XY)
    app.XY.XLim = [0, render_dims(2)];
    app.XY.YLim = [0, render_dims(1)];
end

if any(strcmp(actions, 'window'))
    Program.GUIHandling.set_thresholds(app, 255);
end
Program.Helpers.sync_main_display_from_processing(app, false);
Program.ProcessingSession.refreshColors(app);
app.refreshAutoIDList();
Program.Routines.ID.hot_neuron_reset();
Program.Routines.Processing.render();
Program.Routines.ID.render();

applied = true;
end

function applied = local_apply_lazy_actions(app, context, actions)
applied = false;

unsupported = intersect(actions, {'ds'});
if ~isempty(unsupported)
    uialert(app.CELL_ID, ...
        sprintf('The %s action is not yet chunk-safe for lazy colormap volumes. Crop/rotate/flip/channel-window actions can be streamed without full materialization.', ...
        strjoin(unsupported, ', ')), ...
        'Chunked Processing Limitation', 'Icon', 'warning');
        return
end

non_slice_agnostic = local_non_slice_agnostic_actions(actions);
if ~isempty(non_slice_agnostic)
    uialert(app.CELL_ID, ...
        sprintf('The %s action requires full-volume processing and is not safe for slice-wise lazy execution. Apply on a non-lazy colormap volume instead.', ...
        strjoin(non_slice_agnostic, ', ')), ...
        'Chunked Processing Limitation', 'Icon', 'warning');
    return
end

if ~isa(context.reader, 'matlab.io.MatFile') || strlength(string(context.path)) == 0
    return
end

dims = context.dims;
if numel(dims) < 4 || any(dims(1:4) <= 0)
    return
end

target_path = local_processed_mat_path(context.path);
source = context.reader;
metadata = local_read_metadata(source, app, actions);
updated_scale = Program.Helpers.update_processing_image_scale(app, actions, dims, false);
if ~isfield(metadata, 'info') || ~isstruct(metadata.info)
    metadata.info = struct();
end
metadata.info.scale = updated_scale;
state = local_processing_state(app, actions, dims(4));
neurons = Program.ProcessingSession.copyNeurons(app.image_neurons);
current_dims = dims;
for n = 1:numel(actions)
    next_dims = Methods.ChunkyMethods.calc_pp_size(app, actions{n}, current_dims);
    neurons = Program.Helpers.transform_processing_neurons(app, neurons, actions{n}, current_dims, next_dims);
    current_dims = next_dims;
end
if ~isempty(neurons), neurons.scale = updated_scale; end

job = Program.HeavyJob.acquire('Image processing');
job_cleanup = onCleanup(@() delete(job));
Program.ProcessingSession.checkpointPixels(app);
d = uiprogressdlg(app.CELL_ID, ...
    'Title', 'NeuroPAL ID', ...
    'Message', 'Applying chunked colormap processing...', ...
    'Indeterminate', 'off', 'Cancelable', 'on');
cleanup = onCleanup(@() local_close_progress(d));

source_z = 1:dims(3);
if any(strcmpi(actions, 'mirrorz'))
    source_z = fliplr(source_z);
end
slice_actions = local_slice_actions(actions);
try
    result = DataHandling.Helpers.process_mat_transaction( ...
        context.path, target_path, metadata, ...
        @(slice) local_apply_actions_to_slice(app, slice, slice_actions), ...
        source_z, d, 'CheckFcn', @() local_check_processing_state(app, actions, dims(4), state));
catch ME
    if strcmp(ME.identifier, 'DataHandling:Processing:Cancelled')
        return
    end
    rethrow(ME);
end
target_path = result.path;
out_dims = result.dims;

app.image_file = target_path;
app.proc_image = matfile(target_path);
app.image_data = [];
app.image_data_zscored = [];
app.image_neurons = neurons;
app.selected_neuron = [];
Program.ProcessingSession.stageIDs(app);
app.image_prefs = metadata.prefs;
app.image_um_scale = updated_scale;
if isstruct(app.image_info)
    app.image_info.scale = updated_scale;
end
for n = 1:numel(actions)
    if isfield(app.flags, actions{n})
        app.flags = rmfield(app.flags, actions{n});
    end
end
setappdata(app.CELL_ID, 'proc_runtime_dirty', true);

Program.GUIHandling.clear_processing_preview_cache(app);
Program.GUIHandling.set_gui_limits(app, 'soft', [out_dims 1]);
Program.GUIHandling.set_thresholds(app, Program.Helpers.processing_colormap_max(app));
app.refreshAutoIDList();
Program.Routines.ID.hot_neuron_reset();
Program.Routines.Processing.render();
applied = true;
end

function metadata = local_read_metadata(source, app, ~)
metadata = struct();
vars = {'version', 'info', 'prefs', 'worm'};
for i = 1:numel(vars)
    name = vars{i};
    try
        metadata.(name) = source.(name);
    catch
    end
end

if ~isfield(metadata, 'prefs') || ~isstruct(metadata.prefs)
    metadata.prefs = app.image_prefs;
end
end

function slice = local_apply_actions_to_slice(app, slice, actions)
for n = 1:numel(actions)
    slice = Methods.ChunkyMethods.apply_slice(app, actions{n}, slice);
end
end

function actions = local_slice_actions(actions)
actions = actions(~strcmpi(actions, 'mirrorz'));
end

function path = local_processed_mat_path(source_path)
[folder, name, ~] = fileparts(char(source_path));
name = regexprep(name, '(_processed(?:_\d{3,})?)+$', '');
path = fullfile(folder, [name '_processed.mat']);
index = 1;
while isfile(path)
    path = fullfile(folder, sprintf('%s_processed_%03d.mat', name, index));
    index = index + 1;
end
end

function actions = local_non_slice_agnostic_actions(actions)
safe_actions = {'crop', 'hori', 'vert', 'mirrorz', 'rotate', 'cc', 'acc', 'window'};
unsafe = setdiff(actions, safe_actions);
unsafe = setdiff(unsafe, {'ds'});
actions = sort(unique(unsafe));
end

function state = local_processing_state(app, actions, n_channels)
state = struct('path', char(string(app.image_file)), ...
    'mode', char(string(app.VolumeDropDown.Value)), ...
    'scale', app.image_um_scale, 'angle', [], 'crop', [], ...
    'normalization', [], 'windows', []);
if any(strcmp(actions, 'rotate'))
    state.angle = app.proc_rot_spinner.Value;
end
if any(strcmp(actions, 'crop'))
    state.crop = app.rotation_stack.cache.Colormap;
end
if any(strcmp(actions, 'zscore'))
    state.normalization = Methods.ChunkyMethods.proc_normalize_percentiles(app);
end
if any(strcmp(actions, 'window'))
    state.windows = Methods.ChunkyMethods.proc_window_settings(app, n_channels);
end
end

function local_check_processing_state(app, actions, n_channels, expected)
if ~isempty(app.image_data) || ...
        ~isequaln(expected, local_processing_state(app, actions, n_channels))
    error('DataHandling:Processing:StateChanged', ...
        'The image or processing settings changed during processing. No output was published.');
end
end

function local_close_progress(d)
try
    if ~isempty(d) && isvalid(d)
        close(d);
    end
catch
end
end
