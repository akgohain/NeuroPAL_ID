function saved = write_processing_colormap_to_file(app)
% Persist the shared in-memory colormap volume/prefs to the backing MAT file.

if nargin < 1 || isempty(app)
    app = Program.app;
end

saved = false;
if ~strcmpi(char(string(app.VolumeDropDown.Value)), 'Colormap')
    return
end

context = Program.Helpers.processing_colormap_context(app);
if strlength(string(context.path)) == 0
    return
end

if isempty(context.volume) && ~context.is_lazy
    return
end

Program.Helpers.sync_main_display_from_processing(app, false);

data = app.image_data;
has_data = ~isempty(context.volume);
prefs = app.image_prefs;
info = app.image_info;
if isstruct(info)
    info.scale = app.image_um_scale;
end

if context.is_lazy && ~has_data
    if isa(app.proc_image, 'matlab.io.MatFile')
        app.proc_image.Properties.Writable = true;
        cleanup = onCleanup(@() local_make_readonly(app));
        if isstruct(info) && ~isempty(fieldnames(info))
            app.proc_image.info = info;
        end
        if isstruct(prefs) && ~isempty(fieldnames(prefs))
            app.proc_image.prefs = prefs;
        end
    else
        vars = {};
        if isstruct(info) && ~isempty(fieldnames(info))
            vars{end+1} = 'info';
        end
        if isstruct(prefs) && ~isempty(fieldnames(prefs))
            vars{end+1} = 'prefs';
        end
        if ~isempty(vars)
            save(context.path, vars{:}, '-append');
        end
    end
else
    if isa(app.proc_image, 'matlab.io.MatFile')
        app.proc_image.Properties.Writable = true;
        cleanup = onCleanup(@() local_make_readonly(app));
        app.proc_image.data = data;
        if isstruct(info) && ~isempty(fieldnames(info))
            app.proc_image.info = info;
        end
        if isstruct(prefs) && ~isempty(fieldnames(prefs))
            app.proc_image.prefs = prefs;
        end
    else
        if isstruct(info) && ~isempty(fieldnames(info))
            save(context.path, 'data', 'prefs', 'info', '-append');
        else
            save(context.path, 'data', 'prefs', '-append');
        end
    end
end

if isappdata(app.CELL_ID, 'proc_runtime_dirty')
    rmappdata(app.CELL_ID, 'proc_runtime_dirty');
end

Program.GUIHandling.clear_processing_preview_cache(app);
saved = true;
end

function local_make_readonly(app)
if isa(app.proc_image, 'matlab.io.MatFile')
    app.proc_image.Properties.Writable = false;
end
end
