function update_zephir_video_tab(app)
%UPDATE_ZEPHIR_VIDEO_TAB Refresh workflow status and action enablement.

if nargin < 1 || isempty(app) || ~isvalid(app) || ...
        ~isprop(app, 'VideoTrackingTab') || isempty(app.VideoTrackingTab) || ...
        ~isvalid(app.VideoTrackingTab)
    return
end

[has_video, source_file, source_dir] = video_source(app);
[~, ~, annotations_file, worldlines_file, ...
    checkpoint_file, results_file] = artifact_paths(app, source_file, source_dir);

has_annotations_file = ~isempty(annotations_file) && isfile(annotations_file);
has_worldlines_file = ~isempty(worldlines_file) && isfile(worldlines_file);
has_checkpoint = ~isempty(checkpoint_file) && isfile(checkpoint_file);
has_results = ~isempty(results_file) && isfile(results_file);
has_live_annotations = video_annotation_count(app) > 0;
has_annotations = has_live_annotations || (has_annotations_file && has_worldlines_file);

if has_video
    file_text = compact_path(source_file);
    dataset_file_text = compact_path(source_file, 34);
    dims_text = video_dims_text(app);
    folder_text_value = source_folder_text(source_file);
    format_text_value = source_format_text(app, source_file);
    channels_text_value = source_channels_text(app);
    scale_text_value = source_scale_text(app, source_dir);
    memory_text_value = memory_text(app);
    next_text = next_action_text(has_annotations, has_checkpoint, has_results);
else
    file_text = 'No video loaded';
    dataset_file_text = file_text;
    dims_text = 'Recording: not ready';
    folder_text_value = 'Folder: n/a';
    format_text_value = 'Format: n/a';
    channels_text_value = 'Channels: n/a';
    scale_text_value = 'Scale/timing: n/a';
    memory_text_value = 'Lazy streaming starts after a video is loaded.';
    next_text = 'Next: open a video';
end

set_label(app, 'zephir_status_file', file_text, [0.88 0.91 0.94]);
set_label(app, 'zephir_status_dims', dims_text, [0.88 0.91 0.94]);
set_label(app, 'zephir_status_state', next_text, state_color(has_video, has_annotations, has_checkpoint, has_results));

set_label(app, 'zephir_dataset_file', sprintf('Source: %s', dataset_file_text), [0.10 0.10 0.10]);
set_label(app, 'zephir_dataset_folder', folder_text_value, [0.10 0.10 0.10]);
set_label(app, 'zephir_dataset_dims', dims_text, [0.10 0.10 0.10]);
set_label(app, 'zephir_dataset_format', format_text_value, [0.10 0.10 0.10]);
set_label(app, 'zephir_dataset_channels', channels_text_value, [0.10 0.10 0.10]);
set_label(app, 'zephir_dataset_scale', scale_text_value, [0.10 0.10 0.10]);
set_label(app, 'zephir_dataset_memory', memory_text_value, [0.10 0.10 0.10]);

has_neuropal_neurons = neuro_pal_neurons_available(app);

set_component_state(app.TrackingButton, 'on');
set_component_state(app.ImportexistingtracksButton, bool_state(has_video));
set_component_state(app.InsertNeuroPALNeuronsButton, bool_state(has_video && has_neuropal_neurons));
set_component_state(app.InsertlastIDdFrameButton, bool_state(has_video && has_live_annotations));
set_component_state(app.RecommendFramesButton, bool_state(has_video));
set_component_state(app.SaveAnnotationsButton, bool_state(has_video && has_live_annotations));
set_component_state(app.TrackNeuronsButton, bool_state(has_video && has_annotations));
set_component_state(app.ExtractActivityButton, bool_state(has_video && has_checkpoint));
set_component_state(app.ManipulateNeuronsButton, bool_state(has_video && has_live_annotations));
set_component_state(app.AutosegmentFrameButton, 'off');

app.TrackingButton.Visible = 'off';
app.TrackingButton.Enable = 'on';
end

function [has_video, source_file, source_dir] = video_source(app)
source_file = '';
if isprop(app, 'video_info') && isstruct(app.video_info) && ...
        isfield(app.video_info, 'file') && ~isempty(app.video_info.file)
    source_file = char(string(app.video_info.file));
elseif isprop(app, 'video_path') && ~isempty(app.video_path)
    source_file = char(string(app.video_path));
end
has_video = ~isempty(source_file);
if has_video
    source_dir = fileparts(source_file);
else
    source_dir = '';
end
end

function [analysis_file, metadata_file, annotations_file, worldlines_file, checkpoint_file, results_file] = artifact_paths(app, source_file, source_dir)
analysis_file = '';
metadata_file = '';
annotations_file = '';
worldlines_file = '';
checkpoint_file = '';
results_file = '';

if isempty(source_file) || isempty(source_dir)
    return
end

