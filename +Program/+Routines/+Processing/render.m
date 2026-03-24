function render()
    app = Program.app;

    Program.Handlers.dialogue.step('Loading target chunk...');
    raw = Program.GUIHandling.get_active_volume(app, 'request', 'all');
    package = Program.Routines.Processing.compose_volume(app, raw);
    raw_dims = package.raw_dims;
    render_volume = package.render_volume;
    Program.Helpers.debug_event('ProcRender', ...
        'coords=%s state=%s raw_dims=%s padded_dims=%s threshold_pct=%g mip=%d flags=%s', ...
        mat2str(raw.coords), ...
        string(raw.state), ...
        mat2str(size(raw.array)), ...
        mat2str(raw_dims), ...
        app.ProcNoiseThresholdField.Value, ...
        app.ProcShowMIPCheckBox.Value, ...
        format_flags(app.flags));
    Program.Helpers.debug_array_summary('ProcRender', 'raw_array', raw.array);

    Program.Handlers.dialogue.step('Parsing channel data...');
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
    Program.Helpers.debug_event('ProcRender', ...
        'threshold_raw=%g applies globally to the combined displayed channels', package.threshold_raw);
    Program.Helpers.debug_array_summary('ProcRender', 'post_threshold', render_volume);
    Program.Helpers.debug_array_summary('ProcRender', 'post_normalize', render_volume);

    Program.GUIHandling.set_gui_limits(app, dims=raw_dims);
    Program.Handlers.dialogue.step('Drawing histograms...');
    Program.Handlers.histograms.draw();
    Program.GUIHandling.shorten_knob_labels(app);

    Program.Handlers.dialogue.step('Rendering volume data...');
    if app.ProcShowMIPCheckBox.Value
        frame = squeeze(max(render_volume, [], 3));
    else
        z_idx = min(max(round(z), 1), size(render_volume, 3));
        frame = squeeze(render_volume(:, :, z_idx, :));
    end
    Program.Helpers.debug_array_summary('ProcRender', 'frame', frame);
    log_main_parity(app, frame);

    % Ensure frame is displayable.
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

z_gui = round(app.ZSlider.Value);
z_data = z_gui;
if isfield(app.image_prefs, 'is_Z_flip') && app.image_prefs.is_Z_flip
    z_data = size(app.image_view, 3) - z_data + 1;
end

main_frame = squeeze(app.image_view(:, :, z_data, :));
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
