function listeners = drag_event_listeners(app, install, callbacks)
%DRAG_EVENT_LISTENERS Replace or release the app-owned drag listeners.
if nargin < 2
    install = true;
end
key = 'main_drag_event_listeners';
listeners = {};
if isempty(app) || ~isvalid(app) || isempty(app.CELL_ID) || ~isvalid(app.CELL_ID)
    return
end
if isappdata(app.CELL_ID, key)
    previous = getappdata(app.CELL_ID, key);
    rmappdata(app.CELL_ID, key);
    for n = 1:numel(previous)
        if isvalid(previous{n})
            delete(previous{n});
        end
    end
end
if ~install
    return
end
if nargin < 3
    callbacks = getappdata(app.CELL_ID, 'main_drag_event_callbacks');
    if isempty(callbacks)
        error('Program:UI:MissingDragCallbacks', 'The app drag callbacks have not been initialized.');
    end
end
try
    listeners{1} = addlistener(app.CELL_ID, 'WindowMousePress', callbacks{1});
    listeners{2} = addlistener(app.CELL_ID, 'WindowMouseRelease', callbacks{2});
catch exception
    for n = 1:numel(listeners)
        delete(listeners{n});
    end
    rethrow(exception);
end
setappdata(app.CELL_ID, key, listeners);
end
