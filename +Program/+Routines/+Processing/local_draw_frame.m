function local_draw_frame(app, ax, frame)
if nargin < 1 || isempty(app)
    app = Program.app;
end

if isempty(frame)
    local_hide_frame(ax);
    return
end

frame = local_validate_frame(app, frame);
img = local_get_frame_handle(ax);
frame_size = size(frame);
reset_view = false;

if isempty(img) || ~isgraphics(img)
    img = image(frame, 'Parent', ax, ...
        'Tag', 'processing_frame', ...
        'HitTest', 'off', ...
        'PickableParts', 'none');
    setappdata(ax, 'proc_frame_handle', img);
    setappdata(ax, 'proc_frame_dims', frame_size);
    reset_view = true;
    local_configure_frame_ticks(app, ax, frame_size, reset_view);
    return
end

img.CData = frame;
img.Visible = 'on';

previous_size = [];
if isappdata(ax, 'proc_frame_dims')
    previous_size = getappdata(ax, 'proc_frame_dims');
end

if ~isequal(previous_size, frame_size)
    setappdata(ax, 'proc_frame_dims', frame_size);
    reset_view = true;
elseif ~local_viewport_is_valid(ax, frame_size)
    reset_view = true;
end

local_configure_frame_ticks(app, ax, frame_size, reset_view);
end

function frame = local_validate_frame(app, frame)
if ismatrix(frame)
    return
end

if ndims(frame) == 3 && size(frame, 3) >= 3
    if size(frame, 3) > 3
        frame = frame(:, :, 1:3);
    end
    return
end

msg = sprintf('Processing render: unexpected frame size %s', mat2str(size(frame)));
fprintf('%s\n', msg);
try
    app.logEvent('Processing', msg, 0);
catch
end
error('Processing render: invalid frame size %s', mat2str(size(frame)));
end

function img = local_get_frame_handle(ax)
img = [];
if isappdata(ax, 'proc_frame_handle')
    img = getappdata(ax, 'proc_frame_handle');
    if ~isempty(img) && isgraphics(img)
        return
    end
end

images = findall(ax, 'Type', 'image', 'Tag', 'processing_frame');
if ~isempty(images)
    img = images(1);
    img.Tag = 'processing_frame';
    if isprop(img, 'HitTest')
        img.HitTest = 'off';
    end
    if isprop(img, 'PickableParts')
        img.PickableParts = 'none';
    end
    setappdata(ax, 'proc_frame_handle', img);
    return
end

images = findall(ax, 'Type', 'image');
if ~isempty(images)
    img = images(1);
    img.Tag = 'processing_frame';
    if isprop(img, 'HitTest')
        img.HitTest = 'off';
    end
    if isprop(img, 'PickableParts')
        img.PickableParts = 'none';
    end
    setappdata(ax, 'proc_frame_handle', img);
end
end

function local_hide_frame(ax)
img = local_get_frame_handle(ax);
if ~isempty(img) && isgraphics(img)
    img.Visible = 'off';
end
end

function local_configure_frame_ticks(app, ax, frame_size, reset_view)
scale_xy = local_frame_scale(app, ax);
if reset_view
    Program.Helpers.configure_image_axes_ticks( ...
        ax, frame_size, scale_xy, ...
        'XLim', [1, max(1, frame_size(2))], ...
        'YLim', [1, max(1, frame_size(1))]);
else
    Program.Helpers.configure_image_axes_ticks(ax, frame_size, scale_xy);
end
end

function scale_xy = local_frame_scale(app, ax)
plane = "xy";
try
    if isvalid(app.proc_xzAxes) && ax == app.proc_xzAxes
        plane = "xz";
    elseif isvalid(app.proc_yzAxes) && ax == app.proc_yzAxes
        plane = "yz";
    end
catch
end
scale_xy = Program.Helpers.processing_axis_scale(app, plane);
end

function tf = local_viewport_is_valid(ax, frame_size)
tf = false;
if isempty(ax) || ~isvalid(ax)
    return
end

limits = [ax.XLim ax.YLim];
if any(~isfinite(limits)) || diff(ax.XLim) <= 0 || diff(ax.YLim) <= 0
    return
end

nx = max(1, frame_size(2));
ny = max(1, frame_size(1));
tf = ax.XLim(1) >= 1 && ax.XLim(2) <= nx && ...
    ax.YLim(1) >= 1 && ax.YLim(2) <= ny;
end
