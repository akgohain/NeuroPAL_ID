function configure_processing_zsliders(app, n_slices, current_slice)
    % Keep processing controls in slice coordinates.
    if nargin < 2 || isempty(n_slices)
        n_slices = max(1, round(double(app.proc_zSlider.Limits(2))));
    end
    if nargin < 3 || isempty(current_slice)
        current_slice = app.proc_zSlider.Value;
    end
    n_slices = max(1, round(double(n_slices)));
    current_slice = min(max(round(double(current_slice)), 1), n_slices);
    sliders = {app.proc_zSlider, app.proc_hor_zSlider, app.proc_vert_zSlider};
    for k = 1:numel(sliders)
        Program.Helpers.configure_slice_zslider(sliders{k}, n_slices, current_slice, k == 1, []);
        sliders{k}.Tooltip = 'Z slice';
    end
    app.proc_vert_zSlider.Value = sum(app.proc_vert_zSlider.Limits) - current_slice;
    app.proc_zEditField.Value = current_slice;
    Program.Helpers.render_processing_zticklabels(app);
end
