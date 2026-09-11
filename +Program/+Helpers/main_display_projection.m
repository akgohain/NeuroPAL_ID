function projection = main_display_projection(app, as_volume)
%MAIN_DISPLAY_PROJECTION Return the current MIP without a rendered stack.
if nargin < 2
    as_volume = false;
end
Program.Helpers.get_current_display_slice(app, 'main');
view = Program.Helpers.main_display_view_cache(app);
if isempty(view)
    projection = [];
    return
end
projection = view.max_projection;
if as_volume
    projection = reshape(projection, size(projection, 1), size(projection, 2), 1, 3);
end
end
