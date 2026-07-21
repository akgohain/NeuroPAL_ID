function configure_video_controls(app)
%CONFIGURE_VIDEO_CONTROLS Configure bounded, readable video navigation.

if nargin < 1 || isempty(app) || ~isvalid(app) || ...
        ~isstruct(app.video_info) || ~isfield(app.video_info, 'nt')
    return
end

nt = max(1, round(double(app.video_info.nt)));
app.tSlider.Limits = [1 nt];
app.tSlider.Value = 1;
app.tEditField.Limits = [1 nt];
app.tEditField.Value = 1;

tick_count = min(7, nt);
ticks = unique(round(linspace(1, nt, tick_count)));
app.tSlider.MajorTicks = ticks;
if isprop(app.tSlider, 'MajorTickLabels')
    app.tSlider.MajorTickLabels = arrayfun(@num2str, ticks, 'UniformOutput', false);
end
app.tSlider.MinorTicks = [];

if ~isempty(app.ActivityAxes) && isvalid(app.ActivityAxes)
    activity_ticks = unique([0 ticks]);
    app.ActivityAxes.XTick = activity_ticks;
    app.ActivityAxes.XTickLabel = arrayfun(@num2str, activity_ticks, 'UniformOutput', false);
end

color_sliders = {app.RSlider, app.GSlider, app.BSlider};
for idx = 1:numel(color_sliders)
    slider = color_sliders{idx};
    slider.Limits = [0 10];
    slider.Value = 1;
    slider.MajorTicks = [];
    slider.MinorTicks = [];
end
end
