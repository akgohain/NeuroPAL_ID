function configure_image_axes_minor_ticks(ax, x_minor_ticks, y_minor_ticks)
%CONFIGURE_IMAGE_AXES_MINOR_TICKS Apply minor ticks across MATLAB axes variants.

if nargin < 1 || isempty(ax) || ~isvalid(ax)
    return
end

try
    ax.XMinorTick = 'on';
    ax.YMinorTick = 'on';
catch
end

try
    if isprop(ax, 'XAxis') && isprop(ax.XAxis, 'MinorTickValues')
        ax.XAxis.MinorTickValues = x_minor_ticks;
    end
catch
end

try
    if isprop(ax, 'YAxis') && isprop(ax.YAxis, 'MinorTickValues')
        ax.YAxis.MinorTickValues = y_minor_ticks;
    end
catch
end
end
