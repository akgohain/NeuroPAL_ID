function log_event(app, source, event, notify)
%LOG_EVENT Keep a bounded UI log and one expiring notification per app.
if nargin < 4
    notify = false;
end
if ~app.EnablelogCheckBox.Value
    return
end
line = sprintf('%s (%s): %s', string(datetime('now')), string(source), string(event));
if numel(line) > 4000
    line = [line(1:3997), '...'];
end
app.Log.Value = Program.GUIHandling.append_bounded_log(app.Log.Value, line);
if ~notify || ~app.EnablelognotificationsCheckBox.Value
    return
end

Program.Helpers.clear_log_notification(app);
fig = app.CELL_ID;
label = uilabel('Parent', fig, 'Text', line, ...
    'Position', [fig.Position(3)-500, app.TabGroup.Position(4)-23, 500, 23], ...
    'FontColor', [0 0 0], 'HorizontalAlignment', 'right');
notification_timer = timer('Name', 'NeuroPAL log notification', ...
    'ExecutionMode', 'singleShot', 'StartDelay', 3, ...
    'TimerFcn', @(t, event) local_expire(t, fig));
setappdata(fig, 'log_notification_label', label);
setappdata(fig, 'log_notification_timer', notification_timer);
try
    start(notification_timer);
catch exception
    Program.Helpers.clear_log_notification(app);
    rethrow(exception);
end
end

function local_expire(t, fig)
if isvalid(fig) && isappdata(fig, 'log_notification_timer') && ...
        isequal(getappdata(fig, 'log_notification_timer'), t)
    rmappdata(fig, 'log_notification_timer');
    if isappdata(fig, 'log_notification_label')
        label = getappdata(fig, 'log_notification_label');
        rmappdata(fig, 'log_notification_label');
        if isvalid(label)
            delete(label);
        end
    end
end
if isvalid(t)
    stop(t);
    delete(t);
end
end
