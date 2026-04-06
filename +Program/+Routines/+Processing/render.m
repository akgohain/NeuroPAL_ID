function render()
    app = Program.app;
    Program.GUIHandling.update_processing_zslider_visibility(app);

    [raw, package, cache_hit] = local_get_cached_payload(app);
    raw_dims = package.raw_dims;
    render_volume = package.render_volume;

    Program.Helpers.debug_event('ProcRender', ...
        'coords=%s state=%s raw_dims=%s padded_dims=%s threshold_raw=%g mip=%d cache_hit=%d flags=%s', ...
        mat2str(raw.coords), ...
        string(raw.state), ...
        mat2str(size(raw.array)), ...
        mat2str(raw_dims), ...
        package.threshold_raw, ...
        app.ProcShowMIPCheckBox.Value, ...
        cache_hit, ...
        format_flags(app.flags));
    if ~cache_hit
        Program.Helpers.debug_array_summary('ProcRender', 'raw_array', raw.array);
    end

    r = package.channels.r;
    g = package.channels.g;
    b = package.channels.b;
    white = package.channels.white;
    dic = package.channels.dic;
    gfp = package.channels.gfp;
    [x, y, z, t] = Program.Routines.Processing.parse_gui();
    Program.Helpers.debug_event('ProcRender', ...
        ['channels rgb=[%d %d %d] w=%d dic=%d gfp=%d checks=%s ' ...
         'rgb_gamma=%s white_gamma=%g dic_gamma=%g gfp_gamma=%g'], ...
        r.idx, g.idx, b.idx, white.idx, dic.idx, gfp.idx, ...
        mat2str([r.bool g.bool b.bool white.bool dic.bool gfp.bool]), ...
        mat2str([r.settings.gamma g.settings.gamma b.settings.gamma]), ...
        white.settings.gamma, dic.settings.gamma, gfp.settings.gamma);
    Program.Helpers.debug_event('ProcRender', ...
        'windows r=%s g=%s b=%s coords=[x=%d y=%d z=%d t=%d]', ...
        mat2str(r.settings.low_high_in), ...
        mat2str(g.settings.low_high_in), ...
        mat2str(b.settings.low_high_in), ...
        x, y, z, t);

    if ~cache_hit
        Program.GUIHandling.set_gui_limits(app, dims=raw_dims);
        Program.Handlers.dialogue.step('Drawing histograms...');
        Program.Handlers.histograms.draw();
        Program.GUIHandling.shorten_knob_labels(app);
    end

    Program.Handlers.dialogue.step('Rendering volume data...');
    if app.ProcShowMIPCheckBox.Value
        frame = squeeze(max(render_volume, [], 3));
    else
        [frame, z, ~] = Program.Helpers.get_current_display_slice(app, 'processing', render_volume);
    end
    Program.Helpers.debug_array_summary('ProcRender', 'frame', frame);
    log_main_parity(app, frame);

    if ndims(frame) == 2
        image(frame, 'Parent', app.proc_xyAxes);
    elseif ndims(frame) == 3
        if size(frame, 3) >= 3
            if size(frame, 3) > 3
                frame = frame(:, :, 1:3);
            end
            image(frame, 'Parent', app.proc_xyAxes);
        else
            msg = sprintf('Processing render: unexpected frame size %s', mat2str(size(frame)));
            fprintf('%s\n', msg);
            try
                app.logEvent('Processing', msg, 0);
            catch
            end
            error('Processing render: invalid frame size %s', mat2str(size(frame)));
        end
    else
        msg = sprintf('Processing render: unexpected frame size %s', mat2str(size(frame)));
        fprintf('%s\n', msg);
        try
            app.logEvent('Processing', msg, 0);
        catch
        end
        error('Processing render: invalid frame size %s', mat2str(size(frame)));
    end

    if app.ProcPreviewZslowCheckBox.Value
        image(flipud(rot90(squeeze(render_volume(x, :, :, :, :)))), 'Parent', app.proc_xzAxes);
        image(squeeze(render_volume(:, y, :, :, :)), 'Parent', app.proc_yzAxes);
    end
end

function [raw, package, cache_hit] = local_get_cached_payload(app)
cache_hit = false;
cache_key = Program.Helpers.processing_render_signature(app);
use_cache = strcmp(app.VolumeDropDown.Value, 'Colormap');

if use_cache && isappdata(app.CELL_ID, 'proc_render_cache')
    cache = getappdata(app.CELL_ID, 'proc_render_cache');
    if isstruct(cache) && isfield(cache, 'signature') && strcmp(cache.signature, cache_key)
        raw = cache.raw;
        package = cache.package;
        cache_hit = true;
        return
    end
end

if use_cache
    raw = local_get_full_colormap_payload(app);
else
    raw = Program.GUIHandling.get_active_volume(app, 'request', 'all');
end
package = Program.Routines.Processing.compose_volume(app, raw);
if use_cache
    setappdata(app.CELL_ID, 'proc_render_cache', struct( ...
        'signature', cache_key, ...
        'raw', raw, ...
        'package', package));
end
end

function raw = local_get_full_colormap_payload(app)
state = Program.Handlers.channels.processing_state(app);
max_idx = state.max_source_idx;
if max_idx < 1
    dims = size(app.proc_image, 'data');
    array = zeros(dims(1), dims(2), dims(3), 1, class(app.proc_image.data(1,1,1,1)));
else
    array = app.proc_image.data(:, :, :, 1:max_idx);
end
if ndims(array) == 3
    array = reshape(array, size(array,1), size(array,2), size(array,3), 1);
end
raw = struct( ...
    'state', 'colormap', ...
    'dims', size(array), ...
    'array', array, ...
    'coords', [app.proc_xSlider.Value, app.proc_ySlider.Value, app.proc_zSlider.Value, app.proc_tSlider.Value]);
end

function out = format_flags(flags)
names = fieldnames(flags);
if isempty(names)
    out = '[]';
    return
end

parts = cell(1, numel(names));
for k = 1:numel(names)
    value = flags.(names{k});
    if isnumeric(value) || islogical(value)
        value_str = mat2str(value);
    else
        value_str = char(string(value));
    end
    parts{k} = sprintf('%s=%s', names{k}, value_str);
end
out = strjoin(parts, ',');
end

function log_main_parity(app, frame)
if ~Program.Helpers.debug_enabled()
    return
end

if isempty(app.image_view)
    Program.Helpers.debug_event('ProcParity', 'Skipped: main image_view is empty');
    return
end

z_gui = Program.Helpers.gui_z_to_data_index(app.ZSlider.Value, size(app.image_view, 3), false);
z_data = Program.Helpers.gui_z_to_data_index(z_gui, size(app.image_view, 3), ...
    isfield(app.image_prefs, 'is_Z_flip') && app.image_prefs.is_Z_flip);

[main_frame, ~, ~] = Program.Helpers.get_current_display_slice(app, 'main', app.image_view);
if ~isequal(size(main_frame), size(frame))
    Program.Helpers.debug_event('ProcParity', ...
        'Skipped: main frame size %s ~= processing frame size %s', ...
        mat2str(size(main_frame)), mat2str(size(frame)));
    return
end

diff_frame = abs(double(main_frame) - double(frame));
Program.Helpers.debug_event('ProcParity', ...
    'z_gui=%d z_data=%d mean_abs_diff=%g max_abs_diff=%g', ...
    z_gui, z_data, mean(diff_frame(:)), max(diff_frame(:)));
Program.Helpers.debug_array_summary('ProcParity', 'main_frame', main_frame);
Program.Helpers.debug_array_summary('ProcParity', 'diff_frame', diff_frame);
end
