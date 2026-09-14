function view = main_display_view_cache(app, view)
%MAIN_DISPLAY_VIEW_CACHE Own the bounded projection/current-plane cache.
% Passing [] explicitly invalidates pixel data, including previously returned
% cache structs. app.image_view is a lightweight compatibility alias.

if nargin < 1 || isempty(app)
    app = Program.app;
end
key = 'main_display_view_cache';
if nargin > 1
    if isempty(view)
        Program.Helpers.main_display_source_revision(app, true);
        if isprop(app, 'CELL_ID') && isvalid(app.CELL_ID) && isappdata(app.CELL_ID, key)
            rmappdata(app.CELL_ID, key);
        end
    elseif isprop(app, 'CELL_ID') && isvalid(app.CELL_ID)
        setappdata(app.CELL_ID, key, view);
    end
    if isprop(app, 'image_view')
        app.image_view = view;
    end
    return
end

view = [];
try
    if isprop(app, 'CELL_ID') && isvalid(app.CELL_ID) && isappdata(app.CELL_ID, key)
        view = getappdata(app.CELL_ID, key);
    end
catch
    view = [];
end
end
