classdef UiRuntimeTestApp < handle
    %UIRUNTIMETESTAPP Small owner for listener and notification lifecycle tests.
    properties
        CELL_ID
        Log
        TabGroup
        EnablelogCheckBox = struct('Value', true)
        EnablelognotificationsCheckBox = struct('Value', true)
    end
    methods
        function app = UiRuntimeTestApp()
            app.CELL_ID = uifigure('Visible', 'off');
            app.Log = uitextarea(app.CELL_ID);
            app.TabGroup = uitabgroup(app.CELL_ID);
            setappdata(app.CELL_ID, 'main_drag_event_callbacks', ...
                {@(src, event) [], @(src, event) []});
        end
        function delete(app)
            if ~isempty(app.CELL_ID) && isvalid(app.CELL_ID)
                Program.Helpers.cleanup_ui_runtime(app);
                delete(app.CELL_ID);
            end
        end
    end
end