[~, ~, ext] = fileparts(source_file);
if strcmpi(ext, '.h5')
    analysis_file = source_file;
else
    analysis_file = fullfile(source_dir, 'data.h5');
end

metadata_file = fullfile(source_dir, 'metadata.json');
annotations_file = fullfile(source_dir, 'annotations.h5');
worldlines_file = fullfile(source_dir, 'worldlines.h5');
results_file = fullfile(source_dir, 'results.csv');

[~, analysis_name, analysis_ext] = fileparts(analysis_file);
filename_checkpoint = fullfile(source_dir, sprintf('%s%s_checkpoint.pt', ...
    analysis_name, analysis_ext));
generic_checkpoint = fullfile(source_dir, 'checkpoint.pt');
checkpoint_file = preferred_existing_file({filename_checkpoint, generic_checkpoint});

if isprop(app, 'video_info') && isstruct(app.video_info) && ...
        isfield(app.video_info, 'annotations') && ~isempty(app.video_info.annotations)
    annotations_file = char(string(app.video_info.annotations));
    worldlines_file = fullfile(fileparts(annotations_file), 'worldlines.h5');
end
end

function txt = video_dims_text(app)
if isprop(app, 'video_info') && isstruct(app.video_info) && ...
        all(isfield(app.video_info, {'nx', 'ny', 'nz', 'nc', 'nt'}))
    txt = sprintf('Dims: %d x %d x %d, %d channels, %d frames', ...
        app.video_info.nx, app.video_info.ny, app.video_info.nz, ...
        app.video_info.nc, app.video_info.nt);
else
    txt = 'Recording: metadata missing';
end
end

function txt = source_folder_text(source_file)
[parent, ~, ~] = fileparts(source_file);
txt = sprintf('Folder: %s', compact_path(parent, 44));
end

function txt = source_format_text(app, source_file)
[~, ~, ext] = fileparts(source_file);
ext = lower(string(ext));
format_name = upper(erase(ext, "."));
if strlength(format_name) == 0
    format_name = "unknown";
end

dtype_text = 'sample depth unknown';
chunk_text = '';
if isprop(app, 'video_info') && isstruct(app.video_info)
    if isfield(app.video_info, 'bitDepth') && ~isempty(app.video_info.bitDepth)
        bit_value = app.video_info.bitDepth;
        if isnumeric(bit_value) && isscalar(bit_value)
            dtype_text = sprintf('%g-bit samples', double(bit_value));
        elseif ischar(bit_value) || isstring(bit_value)
            dtype_text = char(string(bit_value));
        end
    end
    if isfield(app.video_info, 'ChunkSize') && ~isempty(app.video_info.ChunkSize)
        chunk_text = sprintf(', chunk %s', mat2str(app.video_info.ChunkSize));
    end
end
txt = sprintf('Format: %s, %s%s', char(format_name), dtype_text, chunk_text);
end

function txt = source_channels_text(app)
txt = 'Channels: metadata unavailable';
if ~isprop(app, 'video_info') || ~isstruct(app.video_info)
    return
end

if isfield(app.video_info, 'channel_names') && ~isempty(app.video_info.channel_names)
    names = app.video_info.channel_names;
    try
        names = string(names);
        txt = sprintf('Channels: %s', char(strjoin(names, ', ')));
    catch
        txt = sprintf('Channels: %d channels', app.video_info.nc);
    end
elseif isfield(app.video_info, 'nc')
    txt = sprintf('Channels: %d channels', app.video_info.nc);
end
end

function txt = source_scale_text(app, source_dir)
txt = 'Scale/timing: metadata not supplied';
if isprop(app, 'video_info') && isstruct(app.video_info)
    scale_fields = {'scale', 'xy_scale', 'z_scale', 'dt'};
    parts = {};
    for idx = 1:numel(scale_fields)
        field = scale_fields{idx};
        if isfield(app.video_info, field) && ~isempty(app.video_info.(field))
            parts{end + 1} = sprintf('%s=%s', field, value_to_text(app.video_info.(field))); %#ok<AGROW>
        end
    end
    if ~isempty(parts)
        txt = sprintf('Scale/timing: %s', strjoin(parts, ', '));
        return
    end
end

metadata_file = fullfile(source_dir, 'metadata.json');
if ~isfile(metadata_file)
    return
end
try
    metadata = jsondecode(fileread(metadata_file));
    parts = {};
    candidates = {'scale', 'xy_scale', 'z_scale', 'dt', 'fps'};
    for idx = 1:numel(candidates)
        field = candidates{idx};
        if isfield(metadata, field) && ~isempty(metadata.(field))
            parts{end + 1} = sprintf('%s=%s', field, value_to_text(metadata.(field))); %#ok<AGROW>
        end
    end
    if ~isempty(parts)
        txt = sprintf('Scale/timing: %s', strjoin(parts, ', '));
    end
