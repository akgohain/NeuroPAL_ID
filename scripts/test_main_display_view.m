function test_main_display_view()
%TEST_MAIN_DISPLAY_VIEW Verify bounded rendering against the full-volume baseline.

repo_root = fileparts(fileparts(mfilename('fullpath')));
fixture_dir = fullfile(repo_root, 'scripts', 'fixtures');
original_path = path;
addpath(fixture_dir);
path_cleanup = onCleanup(@() path(original_path));
original_rng = rng;
rng_cleanup = onCleanup(@() rng(original_rng));
rng(17);
prefs = Program.GUIPreferences.instance();
original_gfp = prefs.GFP_color;
prefs_cleanup = onCleanup(@() local_restore_gfp(prefs, original_gfp));
prefs.GFP_color = [1 1 0];

channels = local_channels();
raw = randi([0 255], 8, 9, 5, 6, 'uint8');
fixtures = {raw, uint16(raw) .* uint16(15), ...
    uint16(raw) .* uint16(255), single(raw) ./ 255, ...
    single(raw) - 90, zeros(size(raw), 'uint8')};
for fixture_idx = 1:numel(fixtures)
    for threshold = [0 30]
        volume = fixtures{fixture_idx};
        [expected_volume, expected_mip] = local_baseline(volume, channels, threshold);
        view = [];
        for flipped = [false true]
            for z_gui = 1:size(volume, 3)
                view = Program.Helpers.compose_main_display_view( ...
                    volume, channels, z_gui, flipped, 'fixture', view, threshold);
                z_data = Program.Helpers.gui_z_to_data_index(z_gui, size(volume, 3), flipped);
                expected_slice = reshape(expected_volume(:, :, z_data, :), 8, 9, 3);
                assert(isequal(view.display_slice, expected_slice), ...
                    'Current-plane parity failed for fixture %d, z=%d.', fixture_idx, z_gui);
                assert(isequal(view.max_projection, expected_mip), 'Projection parity failed.');
                assert(~isfield(view, 'render_volume'), 'The cache must not retain a rendered stack.');
                assert(isa(view.display_slice, 'uint8') && isa(view.max_projection, 'uint8'));
                assert(view.z_data == z_data && view.is_z_flip == flipped);
            end
        end
    end
end

% Changing only Z composes one plane; a repeated request composes none.
view = Program.Helpers.compose_main_display_view(raw, channels, 1, false, 'a');
assert(view.composed_slices == size(raw, 3) && ~view.projection_cache_hit);
next = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'a', view);
assert(next.projection_cache_hit && ~next.slice_cache_hit && next.composed_slices == 1);
same = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'a', next);
assert(same.projection_cache_hit && same.slice_cache_hit && same.composed_slices == 0);

% Revisions, same-size source replacement, channel settings and GFP tint all
% invalidate the projection. Flip changes selection, not source pixels.
changed = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'b', same);
assert(~changed.projection_cache_hit);
channels.r.settings.gamma = 1.7;
changed = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'a', same);
assert(~changed.projection_cache_hit);
prefs.GFP_color = [0 1 0];
changed_tint = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'a', changed);
assert(~changed_tint.projection_cache_hit);
channels.r.idx = 2;
changed_mapping = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'a', changed_tint);
assert(~changed_mapping.projection_cache_hit);
channels.r.settings.low_high_in = [0.2 0.8];
changed_window = Program.Helpers.compose_main_display_view(raw, channels, 3, false, 'a', changed_mapping);
assert(~changed_window.projection_cache_hit);

% The pixel payload stays constant as Z increases.
short = Program.Helpers.compose_main_display_view(raw, channels, 1, false, 'short');
tall = Program.Helpers.compose_main_display_view(repmat(raw, 1, 1, 10, 1), channels, 1, false, 'tall');
short_bytes = whos('short');
tall_bytes = whos('tall');
assert(tall_bytes.bytes <= short_bytes.bytes + 1024, 'Display cache grew with stack depth.');

names = {'r', 'g', 'b', 'white', 'dic', 'gfp'};
for n = 1:numel(names)
    channels.(names{n}).bool = false;
end
black = Program.Helpers.compose_main_display_view(raw, channels, 1, false, 'black');
assert(~any(black.display_slice(:)) && ~any(black.max_projection(:)));
assert(isempty(Program.Helpers.compose_main_display_view([], channels, 1, false, 'empty')));

