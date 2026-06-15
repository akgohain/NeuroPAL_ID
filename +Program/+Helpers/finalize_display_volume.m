function render_volume = finalize_display_volume(render_volume, rgb_channels, threshold_raw, volume_max)
% Normalize a composed RGB volume onto the canonical uint8 display scale.

if nargin < 3 || isempty(threshold_raw)
    threshold_raw = 0;
end

if nargin < 4 || isempty(volume_max)
    volume_max = double(max(render_volume, [], 'all'));
else
    volume_max = double(volume_max);
end

if volume_max > 0
    render_volume = single(render_volume) ./ single(volume_max);
else
    render_volume = zeros(size(render_volume), 'single');
end

for c = 1:min(3, numel(rgb_channels))
    channel = rgb_channels{c};
    if ~channel.bool
        continue
    end

    gamma_value = channel.settings.gamma;
    if gamma_value < 0.01
        gamma_value = 1;
    end

    if gamma_value ~= 1
        render_volume(:, :, :, c) = imadjustn(render_volume(:, :, :, c), [], [], gamma_value);
    end
end

render_volume = Program.Helpers.to_user_uint8(render_volume);
if threshold_raw > 0
    render_volume(render_volume < threshold_raw) = 0;
end
end
