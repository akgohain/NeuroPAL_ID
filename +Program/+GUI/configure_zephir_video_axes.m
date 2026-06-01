function configure_zephir_video_axes(app)
%CONFIGURE_ZEPHIR_VIDEO_AXES Keep the orthogonal viewer edges aligned.
% These views are navigation displays. They intentionally fill their allocated
% cells so XY/XZ and XY/YZ edges remain collinear in the workstation layout.

if nargin < 1 || isempty(app) || ~isvalid(app)
    return
end

configure_projection_axis(app.xyAxes);
configure_projection_axis(app.xzAxes);
configure_projection_axis(app.yzAxes);
end

function configure_projection_axis(ax)
if isempty(ax) || ~isvalid(ax)
    return
end
try
    axis(ax, 'normal');
    ax.DataAspectRatioMode = 'auto';
    ax.PlotBoxAspectRatioMode = 'auto';
    ax.XTick = [];
    ax.YTick = [];
    ax.Box = 'off';
    ax.Layer = 'top';
catch
end
end
