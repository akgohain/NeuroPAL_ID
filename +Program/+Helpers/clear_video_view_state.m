function clear_video_view_state(app)
%CLEAR_VIDEO_VIEW_STATE Reset cached and transient video-view state.

if nargin < 1 || isempty(app) || ~isvalid(app)
    return
end

if isprop(app, 'video_frame_cache')
    app.video_frame_cache = [];
end
if isprop(app, 'video_frame_cache_key')
    app.video_frame_cache_key = struct('file', '', 't', NaN);
end

keys = { ...
    'video_tslider_live_last_t', ...
    'video_tslider_live_last_seconds', ...
    'video_tslider_live_previewing'};
for idx = 1:numel(keys)
    if isappdata(app.CELL_ID, keys{idx})
        rmappdata(app.CELL_ID, keys{idx});
    end
end

if ismethod(app, 'resetVideoViewCache')
    app.resetVideoViewCache();
end
end
