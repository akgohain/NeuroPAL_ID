function configure_main_zslider(app, n_slices, current_slice)
    % Configure the main z slider in integer slice coordinates.

    if nargin < 2 || isempty(n_slices)
        n_slices = size(app.image_data, 3);
    end
    if nargin < 3 || isempty(current_slice)
        current_slice = round((n_slices + 1) / 2);
    end

    n_slices = max(1, round(double(n_slices)));
    current_slice = min(max(round(double(current_slice)), 1), n_slices);

    Program.Helpers.configure_navigation_zslider(app.ZSlider, n_slices, current_slice);

    has_secondary_slider = ...
        (isstruct(app) && isfield(app, 'ZSliderS')) || ...
        (~isstruct(app) && isprop(app, 'ZSliderS'));
    if has_secondary_slider && ~isempty(app.ZSliderS) && isvalid(app.ZSliderS)
        Program.Helpers.configure_navigation_zslider(app.ZSliderS, n_slices, current_slice);
    end
end
