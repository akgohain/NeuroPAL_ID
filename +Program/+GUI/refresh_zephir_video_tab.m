function refresh_zephir_video_tab(app)
%REFRESH_ZEPHIR_VIDEO_TAB Safely refresh ZephIR video tab state.

if nargin < 1 || isempty(app) || ~isvalid(app) || ...
        ~isprop(app, 'VideoTrackingTab') || isempty(app.VideoTrackingTab) || ...
        ~isvalid(app.VideoTrackingTab)
    return
end

Program.GUI.update_zephir_video_tab(app);
end