local_test_app_cache(raw);
fprintf('MAIN_DISPLAY_VIEW=PASS (pixel parity, bounded cache, invalidation, navigation)\n');
end

function local_test_app_cache(raw)
app = MainDisplayTestApp();
cleanup = onCleanup(@() delete(app));
app.image_data = raw;
first = Program.Helpers.render_main_display_view(app, 1);
Program.Helpers.main_display_view_cache(app, first);
assert(isstruct(app.image_view) && ~isfield(app.image_view, 'render_volume'));
app.ZSlider.Value = 4;
[frame, z_gui, z_data] = Program.Helpers.get_current_display_slice(app, 'main', app.image_view);
assert(z_gui == 4 && z_data == 4 && isequal(frame, app.image_view.display_slice));
assert(app.image_view.projection_cache_hit && app.image_view.composed_slices == 1);

app.image_file = 'fixture-b.mat';
replacement = Program.Helpers.render_main_display_view(app, 4, app.image_view);
assert(~replacement.projection_cache_hit, 'Same-size sources must not share a projection.');
Program.Helpers.main_display_view_cache(app, replacement);
app.image_data(1, 1, 1, 1) = bitxor(app.image_data(1, 1, 1, 1), uint8(255));
Program.Helpers.main_display_view_cache(app, []);
assert(isempty(app.image_view) && isempty(Program.Helpers.main_display_view_cache(app)));
after_edit = Program.Helpers.render_main_display_view(app, 4, replacement);
assert(~after_edit.projection_cache_hit, 'Invalidation must reject even a retained old cache struct.');
[expected_volume, expected_mip] = local_baseline(app.image_data, after_edit.channels, 0);
assert(isequal(after_edit.max_projection, expected_mip));
assert(isequal(after_edit.display_slice, reshape(expected_volume(:, :, 4, :), 8, 9, 3)));

Program.Helpers.main_display_view_cache(app, after_edit);
app.image_prefs.is_Z_flip = true;
app.ZSlider.Value = 1;
[~, ~, z_data] = Program.Helpers.get_current_display_slice(app, 'main', app.image_view);
assert(z_data == size(raw, 3) && app.image_view.projection_cache_hit);
app.image_gamma(1) = 0.5;
Program.Helpers.get_current_display_slice(app, 'main', app.image_view);
assert(~app.image_view.projection_cache_hit, 'Gamma changes must invalidate a same-Z request.');
app.image_data = [];
assert(isempty(Program.Helpers.get_current_display_slice(app, 'main', app.image_view)));
assert(isempty(app.image_view));
end

function channels = local_channels()
names = {'r', 'g', 'b', 'white', 'dic', 'gfp'};
gammas = [0.8 1.4 2 0.6 1.1 0.9];
channels = struct();
for c = 1:numel(names)
    channels.(names{c}) = struct('idx', c, 'bool', true, ...
        'settings', struct('gamma', gammas(c), ...
            'low_high_in', [0.05 0.9], 'low_high_out', [0.1 0.95]));
end
channels.other = {};
end

function [render_volume, max_projection] = local_baseline(raw_volume, channels, threshold_raw)
% Freeze the former render_main_display_view algorithm as the parity oracle.
z_count = size(raw_volume, 3);
render_volume = zeros(size(raw_volume, 1), size(raw_volume, 2), z_count, 3, 'single');
max_projection = [];
volume_max = 0;
for z = 1:z_count
    raw_slice = reshape(raw_volume(:, :, z, :), size(raw_volume, 1), size(raw_volume, 2), 1, size(raw_volume, 4));
    [slice_rgb, rgb_channels] = Program.Helpers.compose_display_volume(raw_slice, channels);
    render_volume(:, :, z, :) = slice_rgb;
    if isempty(max_projection)
        max_projection = slice_rgb;
    else
        max_projection = max(max_projection, slice_rgb);
    end
    volume_max = max(volume_max, double(max(slice_rgb, [], 'all')));
end
render_volume = Program.Helpers.finalize_display_volume(render_volume, rgb_channels, threshold_raw, volume_max);
max_projection = Program.Helpers.finalize_display_volume(max_projection, rgb_channels, threshold_raw, volume_max);
max_projection = reshape(max_projection, size(raw_volume, 1), size(raw_volume, 2), 3);
end

function local_restore_gfp(prefs, color)
prefs.GFP_color = color;
end
