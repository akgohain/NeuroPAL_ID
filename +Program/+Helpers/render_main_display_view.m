function view = render_main_display_view(app, z_gui, existing_view)
%RENDER_MAIN_DISPLAY_VIEW Build a bounded cache for the main image viewer.
% Pixel mutations must invalidate main_display_view_cache or request a full
% Program.Routines.ID.render; z navigation may reuse the cached projection.

if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 2 || isempty(z_gui)
    z_gui = app.ZSlider.Value;
end
if nargin < 3
    existing_view = [];
end
if isempty(app.image_data)
    view = [];
    return
end

is_z_flip = isstruct(app.image_prefs) && ...
    isfield(app.image_prefs, 'is_Z_flip') && logical(app.image_prefs.is_Z_flip);
state = Program.Handlers.channels.main_state(app);
channels = struct( ...
    'r', state.r, 'g', state.g, 'b', state.b, ...
    'white', state.white, 'dic', state.dic, 'gfp', state.gfp, 'other', {{}});
source_file = '';
if isprop(app, 'image_file')
    source_file = char(string(app.image_file));
end
source_key = struct('file', source_file, ...
    'revision', Program.Helpers.main_display_source_revision(app));
view = Program.Helpers.compose_main_display_view( ...
    app.image_data, channels, z_gui, is_z_flip, source_key, existing_view, 0);
end
