function scale_xy = processing_axis_scale(app, plane)
% Return x/y display scale for an Image Processing view plane.

if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 2 || strlength(string(plane)) == 0
    plane = "xy";
end

scale3 = [1 1 1];
try
    if strcmpi(char(string(app.VolumeDropDown.Value)), 'Colormap')
        scale3 = double(app.image_um_scale(:).');
    elseif isstruct(app.video_info) && isfield(app.video_info, 'scale')
        scale3 = double(app.video_info.scale(:).');
    end
catch
end
if numel(scale3) < 3
    scale3(end+1:3) = 1;
end
scale3(~isfinite(scale3) | scale3 <= 0) = 1;

switch lower(string(plane))
    case "xz"
        scale_xy = [scale3(1), scale3(3)];
    case "yz"
        scale_xy = [scale3(3), scale3(2)];
    otherwise
        scale_xy = scale3(1:2);
end
end
