function fill_axes_parent(ax, padding)
%FILL_AXES_PARENT Expand image axes to fill their immediate parent.

if nargin < 1 || isempty(ax) || ~isvalid(ax)
    return
end
if nargin < 2 || isempty(padding)
    padding = [1 1 1 1];
end

try
    parent = ax.Parent;
    if isempty(parent) || ~isvalid(parent) || ~isprop(parent, 'Position')
        return
    end

    if isprop(parent, 'AutoResizeChildren')
        parent.AutoResizeChildren = 'off';
    end

    parent_position = double(parent.Position);
    if numel(parent_position) < 4 || parent_position(3) <= 1 || parent_position(4) <= 1
        return
    end

    padding = double(padding(:).');
    if numel(padding) == 1
        padding = repmat(padding, 1, 4);
    elseif numel(padding) < 4
        padding(4) = padding(end);
    end

    left = padding(1) / parent_position(3);
    bottom = padding(2) / parent_position(4);
    right = padding(3) / parent_position(3);
    top = padding(4) / parent_position(4);
    width = max(0.01, 1 - left - right);
    height = max(0.01, 1 - bottom - top);

    ax.Units = 'normalized';
    if isprop(ax, 'PositionConstraint')
        ax.PositionConstraint = 'outerposition';
    end
    if isprop(ax, 'DataAspectRatioMode')
        ax.DataAspectRatioMode = 'auto';
    end
    if isprop(ax, 'PlotBoxAspectRatioMode')
        ax.PlotBoxAspectRatioMode = 'auto';
    end
    ax.Position = [left, bottom, width, height];
    if isprop(ax, 'OuterPosition')
        ax.OuterPosition = [left, bottom, width, height];
    end
    if isprop(ax, 'InnerPosition')
        ax.InnerPosition = [left, bottom, width, height];
    end
catch
end
end
