function source = main_display_export_source(app)
%MAIN_DISPLAY_EXPORT_SOURCE Snapshot display settings for slice-wise export.
Program.Helpers.get_current_display_slice(app, 'main');
view = Program.Helpers.main_display_view_cache(app);
if isempty(view)
    source = [];
    return
end
raw = app.image_data;
source = struct('dims', [size(raw, 1), size(raw, 2), size(raw, 3), 3], ...
    'read_slice', @(z) local_read_slice(raw, view, z));
end

function plane = local_read_slice(raw, view, z)
if ~isequal(Program.GUIPreferences.instance().GFP_color, view.signature.gfp_color)
    error('Program:Display:ChangedExportSettings', 'Display settings changed; restart the image export.');
end
slice = reshape(raw(:, :, z, :), size(raw, 1), size(raw, 2), 1, size(raw, 4));
[rgb, channels] = Program.Helpers.compose_display_volume(slice, view.channels);
rgb = Program.Helpers.finalize_display_volume(rgb, channels, view.threshold_raw, view.volume_max);
plane = reshape(single(rgb) / 255, size(raw, 1), size(raw, 2), 3);
end
