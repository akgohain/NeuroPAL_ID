function render()
    app = Program.app;

    Program.Handlers.dialogue.step('Loading target chunk...');
    raw = Program.GUIHandling.get_active_volume(app, 'request', 'all');
    [raw_volume, raw_dims] = Program.Validation.pad_rgb(raw.array);
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
    
    % Determine the color channel indices.
    Program.Handlers.dialogue.step('Parsing channel data...');
    [r, g, b, white, dic, gfp, other] = Program.Handlers.channels.parse_channel_gui();
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
    
    % Determine the channel=color assignments for displaying.
    color_indices = [r.idx, g.idx, b.idx];
    
    % Draw the 3 color channels.
    render_volume = raw_volume(:, :, :, color_indices);

    % Remove unchecked color channels.
    rgb_channels = {r, g, b};
    rgb_names = {'red', 'green', 'blue'};
    for c = 1:3
        channel = rgb_channels{c};
        if ~channel.bool
            render_volume(:, :, :, c) = 0;
            continue
        end

        Program.Handlers.dialogue.step(sprintf('Computing %s channel...', rgb_names{c}));
        if ~is_neutral_window(channel.settings.low_high_in)
            render_volume(:, :, :, c) = imadjustn( ...
                render_volume(:, :, :, c), ...
                channel.settings.low_high_in, ...
                channel.settings.low_high_out, ...
                1);
        end
    end

    % Add in the white channel.
    if white.bool % White
        Program.Handlers.dialogue.step('Computing white channel...');

        % Compute the white channel.
        wchannel = raw_volume(:, : , :, white.idx);
    
        % Adjust the gamma.
        if white.settings.gamma ~= 1
            if white.settings.gamma < 0.01; white.settings.gamma = 1; end
            wchannel = imadjustn(wchannel, white.settings.low_high_in, white.settings.low_high_out, white.settings.gamma);
        end
    
        % Add the white channel.
        render_volume = render_volume + repmat(squeeze(wchannel), [1, 1, 1, 3]);
    end
    
    % Add in the DIC channel.
    if dic.bool % DIC
        Program.Handlers.dialogue.step('Computing DIC channel...');

        % Compute the DIC channel.
        dic_channel = raw_volume(:, :, :, dic.idx);
    
        % Adjust the gamma.
        if dic.settings.gamma ~= 1
            if dic.settings.gamma < 0.01; dic.settings.gamma = 1; end
            dic_channel = imadjustn(dic_channel, dic.settings.low_high_in, dic.settings.low_high_out, dic.settings.gamma);
        end
    
        % Add the DIC channel.
        render_volume = render_volume + repmat(squeeze(dic_channel), [1, 1, 1, 3]);
    end
    
    % Add in the GFP channel.
    if gfp.bool % GFP
        Program.Handlers.dialogue.step('Computing GFP channel...');
    
        % Compute the GFP channel.
        gfp_color = Program.GUIPreferences.instance().GFP_color;
        gfp_channel = raw_volume(:, :, :, gfp.idx);
    
        % Adjust the gamma.
        if gfp.settings.gamma ~= 1
            if gfp.settings.gamma < 0.01; gfp.settings.gamma = 1; end
            gfp_channel = imadjustn(gfp_channel, gfp.settings.low_high_in, gfp.settings.low_high_out, gfp.settings.gamma);
        end
    
        % Add the GFP channel.
        gfp_channel = repmat(squeeze(gfp_channel), [1, 1, 1, 3]);
        gfp_channel(:, :, :, ~gfp_color) = 0;
        render_volume = render_volume + gfp_channel;
    end

    for c=1:length(other)
        if other{c}.bool
            Program.Handlers.dialogue.step('Processing unknown channel...');

            other_channel = raw_volume(:, :, :, other{c}.idx);
            other_channel = repmat(squeeze(other_channel), [1, 1, 1, 3]);
            for rgb=1:3
                other_channel(:, :, :, rgb) = other_channel(:, :, :, rgb) * other{c}.color(rgb);
            end
            render_volume = render_volume + other_channel;
        end
    end

    threshold_raw = Program.GUIHandling.proc_threshold_raw_value(app, max(render_volume, [], 'all'));
    render_volume(render_volume < threshold_raw) = 0;
    Program.Helpers.debug_event('ProcRender', ...
        'threshold_raw=%g applies globally to the combined displayed channels', threshold_raw);
    Program.Helpers.debug_array_summary('ProcRender', 'post_threshold', render_volume);
    
    % Adjust the gamma.
    % Note: the image only shows RGB. We added the other channels
    % (W, DIC, GFP) to the RGB in order to show these as well.
    volume_max = double(max(render_volume, [], 'all'));
    if volume_max > 0
        render_volume = double(render_volume) / volume_max;
    else
        render_volume = zeros(size(render_volume), 'double');
    end

    for c = 1:3
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
    Program.Helpers.debug_array_summary('ProcRender', 'post_normalize', render_volume);

    % Apply processing operations.
    actions = fieldnames(app.flags);
    for a=1:length(actions)
        action = actions{a};
        if app.flags.(action) == 1
            msg = sprintf("Applying %s...", action);
            Program.Handlers.dialogue.step(msg)
            Program.Handlers.loading.start(msg);
            render_volume = Methods.ChunkyMethods.apply_vol(app, action, render_volume);
        end
    end

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

function tf = is_neutral_window(low_high_in)
tf = isempty(low_high_in);
if tf
    return
end

tf = numel(low_high_in) == 2 && all(abs(double(low_high_in(:)') - [0 1]) < 1e-9);
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
