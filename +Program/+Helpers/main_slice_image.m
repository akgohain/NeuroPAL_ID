function [handle, configure_axes] = main_slice_image(ax, pixels, scale, reset_limits)
%MAIN_SLICE_IMAGE Reuse the slice image and clear its previous annotations.

if nargin < 4, reset_limits = false; end
key = 'main_slice_image';
handle = [];
if isappdata(ax, key)
    previous = getappdata(ax, key);
    if isgraphics(previous, 'image') && isequal(previous.Parent, ax)
        handle = previous;
    end
end

% Keep the base image while replacing the same visible overlays as cla.
children = ax.Children;
for i = 1:numel(children)
    if ~isequal(children(i), handle) && strcmp(children(i).HandleVisibility, 'on')
        delete(children(i));
    end
end

dims = size(pixels);
signature = {dims(1:2), double(scale(:).')};
geometry_key = 'main_slice_geometry';
configure_axes = reset_limits || isempty(handle) || ...
    ~isappdata(ax, geometry_key) || ...
    ~isequaln(getappdata(ax, geometry_key), signature);
if isempty(handle)
    handle = image(pixels, 'Parent', ax, 'Tag', 'main_slice_pixels');
    setappdata(ax, key, handle);
else
    handle.CData = pixels;
end
if configure_axes
    handle.XData = [1 dims(2)];
    handle.YData = [1 dims(1)];
    setappdata(ax, geometry_key, signature);
end
end
