function applied = apply_processing_preview_action(app, actions)
% Apply one or more processing actions to the shared in-memory colormap volume.

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

for n = 1:numel(actions)
    action = actions{n};
    current_volume = Methods.ChunkyMethods.apply_vol(app, action, current_volume);
    if isfield(app.flags, action)
        app.flags = rmfield(app.flags, action);
    end
end

app.image_data = current_volume;
Program.Helpers.update_processing_image_scale(app, actions, source_dims);
app.image_data_zscored = [];
setappdata(app.CELL_ID, 'proc_runtime_dirty', true);

Program.GUIHandling.clear_processing_preview_cache(app);

render_dims = size(app.image_data);
if ndims(app.image_data) == 3
    render_dims = [render_dims 1];
end
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

max_val = max(255, double(max(app.image_data, [], 'all')));
Program.GUIHandling.set_thresholds(app, max_val);
Program.Helpers.sync_main_display_from_processing(app, false);
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
if exist(target_path, 'file') == 2
    delete(target_path);
end

source = context.reader;
metadata = local_read_metadata(source, app, actions);
updated_scale = Program.Helpers.update_processing_image_scale(app, actions, dims);
if ~isfield(metadata, 'info') || ~isstruct(metadata.info)
    metadata.info = struct();
end
metadata.info.scale = updated_scale;
save(target_path, '-struct', 'metadata', '-v7.3');
target = matfile(target_path, 'Writable', true);

d = uiprogressdlg(app.CELL_ID, ...
    'Title', 'NeuroPAL ID', ...
    'Message', 'Applying chunked colormap processing...', ...
    'Indeterminate', 'off');
cleanup = onCleanup(@() local_close_progress(d));

sample_source_z = local_lazy_source_z(actions, dims, 1);
slice_actions = local_slice_actions(actions);
sample = source.data(:, :, sample_source_z, :);
sample = local_apply_actions_to_slice(app, sample, slice_actions);
sample = local_ensure_4d(sample);
out_dims = [size(sample, 1), size(sample, 2), dims(3), size(sample, 4)];
target.data(out_dims(1), out_dims(2), out_dims(3), out_dims(4)) = cast(0, class(sample));
target.data(:, :, 1, :) = sample;

for z = 2:dims(3)
    d.Value = z / dims(3);
    d.Message = sprintf('Processing slice %d/%d...', z, dims(3));
    source_z = local_lazy_source_z(actions, dims, z);
    slice = source.data(:, :, source_z, :);
    slice = local_apply_actions_to_slice(app, slice, slice_actions);
    slice = local_ensure_4d(slice);
    target.data(:, :, z, :) = slice;
end

app.image_file = target_path;
app.proc_image = matfile(target_path);
app.image_data = [];
app.image_data_zscored = [];
app.image_prefs = metadata.prefs;
for n = 1:numel(actions)
    if isfield(app.flags, actions{n})
        app.flags = rmfield(app.flags, actions{n});
    end
end
if isappdata(app.CELL_ID, 'proc_runtime_dirty')
    rmappdata(app.CELL_ID, 'proc_runtime_dirty');
end

Program.GUIHandling.clear_processing_preview_cache(app);
Program.GUIHandling.set_gui_limits(app, 'soft', [out_dims 1]);
Program.GUIHandling.set_thresholds(app, Program.Helpers.processing_colormap_max(app));
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

function source_z = local_lazy_source_z(actions, dims, target_z)
if any(strcmpi(actions, 'mirrorz'))
    source_z = dims(3) - target_z + 1;
else
    source_z = target_z;
end
end

function actions = local_slice_actions(actions)
actions = actions(~strcmpi(actions, 'mirrorz'));
end

function array = local_ensure_4d(array)
dims = size(array);
if numel(dims) == 2
    array = reshape(array, dims(1), dims(2), 1, 1);
elseif numel(dims) == 3
    array = reshape(array, dims(1), dims(2), 1, dims(3));
end
end

function path = local_processed_mat_path(source_path)
[folder, name, ~] = fileparts(string(source_path));
while endsWith(name, '_processed')
    name = extractBefore(name, strlength(name) - 9);
end
path = fullfile(folder, [name '_processed.mat']);
end

function actions = local_non_slice_agnostic_actions(actions)
safe_actions = {'zscore', 'histmatch', 'crop', 'hori', 'vert', 'mirrorz', 'rotate', 'cc', 'acc', 'window'};
unsafe = setdiff(actions, safe_actions);
unsafe = setdiff(unsafe, {'ds'});
actions = sort(unique(unsafe));
end

function local_close_progress(d)
try
    if ~isempty(d) && isvalid(d)
        close(d);
    end
catch
end
end
