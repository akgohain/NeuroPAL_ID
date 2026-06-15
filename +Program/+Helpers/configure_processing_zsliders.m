function configure_processing_zsliders(app, n_slices, current_slice)
    % Configure processing-tab z sliders with physical z tick spacing.

    if nargin < 2 || isempty(n_slices)
        n_slices = max(1, round(double(app.proc_zSlider.Limits(2))));
    end
    if nargin < 3 || isempty(current_slice)
        current_slice = min(max(round(double(app.proc_zSlider.Value)), 1), n_slices);
    end

    label_values = local_z_label_values(app, n_slices);

    Program.Helpers.configure_slice_zslider(app.proc_zSlider, n_slices, current_slice, true, label_values);
    Program.Helpers.configure_slice_zslider(app.proc_hor_zSlider, n_slices, current_slice, false, label_values);
    Program.Helpers.configure_slice_zslider(app.proc_vert_zSlider, n_slices, current_slice, false, label_values);

    minor_ticks = local_minor_ticks(n_slices, label_values, app.proc_zSlider.MajorTicks);
    if isprop(app.proc_zSlider, 'MinorTicks')
        app.proc_zSlider.MinorTicks = minor_ticks;
    end
    if isprop(app.proc_hor_zSlider, 'MinorTicks')
        app.proc_hor_zSlider.MinorTicks = minor_ticks;
    end
    if isprop(app.proc_vert_zSlider, 'MinorTicks')
        app.proc_vert_zSlider.MinorTicks = minor_ticks;
    end

    app.proc_zEditField.Value = current_slice;
    Program.Helpers.render_processing_zticklabels(app);
end

function label_values = local_z_label_values(app, n_slices)
label_values = [];
try
    z_scale = double(app.image_um_scale(3));
    if isfinite(z_scale) && z_scale > 0
        label_values = ((1:n_slices) - 1) * z_scale;
    end
catch
end
end

function minor_ticks = local_minor_ticks(n_slices, label_values, major_ticks)
minor_ticks = [];

if ~isempty(label_values) && isnumeric(label_values) && numel(label_values) >= n_slices
    label_values = double(label_values(:).');
    label_values = label_values(1:n_slices);
    if all(isfinite(label_values)) && label_values(end) > label_values(1)
        unit_values = ceil(label_values(1)):floor(label_values(end));
        minor_ticks = interp1(label_values, 1:n_slices, unit_values, 'linear');
        minor_ticks = minor_ticks(isfinite(minor_ticks) & minor_ticks >= 1 & minor_ticks <= n_slices);
        minor_ticks = local_remove_major_ticks(minor_ticks, major_ticks);
        return
    end
end

minor_ticks = setdiff(1:n_slices, major_ticks);
end

function minor_ticks = local_remove_major_ticks(minor_ticks, major_ticks)
if isempty(minor_ticks) || isempty(major_ticks)
    return
end

keep = true(size(minor_ticks));
for n = 1:numel(major_ticks)
    keep = keep & abs(minor_ticks - major_ticks(n)) > 1e-6;
end
minor_ticks = minor_ticks(keep);
end
