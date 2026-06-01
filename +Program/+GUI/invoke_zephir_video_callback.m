function invoke_zephir_video_callback(app, src, event)
%INVOKE_ZEPHIR_VIDEO_CALLBACK Run a legacy callback, then refresh UI state.

if nargin < 2 || isempty(src) || ~isvalid(src)
    return
end

callback = getappdata(src, 'zephir_original_button_callback');
if isempty(callback)
    Program.GUI.update_zephir_video_tab(app);
    return
end

callback_event = event;
if isprop(src, 'Tag') && strcmp(char(string(src.Tag)), 'zephir-open-video-button') && ...
        ~(isstruct(event) && isfield(event, 'file'))
    callback_event = struct();
end

try
    feval(callback, src, callback_event);
catch ME
    Program.GUI.update_zephir_video_tab(app);
    rethrow(ME)
end

Program.GUI.update_zephir_video_tab(app);
end