catch
end
end

function txt = memory_text(app)
if isprop(app, 'video_info') && isstruct(app.video_info) && ...
        all(isfield(app.video_info, {'nx', 'ny', 'nz', 'nc', 'nt'}))
    bytes_per_voxel = bytes_per_sample(app);
    bytes = double(app.video_info.nx) * double(app.video_info.ny) * ...
        double(app.video_info.nz) * double(app.video_info.nc) * ...
        double(app.video_info.nt) * bytes_per_voxel;
    txt = sprintf('Lazy streaming active. Full stack estimate: %s.', format_bytes(bytes));
else
    txt = 'Lazy streaming starts after a video is loaded.';
end
end

function bytes = bytes_per_sample(app)
bytes = 1;
try
    bit_depth = app.video_info.bitDepth;
    if isnumeric(bit_depth) && isscalar(bit_depth) && isfinite(bit_depth)
        bytes = max(1, ceil(double(bit_depth) / 8));
    elseif ischar(bit_depth) || isstring(bit_depth)
        bits = regexp(char(string(bit_depth)), '\d+', 'match', 'once');
        if ~isempty(bits)
            bytes = max(1, ceil(str2double(bits) / 8));
        end
    end
catch
end
end

function txt = format_bytes(bytes)
units = {'B', 'KB', 'MB', 'GB', 'TB'};
value = double(bytes);
unit_idx = 1;
while value >= 1024 && unit_idx < numel(units)
    value = value / 1024;
    unit_idx = unit_idx + 1;
end
txt = sprintf('%.2f %s', value, units{unit_idx});
end

function txt = value_to_text(value)
if isnumeric(value)
    txt = mat2str(value);
elseif ischar(value) || isstring(value)
    txt = char(string(value));
else
    txt = class(value);
end
end

function n = video_annotation_count(app)
n = 0;
if ~isprop(app, 'video_neurons') || isempty(app.video_neurons)
    return
end

for idx = 1:numel(app.video_neurons)
    if ~isfield(app.video_neurons(idx), 'rois') || isempty(app.video_neurons(idx).rois)
        continue
    end
    rois = app.video_neurons(idx).rois;
    for t = 1:numel(rois)
        if has_roi_position(rois(t))
            n = n + 1;
        end
    end
end
end

function tf = has_roi_position(roi)
fields = {'x_slice', 'y_slice', 'z_slice'};
tf = true;
for idx = 1:numel(fields)
    field = fields{idx};
    tf = tf && isfield(roi, field) && ~isempty(roi.(field)) && ...
        isnumeric(roi.(field)) && isscalar(roi.(field)) && isfinite(roi.(field));
end
end

function tf = neuro_pal_neurons_available(app)
try
    tf = isprop(app, 'image_neurons') && ~isempty(app.image_neurons) && ...
        ~isempty(app.image_neurons.neurons);
catch
    tf = false;
end
end

function txt = next_action_text(has_annotations, has_checkpoint, has_results)
if ~has_annotations
    txt = 'Next: seed reference annotations';
elseif ~has_checkpoint
    txt = 'Next: run ZephIR tracking';
elseif ~has_results
    txt = 'Next: review tracked worldlines';
else
    txt = 'Next: extract activity or export';
end
end

function color = state_color(has_video, has_annotations, has_checkpoint, has_results)
if ~has_video
    color = [1.00 0.82 0.34];
elseif ~has_annotations
    color = [1.00 0.70 0.24];
elseif ~has_checkpoint
    color = [0.44 0.78 1.00];
elseif ~has_results
    color = [0.48 0.82 0.48];
else
    color = [0.40 0.88 0.55];
end
end

function path = preferred_existing_file(candidates)
path = candidates{1};
for idx = 1:numel(candidates)
    if isfile(candidates{idx})
        path = candidates{idx};
        return
    end
end
end

function path_text = compact_path(path, max_chars)
if nargin < 2
    max_chars = 54;
end
path_text = char(string(path));
if strlength(string(path_text)) > max_chars
    [parent, name, ext] = fileparts(path_text);
    [~, parent_name] = fileparts(parent);
    path_text = fullfile('...', parent_name, [name ext]);
    if strlength(string(path_text)) > max_chars
        path_text = [name ext];
    end
end
end

function set_label(app, tag, text, color)
label = findobj(app.VideoTrackingTab, 'Tag', tag);
if isempty(label) || ~isvalid(label(1))
    return
end
label = label(1);
label.Text = char(string(text));
if isprop(label, 'Tooltip')
    label.Tooltip = {char(string(text))};
end
if nargin >= 4
    label.FontColor = color;
end
end

function set_component_state(component, state)
if isempty(component) || ~isvalid(component) || ~isprop(component, 'Enable')
    return
end
component.Enable = state;
end

function state = bool_state(tf)
if tf
    state = 'on';
else
    state = 'off';
end
end
