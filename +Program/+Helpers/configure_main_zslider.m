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

    if n_slices == 1
        major_ticks = 1:n_slices;
        minor_ticks = [];
    else
        major_ticks = unique(round(linspace(1, n_slices, 6)), 'stable');
        minor_ticks = setdiff(1:n_slices, major_ticks);
    end
    tick_labels = arrayfun(@(z) sprintf('%d', z), major_ticks, 'UniformOutput', false);

    Program.Helpers.configure_slice_zslider( ...
        app.ZSlider, n_slices, current_slice, false, []);
    app.ZSlider.MajorTicks = major_ticks;
    if isprop(app.ZSlider, 'MajorTickLabels')
        app.ZSlider.MajorTickLabels = tick_labels;
    end
    if isprop(app.ZSlider, 'MinorTicks')
        app.ZSlider.MinorTicks = minor_ticks;
    end
end
