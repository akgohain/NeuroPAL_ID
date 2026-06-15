function [frame, z_gui, z_data] = get_current_display_slice(app, target, display_volume)
% Extract the current UI-selected z-slice for the requested target.

if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 2 || strlength(string(target)) == 0
    target = "main";
end
target = lower(string(target));

if nargin < 3 || isempty(display_volume)
    if target == "main"
        display_volume = Program.Helpers.render_main_display_view(app, app.ZSlider.Value, ...
            Program.Helpers.main_display_view_cache(app));
        Program.Helpers.main_display_view_cache(app, display_volume);
        app.image_view = display_volume.render_volume;
    else
        package = Program.Helpers.get_display_volume(app, target);
        display_volume = package.display_volume;
    end
end

switch target
    case "main"
        z_gui = double(app.ZSlider.Value);
        if isstruct(app.image_prefs) && isfield(app.image_prefs, 'is_Z_flip')
            is_z_flip = app.image_prefs.is_Z_flip;
        else
            is_z_flip = false;
        end
    case "processing"
        z_gui = double(app.proc_zSlider.Value);
        is_z_flip = false;
    otherwise
        error('Unknown display target: %s', target);
end

if isstruct(display_volume) && isfield(display_volume, 'renderer') && ...
        strcmp(char(string(display_volume.renderer)), 'main_display_view')
    z_gui = Program.Helpers.gui_z_to_data_index(z_gui, size(app.image_data, 3), false);
    if ~isfield(display_volume, 'z_gui') || display_volume.z_gui ~= z_gui
        display_volume = Program.Helpers.render_main_display_view(app, z_gui, display_volume);
        Program.Helpers.main_display_view_cache(app, display_volume);
        app.image_view = display_volume.render_volume;
    end
    frame = squeeze(display_volume.display_slice);
    z_data = display_volume.z_data;
    return
end

[frame, z_gui, z_data] = Program.Helpers.extract_z_slice(display_volume, z_gui, is_z_flip);
end
