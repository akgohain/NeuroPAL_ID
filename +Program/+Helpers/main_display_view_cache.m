function view = main_display_view_cache(app, view)
%MAIN_DISPLAY_VIEW_CACHE Store the modern main display render cache.

if nargin < 1 || isempty(app)
    app = Program.app;
end

key = 'main_display_view_cache';
if nargin > 1
    if isempty(view)
        if isprop(app, 'CELL_ID') && isvalid(app.CELL_ID) && isappdata(app.CELL_ID, key)
            rmappdata(app.CELL_ID, key);
        end
    elseif isprop(app, 'CELL_ID') && isvalid(app.CELL_ID)
        setappdata(app.CELL_ID, key, view);
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
