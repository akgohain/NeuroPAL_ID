function package = compose_volume(app, raw)
if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 2 || isempty(raw)
    raw = Program.GUIHandling.get_active_volume(app, 'request', 'all');
end

[raw_volume, raw_dims] = Program.Validation.pad_rgb(raw.array);
if strcmp(app.VolumeDropDown.Value, 'Colormap') && app.ProcShowMIPCheckBox.Value && ...
        isfield(app.flags, 'debleed') && app.flags.debleed
    % Subtract channel crosstalk before projecting; these operations do not commute.
    context = Program.Helpers.processing_colormap_context(app);
    for z = 1:context.dims(3)
        slice = Program.Helpers.read_processing_colormap(app, 'z', z);
        slice = Methods.ChunkyMethods.apply_preview_actions(app, slice);
        if z == 1
            preview_raw_volume = slice;
        else
            preview_raw_volume = max(preview_raw_volume, slice);
        end
    end
else
    preview_raw_volume = Methods.ChunkyMethods.apply_preview_actions(app, raw_volume);
end
display_package = Program.Helpers.get_display_volume(app, 'processing', preview_raw_volume);
channels = display_package.channels;
threshold_raw = display_package.threshold_raw;
render_volume = display_package.display_volume;

package = struct( ...
    'raw', raw, ...
    'raw_volume', raw_volume, ...
    'preview_raw_volume', preview_raw_volume, ...
    'raw_dims', raw_dims, ...
    'channels', channels, ...
    'render_volume', render_volume, ...
    'threshold_raw', threshold_raw);
end
