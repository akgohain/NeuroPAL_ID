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

    n_slices = max(1, round(double(n_slices)));
    current_slice = min(max(round(double(current_slice)), 1), n_slices);
    if n_slices <= 2
        major_ticks = 1:n_slices;
    else
        major_ticks = unique([1, round((n_slices + 1) / 2), n_slices], 'stable');
    end
    if isempty(label_values)
        tick_labels = arrayfun(@(z) sprintf('%d', z), major_ticks, 'UniformOutput', false);
    else
        tick_labels = arrayfun(@(z) sprintf('%.1f', double(label_values(z))), ...
            major_ticks, 'UniformOutput', false);
    end

    Program.Helpers.configure_slice_zslider( ...
        app.ZSlider, n_slices, current_slice, false, label_values);
    app.ZSlider.MajorTicks = major_ticks;
    if isprop(app.ZSlider, 'MajorTickLabels')
        app.ZSlider.MajorTickLabels = tick_labels;
    end
    if isprop(app.ZSlider, 'MinorTicks')
        app.ZSlider.MinorTicks = [];
    end
end
