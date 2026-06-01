function configure_image_axes_ticks(ax, dims, scale_xy, varargin)
% Configure readable physical-unit tick labels for image display axes.

if nargin < 1 || isempty(ax) || ~isvalid(ax)
    return
end

if nargin < 2 || isempty(dims)
    dims = [1 1];
end
dims = double(dims(:).');
if numel(dims) < 2
    dims(2) = dims(1);
end

if nargin < 3 || isempty(scale_xy)
    scale_xy = [1 1];
end
scale_xy = double(scale_xy(:).');
if numel(scale_xy) < 2
    scale_xy(2) = scale_xy(1);
end
scale_xy(~isfinite(scale_xy) | scale_xy <= 0) = 1;

opts = local_options(varargin{:});
nx = max(1, dims(2));
ny = max(1, dims(1));

if isempty(opts.XLim)
    xlim = ax.XLim;
    if any(~isfinite(xlim)) || diff(xlim) <= 0
        xlim = [1 nx];
    end
else
    xlim = double(opts.XLim);
    ax.XLim = xlim;
end

if isempty(opts.YLim)
    ylim = ax.YLim;
    if any(~isfinite(ylim)) || diff(ylim) <= 0
        ylim = [1 ny];
    end
else
    ylim = double(opts.YLim);
    ax.YLim = ylim;
end

[x_ticks, x_labels] = local_axis_ticks(xlim, scale_xy(1), opts.TargetXTicks, false);
[y_ticks, y_labels] = local_axis_ticks(ylim, scale_xy(2), opts.TargetYTicks, true);

ax.XTick = x_ticks;
ax.XTickLabel = x_labels;
ax.YTick = y_ticks;
ax.YTickLabel = y_labels;
ax.XTickLabelRotation = 0;
ax.YTickLabelRotation = 0;
ax.TickDir = 'out';
ax.Box = 'on';
end

function opts = local_options(varargin)
opts = struct( ...
    'XLim', [], ...
    'YLim', [], ...
    'TargetXTicks', 9, ...
    'TargetYTicks', 6);

if mod(numel(varargin), 2) ~= 0
    return
end

for k = 1:2:numel(varargin)
    name = char(string(varargin{k}));
    if isfield(opts, name)
        opts.(name) = varargin{k + 1};
    end
end
end

function [ticks, labels] = local_axis_ticks(limits, scale, target_count, invert_origin)
limits = sort(double(limits));
span_units = max(0, diff(limits) * scale);
if span_units <= 0
    ticks = limits(1);
    labels = {'0'};
    return
end

target_count = max(2, round(double(target_count)));
step = local_nice_step(span_units / max(1, target_count - 1));
values = 0:step:span_units;
if isempty(values)
    values = 0;
end

if invert_origin
    ticks = limits(2) - values ./ scale;
    keep = ticks >= limits(1) - eps(limits(1)) & ticks <= limits(2) + eps(limits(2));
    ticks = ticks(keep);
    values = values(keep);
    ticks = fliplr(ticks);
    values = fliplr(values);
else
    ticks = limits(1) + values ./ scale;
    keep = ticks >= limits(1) - eps(limits(1)) & ticks <= limits(2) + eps(limits(2));
    ticks = ticks(keep);
    values = values(keep);
end

if isempty(ticks)
    ticks = limits(1);
    values = 0;
end

labels = arrayfun(@local_format_tick, values, 'UniformOutput', false);
end

function step = local_nice_step(raw_step)
if ~isfinite(raw_step) || raw_step <= 0
    step = 1;
    return
end

base = 10 ^ floor(log10(raw_step));
candidates = [1 2 2.5 5 10] * base;
idx = find(candidates >= raw_step, 1, 'first');
if isempty(idx)
    step = candidates(end);
else
    step = candidates(idx);
end
end

function label = local_format_tick(value)
if abs(value) < 1e-10
    value = 0;
end

if abs(value - round(value)) < 1e-8
    label = sprintf('%.0f', value);
else
    label = regexprep(sprintf('%.4g', value), '\.?0+$', '');
end
end
