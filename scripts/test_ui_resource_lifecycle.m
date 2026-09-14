function test_ui_resource_lifecycle()
%TEST_UI_RESOURCE_LIFECYCLE Verify listener replacement and bounded UI logging.
repo_root = fileparts(fileparts(mfilename('fullpath')));
original_path = path;
addpath(fullfile(repo_root, 'scripts', 'fixtures'));
try
    app = UiRuntimeTestApp();
catch exception
    path(original_path);
    rethrow(exception);
end
cleanup = onCleanup(@() local_finish(app, original_path));

previous = {};
for iteration = 1:20
    current = Program.Helpers.drag_event_listeners(app);
    assert(numel(current) == 2 && all(cellfun(@isvalid, current)));
    assert(all(cellfun(@(listener) ~isvalid(listener), previous)));
    previous = current;
end
Program.Helpers.drag_event_listeners(app, false);
assert(all(cellfun(@(listener) ~isvalid(listener), current)));
assert(~isappdata(app.CELL_ID, 'main_drag_event_listeners'));

app.Log.Value = cellstr("Old " + string((1:510)'));
Program.Helpers.log_event(app, 'Test', 'New log entry', false);
assert(numel(app.Log.Value) == 500 && contains(app.Log.Value{end}, 'New log entry'));
Program.Helpers.log_event(app, 'Test', repmat('x', 1, 5000), false);
assert(numel(app.Log.Value{end}) == 4000);
for iteration = 1:5
    Program.Helpers.log_event(app, 'Test', 'Notification', true);
    current_timer = getappdata(app.CELL_ID, 'log_notification_timer');
    current_label = getappdata(app.CELL_ID, 'log_notification_label');
    if iteration > 1
        assert(~isvalid(previous_timer) && ~isvalid(previous_label));
    end
    previous_timer = current_timer;
    previous_label = current_label;
end
expire = current_timer.TimerFcn;
expire(current_timer, []);
assert(~isvalid(current_timer) && ~isvalid(current_label));
assert(~isappdata(app.CELL_ID, 'log_notification_timer'));

listeners = Program.Helpers.drag_event_listeners(app);
Program.Helpers.log_event(app, 'Test', 'Closing app', true);
owned_timer = getappdata(app.CELL_ID, 'log_notification_timer');
Program.Helpers.cleanup_ui_runtime(app);
Program.Helpers.cleanup_ui_runtime(app);
assert(~isvalid(owned_timer));
assert(all(cellfun(@(listener) ~isvalid(listener), listeners)));
clear cleanup
fprintf('UI_RESOURCE_LIFECYCLE=PASS\n');
end

function local_finish(app, original_path)
% Delete fixture objects while their class definitions remain on the path.
delete(app);
path(original_path);
end
