classdef ChunkyMethods
    % Processing functions that support lazy read/write.

    %% Public variables.
    properties (Access = public)
    end

    methods (Static)

        function [new_dims, og_dims] = calc_pp_size(app, action, vol)
            % Calculate the post-processing dimensions of a volume.

            if isa(vol, 'matlab.io.MatFile')
                og_dims = size(vol, 'data');
            else
                og_dims = size(vol);
            end

            switch action
                case 'crop'
                    rotated_mask = imrotate(app.rotation_stack.cache.(app.VolumeDropDown.Value).mask, app.rotation_stack.cache.(app.VolumeDropDown.Value).angle);
                    nonzero_rows = squeeze(any(any(rotated_mask, 2), 3));
                    nonzero_columns = squeeze(any(any(rotated_mask, 1), 3));
                    
                    top_edge = find(nonzero_rows, 1, 'first');
                    bottom_edge = find(nonzero_rows, 1, 'last');
                    left_edge = find(nonzero_columns, 1, 'first');
                    right_edge = find(nonzero_columns, 1, 'last');

                    new_dims = og_dims;
                    new_dims(1:2) = [bottom_edge-top_edge+1, right_edge-left_edge+1];

                case 'ds'
                    [target_xy, target_slices] = Methods.ChunkyMethods.proc_downsample_targets(app, og_dims(1:3));
                    new_dims = og_dims;
                    new_dims(1:2) = target_xy;
                    new_dims(3) = numel(target_slices);

                case {'hori', 'vert', 'cc', 'acc', 'rotate'}
                    temp_arr = zeros(og_dims);

                    switch action
                        case 'hori'
                            temp_arr = temp_arr(:,end:-1:1,end:-1:1,:,:);

                        case 'vert'
                            temp_arr = temp_arr(end:-1:1,:,end:-1:1,:,:);

                        case 'cc'
                            temp_arr = permute(temp_arr, [2,1,3,4]);
                            temp_arr = temp_arr(:,end:-1:1,:,:,:);

                        case 'acc'
                            temp_arr = permute(temp_arr, [2,1,3,4]);
                            temp_arr = temp_arr(end:-1:1,:,:,:,:);

                        case 'rotate'
                            temp_arr = imrotate(temp_arr, app.proc_rot_spinner.Value);
                            
                    end

                    new_dims = og_dims;
                    new_dims(1:2) = [size(temp_arr, 1) size(temp_arr, 2)];

                otherwise
                    new_dims = og_dims;
            end
        end

        function output_slice = apply_slice(app, action, slice)
            % Apply operation to a slice.
            state = Program.Handlers.channels.processing_state(app);
            RGBW = [state.r.source_idx, state.g.source_idx, state.b.source_idx, state.white.source_idx];

            if size(slice, 4) < max(RGBW)
                RGBW = 1:size(slice, 4);
            end
            
            switch action
                case 'zscore'
                    output_slice = Methods.Preprocess.zscore_frame(slice); 

                case 'histmatch'
                    slice(:, :, :, RGBW(1:3)) = Methods.run_histmatch(slice, RGBW);
                    output_slice = Methods.Preprocess.zscore_frame(slice);     

                case 'crop'
                    output_slice = Program.rotation_gui.apply_mask(app, slice);

                case 'hori'
                    output_slice = slice(:,end:-1:1,end:-1:1,:,:);

                case 'vert'
                    output_slice = slice(end:-1:1,:,end:-1:1,:,:);

                case 'rotate'
                    output_slice = imrotate(slice, app.proc_rot_spinner.Value);

                case 'cc'
                    temp_slice = permute(slice, [2,1,3,4]);
                    output_slice = temp_slice(:,end:-1:1,:,:,:);

                case 'acc'
                    temp_slice = permute(slice, [2,1,3,4]);
                    output_slice = temp_slice(end:-1:1,:,:,:,:);

                case 'ds'
                    [target_xy, target_slices] = Methods.ChunkyMethods.proc_downsample_targets(app, ...
                        [size(slice, 1), size(slice, 2), size(slice, 3)]);
                    temp_slice = imresize(slice, target_xy);
                    output_slice = temp_slice(:, :, target_slices, :);

                case 'window'
                    output_slice = Methods.ChunkyMethods.apply_channel_windows(app, slice);

                case 'debleed'
                    % TBD
            end            
        end

        function processed_vol = apply_vol(app, action, vol)
            % Apply operation to a volume.

            switch action
                case 'debleed'
                    processed_vol = Methods.ChunkyMethods.debleed(app, vol);

                otherwise
                    [new_dims, old_dims] = Methods.ChunkyMethods.calc_pp_size(app, action, vol);
                    nz = old_dims(3);

                    if strcmp(action, 'ds')
                        processed_vol = Methods.ChunkyMethods.apply_slice(app, action, vol);
                        return
                    end

                    % Initialize cache array.
                    processed_vol = zeros(new_dims, class(vol));
    
                    % Iterate over slices.
                    for z=1:nz
                        Program.Handlers.dialogue.step(sprintf("Slice %.f/%.f", z, nz));
    
                        % Grab slice.
                        if isa(vol, 'matlab.io.MatFile')
                            slice = app.proc_image.data(:, :, z, :);
                        else
                            slice = vol(:, :, z, :);
                        end
    
                        % Apply operation.
                        slice = Methods.ChunkyMethods.apply_slice(app, action, slice);
    
                        % Update appropriate slice in cache array.
                        processed_vol(:, :, z, :) = slice;
                    end
            end            
        end

        function apply_colormap(app, actions)
            % Apply set of operations to a colormap.

            % Calculate new colormap dimensions
            Program.Handlers.dialogue.step('Calculating new dimensions...');
            new_dims = size(app.proc_image, 'data');
            for a=1:length(actions)
                new_dims = Methods.ChunkyMethods.calc_pp_size(app, actions{a}, zeros(new_dims));
            end

            if length(actions) < 1
                return
            end

            current_vol = app.proc_image.data;
            for a=1:length(actions)
                Program.Handlers.dialogue.add_task(sprintf("Applying %s", actions{a}));
                Program.Handlers.dialogue.set_value(a/length(actions));
                processed_vol = Methods.ChunkyMethods.apply_vol(app, actions{a}, current_vol);
                current_vol = processed_vol;
            end
    
            % Save to file.
            app.proc_image.Properties.Writable = true;
            app.proc_image.data = current_vol;
            app.proc_image.Properties.Writable = false;
        end

        function apply_video(app, actions, progress)
            % Apply set of operations to a video.

            start_time = datetime("now");

            % ...Set up necessary paths.
            ppath = fileparts(app.video_path); % Get current file's parent path.
            temp_path = sprintf('%s/cache_video.h5', ppath); % Create cache file to which we'll be writing.
            processed_path = sprintf('%s/processed_video.h5', ppath); % Create new video file to avoid overwriting original.

            % If a cache file already exists, delete it.
            if exist(temp_path, 'file')==2
                delete(temp_path);
            end

            % Calculate new video dimensions
            Program.Handlers.dialogue.step('Calculating new dimensions...');
            nt = app.video_info.nt;
            p_frame = app.retrieve_frame(1);
            new_dims = size(p_frame);
            for a=1:length(actions)
                action = actions{a};
                new_dims = Methods.ChunkyMethods.calc_pp_size(app, action, zeros(new_dims));
            end

            % Create the cache file we'll be writing to chunk-by-chunk.
            Program.Handlers.dialogue.step('Creating cache file...');
            h5create(temp_path, '/data', [new_dims(1:end) nt], "Chunksize", [new_dims(1:end) 1], "Datatype", class(p_frame));

            for t=1:nt
                frame_progress = t/nt;
                Program.Handlers.dialogue.set_value(frame_progress);
                time_string = Program.GUIHandling.get_time_string(start_time, t, nt);
                Program.Handlers.dialogue.add_task(sprintf("Frame %.f/%.f %s", t, nt, time_string));

                processed_frame = app.retrieve_frame(t);

                for a=1:length(actions)
                    Program.Handlers.dialogue.set_value(min(frame_progress + (frame_progress/t)*(a/length(actions)), 1));
                    processed_frame = Methods.ChunkyMethods.apply_vol(app, actions{a}, processed_frame);
                end

                % Ensure cache frame retains time dimension.
                write_size = [size(processed_frame) 1];
                processed_frame = reshape(processed_frame, write_size);
                
                % Write cache frame to cache file.
                h5write(temp_path, '/data', processed_frame, [1 1 1 1 t], write_size);

                Program.Handlers.dialogue.resolve();
            end

            if exist(processed_path, 'file')==2
                delete(processed_path);
            end

            movefile(temp_path, processed_path);
            app.video_info.nt = nt;
            Program.Routines.Videos.reload(processed_path);
        end

        function spectral_unmix(app, channel)
            % Remove spectral crosstalk of images based on a linear spectral crosstalk remover.
            Program.GUIHandling.gui_lock(app, 'lock', 'processing_tab');

            if isa(channel, 'matlab.ui.eventdata.ButtonPushedData')
                channel = channel.Source.Tag;
            end

            state = Program.Handlers.channels.processing_state(app);
            ch_idx = [state.r.source_idx, state.g.source_idx, state.b.source_idx];
            size_selection = app.DropperradiusSpinner.Value;
            sigma_gauss = app.SigmagaussEditField.Value;
            rgb = ch_idx(1:3);
            t_idx = [];

            vol = app.proc_image.data;

            % Pick & update ideal channel representations.
            target = Program.GUIHandling.dropper( ...
                sprintf('Click on the pixel on this slice that best represents %s.', channel), ...
                app.proc_xyAxes, vol, app.proc_zSlider.Value);

            if isempty(target.values)
                Program.GUIHandling.gui_lock(app, 'unlock', 'processing_tab');
                return
            else
                app.(sprintf("%s_r", channel)).Value = mean(target.values(ch_idx(1)), 'all');
                app.(sprintf("%s_g", channel)).Value = mean(target.values(ch_idx(2)), 'all');
                app.(sprintf("%s_b", channel)).Value = mean(target.values(ch_idx(3)), 'all');
            end

            % Construct filtered volume: stack channels & normalize.
            vol = double(Methods.Preprocess.zscore_frame(vol));
            vol(vol < 0) = 0;

            filtered_vol = zeros(length(rgb), size(vol,1), size(vol,2), size(vol,3));
            for i = 1:length(rgb)
                filtered_vol(i,:,:,:) = imgaussfilt3(vol(:,:,:,rgb(i))./max(vol(:,:,:,rgb(i)),[],'all').*65535, sigma_gauss);
            end

            switch channel
                case {'bg', 'background'}
                    app.spectral_cache.bg_px = target.pixels;
                    app.spectral_cache.bg_val = double(mean(filtered_vol(:,target.pixels(2)-size_selection:target.pixels(2)+size_selection,target.pixels(1)-size_selection:target.pixels(1)+size_selection,target.pixels(3)),[2,3]));
                case {'w', 'gfp', 'dic', 'gut', 'white'}
                    % TBD
                otherwise
                    t_idx = ch_idx(Program.GUIHandling.channel_map(channel));
            end

            if ~isempty(t_idx)
                if ~ismember(t_idx, app.spectral_cache.ch_db)
                    app.spectral_cache.ch_db = [app.spectral_cache.ch_db; t_idx];
                end

                % If necessary, grab background.
                if isempty(app.spectral_cache.bg_px) || isempty(app.spectral_cache.bg_val)
                    Methods.ChunkyMethods.spectral_unmix(app, 'background')
                end
    
                % Subtract background.
                for ii=1:length(app.spectral_cache.bg_val)
                    filtered_vol(ii,:,:,:) = filtered_vol(ii,:,:,:) - app.spectral_cache.bg_val(ii); 
                end
                
                % Compute linear scaling for spectral crosstalk.
                channels_to_debleed = rgb~=app.spectral_cache.ch_db(t_idx, :);
                app.spectral_cache.ch_val(t_idx, :) = mean(filtered_vol(:,target.pixels(2)-size_selection:target.pixels(2)+size_selection,target.pixels(1)-size_selection:target.pixels(1)+size_selection,target.pixels(3)),[2,3]);
                app.spectral_cache.ch_val(t_idx, channels_to_debleed) = app.spectral_cache.ch_val(channels_to_debleed)/app.spectral_cache.ch_val(~channels_to_debleed);
                app.spectral_cache.ch_val(t_idx, ~channels_to_debleed) = app.spectral_cache.ch_val(~channels_to_debleed)/app.spectral_cache.ch_val(~channels_to_debleed);
    
                app.flags.debleed = 1;
            end
        end

        function output = debleed(app, vol, mode)
            % Check whether to use cache values or cache coords.
            if ~exist('mode', 'var')
                if ~isempty(app.spectral_cache.ch_val)
                    mode = 'val';
                else
                    mode = 'coord';
                end
            end

            % Back up full volume.
            output = vol;

            % Grab processing tab values.
            state = Program.Handlers.channels.processing_state(app);
            ch_idx = [state.r.source_idx, state.g.source_idx, state.b.source_idx];
            size_selection = app.DropperradiusSpinner.Value;
            sigma_gauss = app.SigmagaussEditField.Value;
            rgb = ch_idx(1:3);
            channels_to_debleed = rgb~=app.spectral_cache.ch_db;

            % Normalize volume.
            switch class(vol)
                case {'single', 'double'}
                    % TBD
                case {'matlab.io.MatFile'}
                    vol = vol.data;
                    vol = double(vol)/double(intmax(class(vol)));
                otherwise
                    vol = double(vol)/double(intmax(class(vol)));
            end

            vol(vol<0) = 0;
            
            % Stack relevant channels and normalize.
            filtered_vol = zeros(length(rgb), size(vol,1),size(vol,2),size(vol,3));
            for i = 1:length(rgb)
                filtered_vol(i,:,:,:) = imgaussfilt3(vol(:,:,:,rgb(i))./max(vol(:,:,:,rgb(i)),[],'all').*65535, sigma_gauss);
            end

            switch mode
                case 'val'
                    % Remove background noise.
                    for ii=1:length(app.spectral_cache.bg_val)
                        filtered_vol(ii,:,:,:) = filtered_vol(ii,:,:,:) - app.spectral_cache.bg_val(ii); 
                    end

                    % Debleed.
                    for t_idx = 1:length(app.spectral_cache.ch_db)
                        c = app.spectral_cache.ch_db(t_idx, :);
                        t_ch = channels_to_debleed(c, :);
                        
                        for db = 1:length(t_ch)
                            filtered_vol(db,:,:,:) = filtered_vol(db,:,:,:) - t_ch(db).*app.spectral_cache.ch_val(c, db)* filtered_vol(~t_ch,:,:,:);
                        end
                    end
                case 'coord'
                    % Construct background array
                    bg = double(mean(filtered_vol(:,app.spectral_cache.bg_px(2)-size_selection:app.spectral_cache.bg_px(2)+size_selection,app.spectral_cache.bg_px(1)-size_selection:app.spectral_cache.bg_px(1)+size_selection,app.spectral_cache.bg_px(3)),[2,3]));
                    for ii=1:size(bg)
                        filtered_vol(ii,:,:,:) = filtered_vol(ii,:,:,:) - bg(ii); 
                    end

                    loc_pixel = [app.spectral_cache.ch_px{1};app.spectral_cache.ch_px{2};app.spectral_cache.ch_px{3}];

                    % Compute linear scaling for spectral crosstalk.
                    scale_crosstalk = mean(filtered_vol(:,loc_pixel(1,2)-size_selection:loc_pixel(1,2)+size_selection,loc_pixel(1,1)-size_selection:loc_pixel(1,1)+size_selection,loc_pixel(1,3)),[2,3]);
                    scale_crosstalk(app.spectral_cache.ch_db) = scale_crosstalk(app.spectral_cache.ch_db)/scale_crosstalk(~app.spectral_cache.ch_db);
                    scale_crosstalk(~app.spectral_cache.ch_db) = scale_crosstalk(~app.spectral_cache.ch_db)/scale_crosstalk(~app.spectral_cache.ch_db);
                    
                    % Debleed.
                    for t_idx = 1:length(app.spectral_cache.ch_db)
                        c = app.spectral_cache.ch_db(t_idx, :);
                        filtered_vol(c,:,:,:) = filtered_vol(c,:,:,:) - app.spectral_cache.ch_db(c)*scale_crosstalk(c)* filtered_vol(~app.spectral_cache.ch_db,:,:,:);
                    end
            end

            % Normalize corrected image again.
            for i = 1:length(ch_idx)
                filtered_vol(i,:,:,:) = cast((filtered_vol(i,:,:,:)./max(filtered_vol(i,:,:,:),[],'all').*65535), 'uint64');
            end

            % Permute image to get same format as input.
            filtered_vol = permute(filtered_vol, [4,2,3,1]);
            filtered_vol = permute(filtered_vol,[2,3,1,4]);
            filtered_vol = Methods.Preprocess.zscore_frame(filtered_vol);

            % Replace OG RGB channels and return resulting array.
            output(:,:,:,rgb(1)) = filtered_vol(:,:,:,1);
            output(:,:,:,rgb(2)) = filtered_vol(:,:,:,2);
            output(:,:,:,rgb(3)) = filtered_vol(:,:,:,3);
        end

        function sliceIndices = proc_target_slices(nz, nnz)
            % Calculate the indices of slices to retain for a new volume with nnz slices while preserving isotropy.

            nz = max(1, round(double(nz)));
            nnz = min(max(round(double(nnz)), 1), nz);

            if nnz <= 1
                sliceIndices = ceil(nz / 2);
                return
            end

            if nnz >= nz
                sliceIndices = 1:nz;
                return
            end

            target_positions = linspace(1, nz, nnz);
            available = 1:nz;
            sliceIndices = zeros(1, nnz);
            used = false(1, nz);

            for k = 1:nnz
                [~, order] = sort(abs(available - target_positions(k)), 'ascend');
                for candidate_idx = order
                    candidate = available(candidate_idx);
                    if ~used(candidate)
                        sliceIndices(k) = candidate;
                        used(candidate) = true;
                        break
                    end
                end
            end

            sliceIndices = sort(sliceIndices);
        end

        function neurons = stream_neurons(mode)
            video_info = Program.GUIHandling.global_grab('NeuroPAL ID', 'video_info');
            video_neurons = Program.GUIHandling.global_grab('NeuroPAL ID', 'video_neurons');

            if ~exist('mode', 'var')
                if isfield(video_info.annotations)
                    mode = 'annotations';
                elseif length(video_neurons) > 1
                    mode = 'tree';
                end
            end

            switch mode
                case 'annotations'
                    [~, ~, fmt] = fileparts(video_info.annotations);
                    
                    switch fmt
                        case '.xml'
                            [positions, labels] = DataHandling.readTrackmate(video_info.annotations);
                        case '.h5'
                            [positions, labels] = DataHandling.readAnnoH5(video_info.annotations);                            
                    end

                case 'tree'
                    labels = {};
                    positions = [];
                    for i=1:length(video_neurons)
                        neuron = video_neurons(i);

                        for j=1:length(neuron.rois)
                            x = neuron.rois.x_slice;
                            y = neuron.rois.y_slice;
                            z = neuron.rois.z_slice;
                            t = j;

                            positions = [positions; [x y z t]];
                            labels{end+1} = neuron.worldline.name;
                        end
                    end
                    
            end

            neurons = struct('positions', {positions}, 'labels', {labels});
        end

        function frame = load_proc_image(app)
            frame = struct('xy', {[]}, 'yz', {[]}, 'xz', {[]});
            raw = Program.GUIHandling.get_active_volume(app, 'request', 'all');
            package = Program.Routines.Processing.compose_volume(app, raw);
            render_volume = package.render_volume;
            raw_dims = package.raw_dims;

            Program.GUI.preprocessing_gui().set_gui_limits( ...
                'x', [1, raw_dims(2)], ...
                'y', [1, raw_dims(1)]);

            Program.Handlers.histograms.draw();
            Program.GUIHandling.shorten_knob_labels(app);

            if app.ProcShowMIPCheckBox.Value
                frame.xy = squeeze(max(render_volume, [], 3));
            else
                frame.xy = Program.Helpers.extract_z_slice(render_volume, raw.coords(3), false);
            end

            if app.ProcPreviewZslowCheckBox.Value
                x = min(max(round(raw.coords(1)), 1), size(render_volume, 2));
                y = min(max(round(raw.coords(2)), 1), size(render_volume, 1));
                frame.xz = squeeze(render_volume(:, y, :, :));
                frame.yz = squeeze(render_volume(x, :, :, :));
            end
        end

        function output = apply_channel_windows(app, volume)
            output = volume;
            if ndims(output) < 4
                return
            end

            window_settings = Methods.ChunkyMethods.proc_window_settings(app, size(output, 4));
            if isempty(window_settings)
                return
            end

            for n = 1:numel(window_settings)
                source_idx = window_settings(n).source_idx;
                output(:, :, :, source_idx) = Methods.ChunkyMethods.apply_channel_window( ...
                    output(:, :, :, source_idx), ...
                    window_settings(n).low_high_in);
            end
        end

        function window_settings = proc_window_settings(app, n_channels)
            state = Program.Handlers.channels.processing_state(app);
            template = struct('source_idx', 0, 'low_high_in', [0 1]);
            assigned = false(1, n_channels);
            window_settings = repmat(template, 1, n_channels);

            for n = 1:numel(state.rows)
                row = state.rows(n);
                source_idx = row.source_idx;
                if source_idx < 1 || source_idx > n_channels || assigned(source_idx)
                    continue
                end

                low_high = double(row.settings.low_high_in);
                if isempty(low_high) || numel(low_high) ~= 2
                    continue
                end

                low_high = Methods.ChunkyMethods.normalize_window_range(low_high);
                if all(abs(low_high - [0 1]) <= (0.5 / 255))
                    continue
                end

                window_settings(source_idx).source_idx = source_idx;
                window_settings(source_idx).low_high_in = low_high;
                assigned(source_idx) = true;
            end

            window_settings = window_settings(assigned);
        end

        function output = apply_channel_window(channel, low_high_in)
            low_high_in = Methods.ChunkyMethods.normalize_window_range(low_high_in);
            if all(abs(low_high_in - [0 1]) <= (0.5 / 255))
                output = channel;
                return
            end

            if isfloat(channel)
                finite_mask = isfinite(channel);
                if ~any(finite_mask, 'all')
                    output = channel;
                    return
                end

                finite_vals = channel(finite_mask);
                min_val = min(finite_vals, [], 'all');
                max_val = max(finite_vals, [], 'all');
                if min_val >= 0 && max_val <= 1
                    min_val = 0;
                    max_val = 1;
                end
                if max_val <= min_val
                    output = zeros(size(channel), 'like', channel);
                    return
                end

                normalized = zeros(size(channel), 'double');
                normalized(finite_mask) = (double(channel(finite_mask)) - double(min_val)) ./ ...
                    (double(max_val) - double(min_val));
                normalized = min(max(normalized, 0), 1);
                adjusted = imadjustn(normalized, low_high_in, [0 1], 1);

                output = channel;
                adjusted = double(adjusted) .* (double(max_val) - double(min_val)) + double(min_val);
                output(finite_mask) = cast(adjusted(finite_mask), class(channel));
                return
            end

            output = imadjustn(channel, low_high_in, [0 1], 1);
        end

        function low_high = normalize_window_range(low_high)
            if isempty(low_high) || numel(low_high) < 2
                low_high = [0 1];
                return
            end

            low_high = double(low_high(:)');
            low_high = min(max(low_high(1:2), 0), 1);
            if low_high(1) > low_high(2)
                low_high = fliplr(low_high);
            end
        end

        function request = proc_downsample_request(app, dims3)
            ny = max(1, round(double(dims3(1))));
            nx = max(1, round(double(dims3(2))));
            nz = max(1, round(double(dims3(3))));

            min_xy_factor = 1 / max([ny, nx]);
            xy_factor = double(app.ProcXYFactorEditField.Value);
            if ~isfinite(xy_factor)
                xy_factor = 1;
            end
            xy_factor = min(max(xy_factor, min_xy_factor), 1);

            z_target = double(app.ProcZSlicesEditField.Value);
            if ~isfinite(z_target)
                z_target = nz;
            end
            z_target = min(max(round(z_target), 1), nz);

            target_xy = max(1, round([ny, nx] * xy_factor));
            target_xy = min(target_xy, [ny, nx]);
            target_slices = Methods.ChunkyMethods.proc_target_slices(nz, z_target);

            if isequal(target_xy, [ny, nx])
                xy_factor = 1;
            end
            if numel(target_slices) == nz
                z_target = nz;
            else
                z_target = numel(target_slices);
            end

            request = struct( ...
                'dims3', [ny, nx, nz], ...
                'min_xy_factor', min_xy_factor, ...
                'xy_factor', xy_factor, ...
                'target_xy', target_xy, ...
                'z_target', z_target, ...
                'target_slices', target_slices, ...
                'is_identity', isequal(target_xy, [ny, nx]) && numel(target_slices) == nz);
        end

        function [target_xy, target_slices] = proc_downsample_targets(app, dims3)
            request = Methods.ChunkyMethods.proc_downsample_request(app, dims3);
            target_xy = request.target_xy;
            target_slices = request.target_slices;
        end
    end
end
