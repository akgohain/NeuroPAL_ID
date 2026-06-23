function ensure_main_image_axes(app)
%ENSURE_MAIN_IMAGE_AXES Use runtime-managed axes for large image viewers.

if nargin < 1 || isempty(app)
    app = Program.app;
end

try
    app.XY = local_ensure_axes(app.XY, app.XYPanel, [1 1 1 1]);
catch
end

try
    app.MaxProjection = local_ensure_axes(app.MaxProjection, ...
        app.MaximumIntensityProjectionTab, [1 1 1 1]);
catch
end
end

function ax = local_ensure_axes(ax, parent, padding)
if isempty(parent) || ~isvalid(parent)
    return
end
if isprop(parent, 'AutoResizeChildren')
    parent.AutoResizeChildren = 'off';
end

if isempty(ax) || ~isvalid(ax)
    old_ax = ax;
    ax = uiaxes(parent);
    ax.Box = 'on';
    ax.FontWeight = 'bold';
    ax.FontSize = 10;
    ax.Units = 'pixels';
    if ~isempty(old_ax) && isvalid(old_ax)
        try
            ax.Title.Interpreter = old_ax.Title.Interpreter;
            ax.Title.String = old_ax.Title.String;
            ax.TitleFontSizeMultiplier = old_ax.TitleFontSizeMultiplier;
            ax.TitleFontWeight = old_ax.TitleFontWeight;
        catch
        end
        try
            delete(old_ax);
        catch
        end
    end
end

Program.Helpers.fill_axes_parent(ax, padding);
end
