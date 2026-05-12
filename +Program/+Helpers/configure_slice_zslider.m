function configure_slice_zslider(slider, n_slices, current_slice, show_labels, label_values)
    % Configure a z slider with integer slice ticks.

    if nargin < 4 || isempty(show_labels)
        show_labels = true;
    end
    if nargin < 5
        label_values = [];
    end

    n_slices = max(1, round(double(n_slices)));
    current_slice = min(max(round(double(current_slice)), 1), n_slices);

    if n_slices == 1
        slider.Limits = [1, 2];
        slider.MajorTicks = 1;
        slider.MinorTicks = [];
        slider.Value = 1;
        if isprop(slider, 'MajorTickLabels')
            if show_labels
                slider.MajorTickLabels = {'1'};
            else
                slider.MajorTickLabels = {''};
            end
        end
        if isprop(slider, 'Enable')
            slider.Enable = 'off';
        end
        return
    end

    if isprop(slider, 'Enable')
        slider.Enable = 'on';
    end

    if n_slices <= 8
        major_ticks = 1:n_slices;
    elseif ~isempty(label_values) && isnumeric(label_values) && numel(label_values) >= n_slices
        major_ticks = local_major_ticks_from_labels(label_values, n_slices, 8);
    else
        max_labels = 8;
        major_ticks = unique(round(linspace(1, n_slices, max_labels)));
    end

    slider.Limits = [1, n_slices];
    slider.MajorTicks = major_ticks;
    slider.MinorTicks = [];
    slider.Value = current_slice;

    if isprop(slider, 'MajorTickLabels')
        if show_labels
            slider.MajorTickLabels = local_tick_labels(major_ticks, label_values, n_slices);
        else
            slider.MajorTickLabels = repmat({''}, 1, numel(major_ticks));
        end
    end
end

function major_ticks = local_major_ticks_from_labels(label_values, n_slices, max_labels)
label_values = double(label_values(:).');
label_values = label_values(1:n_slices);
label_min = label_values(1);
label_max = label_values(end);

if ~all(isfinite([label_min, label_max])) || label_max <= label_min
    major_ticks = unique(round(linspace(1, n_slices, max_labels)));
    return
end

step = local_nice_step((label_max - label_min) / max(1, max_labels - 1));
tick_values = label_min:step:label_max;
if isempty(tick_values) || abs(tick_values(end) - label_max) > step * 0.25
    tick_values(end + 1) = label_max;
end

major_ticks = arrayfun(@(value) local_nearest_label_index(label_values, value), tick_values);
major_ticks = unique([major_ticks, 1, n_slices], 'stable');
end

function step = local_nice_step(raw_step)
if ~isfinite(raw_step) || raw_step <= 0
    step = 1;
    return
end

base = 10 ^ floor(log10(raw_step));
candidates = [1, 2, 2.5, 5, 10] * base;
idx = find(candidates >= raw_step, 1, 'first');
if isempty(idx)
    step = candidates(end);
else
    step = candidates(idx);
end
end

function idx = local_nearest_label_index(label_values, value)
[~, idx] = min(abs(label_values - value));
end

function labels = local_tick_labels(major_ticks, label_values, n_slices)
if ~isempty(label_values) && isnumeric(label_values) && numel(label_values) >= n_slices
    labels = arrayfun(@(z) sprintf('%.1f', double(label_values(z))), ...
        major_ticks, 'UniformOutput', false);
else
    labels = arrayfun(@(z) sprintf('%d', z), major_ticks, ...
        'UniformOutput', false);
end
end
