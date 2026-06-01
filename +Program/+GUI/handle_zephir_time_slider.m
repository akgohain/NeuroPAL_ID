function handle_zephir_time_slider(app, value, is_final)
%HANDLE_ZEPHIR_TIME_SLIDER Keep time scrubbing responsive for lazy videos.
% Live slider events update only the current XY plane. The full orthogonal
% render and ROI refresh still happen when the user releases the slider.

if nargin < 3
    is_final = true;
end
if nargin < 2 || isempty(app) || ~isvalid(app) || isempty(value)
    return
end
if ~isprop(app, 'video_info') || isempty(app.video_info) || ...
        ~isstruct(app.video_info) || ~isfield(app.video_info, 'nt')
    return
end

target_t = clamp_time(app, value);
app.tEditField.Value = target_t;

if is_final
    app.tSlider.Value = target_t;
    setappdata(app.CELL_ID, 'video_tslider_live_last_t', target_t);
    setappdata(app.CELL_ID, 'video_tslider_live_previewing', false);
    tune_video_cache(app);
    app.visual_composer(target_t);
    prefetch_neighbor_xy(app, target_t);
    drawnow limitrate nocallbacks
    return
end

if ~should_live_preview(app, target_t)
    drawnow limitrate nocallbacks
    return
end

setappdata(app.CELL_ID, 'video_tslider_live_previewing', true);
cleanup = onCleanup(@() setappdata(app.CELL_ID, ...
    'video_tslider_live_previewing', false));
tune_video_cache(app);
render_live_xy_preview(app, target_t);
clear cleanup
drawnow limitrate nocallbacks
end

function target_t = clamp_time(app, value)
limits = double(app.tSlider.Limits);
if numel(limits) < 2 || any(~isfinite(limits))
    limits = [1, max(1, double(app.video_info.nt))];
end

target_t = round(double(value));
if isempty(target_t) || ~isfinite(target_t)
    target_t = round(double(app.tSlider.Value));
end
target_t = min(max(target_t, limits(1)), limits(2));
target_t = min(max(target_t, 1), max(1, double(app.video_info.nt)));
end

function tf = should_live_preview(app, target_t)
tf = false;

if isappdata(app.CELL_ID, 'video_tslider_live_previewing') && ...
        logical(getappdata(app.CELL_ID, 'video_tslider_live_previewing'))
    return
end

last_t = NaN;
if isappdata(app.CELL_ID, 'video_tslider_live_last_t')
    last_t = getappdata(app.CELL_ID, 'video_tslider_live_last_t');
end
if isequal(last_t, target_t)
    return
end

now_seconds = now * 86400; %#ok<TNOW1>
last_seconds = -Inf;
if isappdata(app.CELL_ID, 'video_tslider_live_last_seconds')
    last_seconds = getappdata(app.CELL_ID, 'video_tslider_live_last_seconds');
end

if now_seconds - last_seconds < 0.035
    return
end

setappdata(app.CELL_ID, 'video_tslider_live_last_t', target_t);
setappdata(app.CELL_ID, 'video_tslider_live_last_seconds', now_seconds);
tf = true;
end

function render_live_xy_preview(app, target_t)
if live_orthos_enabled(app)
    app.visual_composer(target_t);
    return
end

z = round(double(app.hor_zSlider.Value));
x = round(double(app.video_info.ny) - double(app.ySlider.Value));
y = round(double(app.xSlider.Value));
[target_t, z, x, y] = app.clampVideoViewCoordinates(target_t, z, x, y);

xy = app.readCachedVideoXYStack(target_t, z);
xy = app.scaleVideoProjection(xy);
xy_img = app.setVideoImage(app.xyAxes, xy, 'npal_video_xy');
xy_img.ButtonDownFcn = {@app.ImageClicked};

app.xyAxes.XLim = [1, size(xy, 2)];
app.xyAxes.YLim = [1, size(xy, 1)];
Program.GUI.configure_zephir_video_axes(app);
Program.Helpers.draw_video_cursor(x, y, z);
end

function tf = live_orthos_enabled(app)
try
    tf = isappdata(app.CELL_ID, 'zephir_live_orthos_during_drag') && ...
        logical(getappdata(app.CELL_ID, 'zephir_live_orthos_during_drag'));
catch
    tf = false;
end
end

function prefetch_neighbor_xy(app, target_t)
z = round(double(app.hor_zSlider.Value));
neighbor_t = unique([target_t - 1, target_t + 1]);
neighbor_t = neighbor_t(neighbor_t >= 1 & neighbor_t <= double(app.video_info.nt));

for t_idx = neighbor_t
    try
        app.readCachedVideoXYStack(t_idx, z);
    catch
    end
end
end

function tune_video_cache(app)
try
    cache = app.ensureVideoViewCache();
    cache.max_planes = max(cache.max_planes, 96);
    cache.max_plane_bytes = max(cache.max_plane_bytes, 256 * 1024 * 1024);
    cache.max_views = max(cache.max_views, 32);
    cache.max_view_bytes = max(cache.max_view_bytes, 192 * 1024 * 1024);
    app.video_view_cache = cache;
catch
end
end
