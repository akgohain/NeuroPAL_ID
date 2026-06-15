function view = render_main_display_view(app, z_gui, existing_view)
%RENDER_MAIN_DISPLAY_VIEW Render main-view max projection and current slice.

if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 2 || isempty(z_gui)
    z_gui = app.ZSlider.Value;
end
if nargin < 3
    existing_view = [];
end

raw_volume = app.image_data;
if isempty(raw_volume)
    view = [];
    return
end

z_count = size(raw_volume, 3);
z_gui = min(max(round(double(z_gui)), 1), z_count);
if isstruct(app.image_prefs) && isfield(app.image_prefs, 'is_Z_flip')
    is_z_flip = logical(app.image_prefs.is_Z_flip);
else
    is_z_flip = false;
end
z_data = Program.Helpers.gui_z_to_data_index(z_gui, z_count, is_z_flip);

if local_can_reuse_projection(existing_view)
    view = existing_view;
    [slice_rgb, rgb_channels] = local_compose_slice(raw_volume, view.channels, z_data);
    view.rgb_channels = rgb_channels;
    view.display_slice = Program.Helpers.finalize_display_volume( ...
        slice_rgb, view.rgb_channels, view.threshold_raw, view.volume_max);
    view.z_gui = z_gui;
    view.z_data = z_data;
    return
end

state = Program.Handlers.channels.main_state(app);
channels = struct( ...
    'r', state.r, ...
    'g', state.g, ...
    'b', state.b, ...
    'white', state.white, ...
    'dic', state.dic, ...
    'gfp', state.gfp, ...
    'other', {{}});

threshold_raw = 0;
max_projection = [];
display_slice = [];
volume_max = 0;
rgb_channels = {};

for z = 1:z_count
    Program.Handlers.dialogue.step(sprintf('Rendering z-slice %d of %d...', z, z_count));
    [slice_rgb, rgb_channels] = local_compose_slice(raw_volume, channels, z);

    if isempty(max_projection)
        max_projection = slice_rgb;
    else
        max_projection = max(max_projection, slice_rgb);
    end

    slice_max = double(max(slice_rgb, [], 'all'));
    if slice_max > volume_max
        volume_max = slice_max;
    end

    if z == z_data
        display_slice = slice_rgb;
    end
end

max_projection = Program.Helpers.finalize_display_volume( ...
    max_projection, rgb_channels, threshold_raw, volume_max);
display_slice = Program.Helpers.finalize_display_volume( ...
    display_slice, rgb_channels, threshold_raw, volume_max);

view = struct( ...
    'renderer', 'main_display_view', ...
    'target', 'main', ...
    'channels', channels, ...
    'rgb_channels', {rgb_channels}, ...
    'threshold_raw', threshold_raw, ...
    'is_z_flip', is_z_flip, ...
    'z_gui', z_gui, ...
    'z_data', z_data, ...
    'volume_max', volume_max, ...
    'max_projection', max_projection, ...
    'display_slice', display_slice);
end

function tf = local_can_reuse_projection(view)
tf = isstruct(view) && isfield(view, 'renderer') && ...
    strcmp(char(string(view.renderer)), 'main_display_view') && ...
    isfield(view, 'max_projection') && ~isempty(view.max_projection) && ...
    isfield(view, 'channels') && isfield(view, 'threshold_raw') && ...
    isfield(view, 'volume_max') && isfinite(double(view.volume_max));
end

function [slice_rgb, rgb_channels] = local_compose_slice(raw_volume, channels, z_data)
raw_slice = raw_volume(:, :, z_data, :);
if ndims(raw_slice) < 4
    raw_slice = reshape(raw_slice, size(raw_slice, 1), size(raw_slice, 2), 1, []);
end
[slice_rgb, rgb_channels] = Program.Helpers.compose_display_volume(raw_slice, channels);
end
