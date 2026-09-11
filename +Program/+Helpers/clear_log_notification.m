function clear_log_notification(app)
%CLEAR_LOG_NOTIFICATION Release the app-owned notification timer and label.
if isempty(app) || ~isvalid(app) || isempty(app.CELL_ID) || ~isvalid(app.CELL_ID)
    return
end
keys = {'log_notification_timer', 'log_notification_label'};
for n = 1:numel(keys)
    if ~isappdata(app.CELL_ID, keys{n})
        continue
    end
    resource = getappdata(app.CELL_ID, keys{n});
    rmappdata(app.CELL_ID, keys{n});
    if ~isempty(resource) && isvalid(resource)
        if isa(resource, 'timer')
            stop(resource);
        end
        delete(resource);
    end
end
end
