function configure_main_zslider(app, n_slices, current_slice)
    % Configure the main z slider with sparse physical z labels.

    if nargin < 2 || isempty(n_slices)
        n_slices = size(app.image_data, 3);
    end
    if nargin < 3 || isempty(current_slice)
        current_slice = round((n_slices + 1) / 2);
    end

    label_values = [];
    try
        z_scale = double(app.image_um_scale(3));
        if isfinite(z_scale) && z_scale > 0
            label_values = ((1:n_slices) - 1) * z_scale;
        end
    catch
    end

    Program.Helpers.configure_slice_zslider( ...
        app.ZSlider, n_slices, current_slice, true, label_values);
end
