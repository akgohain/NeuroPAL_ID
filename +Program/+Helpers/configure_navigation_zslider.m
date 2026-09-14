function configure_navigation_zslider(slider, n_slices, current_slice)
% Use the same slice ticks and appearance in both image views.
n_slices = max(1, round(double(n_slices)));
Program.Helpers.configure_slice_zslider(slider, n_slices, current_slice, false, []);
slider.MajorTicks = unique(round(linspace(1, n_slices, 6)), 'stable');
slider.MajorTickLabels = arrayfun(@(z) sprintf('%d', z), ...
    slider.MajorTicks, 'UniformOutput', false);
slider.MinorTicks = setdiff(1:n_slices, slider.MajorTicks);
slider.FontSize = 10;
slider.FontWeight = 'bold';
slider.Tooltip = 'Z slice';
end
