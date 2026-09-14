function [frame, z_gui, z_data] = get_current_display_slice(app, target, display_volume, requested_z)
%GET_CURRENT_DISPLAY_SLICE Return the selected plane without materializing RGB stacks.

if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 2 || strlength(string(target)) == 0
    target = "main";
end
if nargin < 3
    display_volume = [];
end
if nargin < 4, requested_z = []; end
target = lower(string(target));

switch target
    case "main"
        % Legacy callbacks pass app.image_view. Numeric stacks from an older
        % render are deliberately replaced by the current cache/source.
        if ~isstruct(display_volume) || ~isfield(display_volume, 'renderer') || ...
                ~strcmp(char(string(display_volume.renderer)), 'main_display_view')
            display_volume = Program.Helpers.main_display_view_cache(app);
        end
        if isempty(requested_z), requested_z = app.ZSlider.Value; end
        view = Program.Helpers.render_main_display_view(app, requested_z, display_volume);
        Program.Helpers.main_display_view_cache(app, view);
        if isempty(view)
            frame = [];
            z_gui = [];
            z_data = [];
        else
            frame = view.display_slice;
            z_gui = view.z_gui;
            z_data = view.z_data;
        end
    case "processing"
        if isempty(display_volume)
            package = Program.Helpers.get_display_volume(app, target);
            display_volume = package.display_volume;
        end
        [frame, z_gui, z_data] = Program.Helpers.extract_z_slice( ...
            display_volume, double(app.proc_zSlider.Value), false);
    otherwise
        error('Unknown display target: %s', target);
end
end
