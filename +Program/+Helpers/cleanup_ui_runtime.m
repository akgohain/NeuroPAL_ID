function cleanup_ui_runtime(app)
%CLEANUP_UI_RUNTIME Release resources owned by the closing app.
Program.Helpers.drag_event_listeners(app, false);
Program.Helpers.clear_log_notification(app);
Program.GUI.clear_zephir_time_slider(app);
end
