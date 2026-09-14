function revision = main_display_source_revision(app, invalidate)
%MAIN_DISPLAY_SOURCE_REVISION Identify pixel changes without hashing the stack.
% main_display_view_cache(app, []) advances this revision and drops the cache.
if nargin < 2
    invalidate = false;
end
revision = uint64(0);
if isempty(app) || ~isprop(app, 'CELL_ID') || ...
        isempty(app.CELL_ID) || ~isvalid(app.CELL_ID)
    return
end
key = 'main_display_source_revision';
if isappdata(app.CELL_ID, key)
    revision = getappdata(app.CELL_ID, key);
end
if invalidate
    revision = revision + uint64(1);
    setappdata(app.CELL_ID, key, revision);
end
end
