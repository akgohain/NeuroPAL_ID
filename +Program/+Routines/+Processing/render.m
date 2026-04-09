function render()
    app = Program.app;
    Program.GUIHandling.ensure_processing_color_ui(app);
    Program.GUIHandling.update_processing_zslider_visibility(app);

    [~, package, ~, raw_cache_hit] = local_get_cached_payload(app);
    render_volume = package.render_volume;
    render_dims = local_volume_dims(render_volume);

    r = package.channels.r;
    g = package.channels.g;
    b = package.channels.b;
    white = package.channels.white;
    dic = package.channels.dic;
    gfp = package.channels.gfp;
    [x, y, z, t] = Program.Routines.Processing.parse_gui();
    view_reset_required = local_processing_view_reset_required(app, render_dims);
    if ~raw_cache_hit || view_reset_required
        Program.GUIHandling.set_gui_limits(app, 'soft', render_dims);
    end

    if local_histograms_need_redraw(app)
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
    cla(app.proc_xyAxes);
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
    local_set_axis_limits(app.proc_xyAxes, size(frame, 2), size(frame, 1));

    if app.ProcPreviewZslowCheckBox.Value
        [row_idx, col_idx] = local_cross_section_indices(app, render_volume);
        xz_frame = flipud(rot90(squeeze(render_volume(row_idx, :, :, :, :))));
        yz_frame = squeeze(render_volume(:, col_idx, :, :, :));
        cla(app.proc_xzAxes);
        cla(app.proc_yzAxes);
        image(xz_frame, 'Parent', app.proc_xzAxes);
        image(yz_frame, 'Parent', app.proc_yzAxes);
        local_set_axis_limits(app.proc_xzAxes, size(xz_frame, 2), size(xz_frame, 1));
        local_set_axis_limits(app.proc_yzAxes, size(yz_frame, 2), size(yz_frame, 1));
    end
end

function dims = local_volume_dims(volume)
dims = size(volume);
if numel(dims) < 4
    dims(4) = 1;
end
end

function tf = local_processing_view_reset_required(app, dims)
tf = true;
key = 'proc_render_view_dims';

if isappdata(app.CELL_ID, key)
    previous_dims = getappdata(app.CELL_ID, key);
    tf = ~isequal(previous_dims, dims);
end

setappdata(app.CELL_ID, key, dims);
if tf
    return
end

tf = local_axes_out_of_bounds(app.proc_xyAxes, dims(2), dims(1));

if ~tf && app.ProcPreviewZslowCheckBox.Value
    tf = local_axes_out_of_bounds(app.proc_xzAxes, dims(2), dims(3)) || ...
        local_axes_out_of_bounds(app.proc_yzAxes, dims(3), dims(1));
end
end

function tf = local_axes_out_of_bounds(ax, nx, ny)
tf = true;
if isempty(ax) || ~isvalid(ax)
    return
end

xlim = ax.XLim;
ylim = ax.YLim;

tf = any(~isfinite([xlim ylim])) || ...
    xlim(1) < 1 || ylim(1) < 1 || ...
    xlim(2) > nx || ylim(2) > ny || ...
    diff(xlim) <= 0 || diff(ylim) <= 0;
end

function local_set_axis_limits(ax, nx, ny)
if isempty(ax) || ~isvalid(ax)
    return
end

ax.XLim = [1, max(1, nx)];
ax.YLim = [1, max(1, ny)];
end

function [row_idx, col_idx] = local_cross_section_indices(app, render_volume)
row_idx = min(max(round(app.proc_ySlider.Value), 1), size(render_volume, 1));
col_idx = min(max(round(app.proc_xSlider.Value), 1), size(render_volume, 2));
end

function [raw, package, cache_hit, raw_cache_hit] = local_get_cached_payload(app)
cache_hit = false;
raw_cache_hit = false;
cache_key = Program.Helpers.processing_render_signature(app);
use_cache = strcmp(app.VolumeDropDown.Value, 'Colormap');

if use_cache && isappdata(app.CELL_ID, 'proc_render_cache')
    cache = getappdata(app.CELL_ID, 'proc_render_cache');
    if isstruct(cache) && isfield(cache, 'signature') && strcmp(cache.signature, cache_key)
        raw = cache.raw;
        package = cache.package;
        cache_hit = true;
        raw_cache_hit = true;
        return
    end
end

if use_cache
    [raw, raw_cache_hit] = local_get_cached_raw_payload(app);
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

function [raw, cache_hit] = local_get_cached_raw_payload(app)
cache_hit = false;
raw_key = Program.Helpers.processing_raw_signature(app);
if isappdata(app.CELL_ID, 'proc_raw_cache')
    cache = getappdata(app.CELL_ID, 'proc_raw_cache');
    if isstruct(cache) && isfield(cache, 'signature') && strcmp(cache.signature, raw_key)
        raw = cache.raw;
        cache_hit = true;
        return
    end
end

raw = local_get_full_colormap_payload(app);
setappdata(app.CELL_ID, 'proc_raw_cache', struct( ...
    'signature', raw_key, ...
    'raw', raw));
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

function tf = local_histograms_need_redraw(app)
signature = Program.Helpers.processing_histogram_signature(app);
if isappdata(app.CELL_ID, 'proc_histogram_signature')
    cached_signature = getappdata(app.CELL_ID, 'proc_histogram_signature');
    if ischar(cached_signature) || isstring(cached_signature)
        tf = ~strcmp(char(cached_signature), signature);
    else
        tf = true;
    end
else
    tf = true;
end

if tf
    setappdata(app.CELL_ID, 'proc_histogram_signature', signature);
end
end
