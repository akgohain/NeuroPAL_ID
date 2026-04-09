function load_file(mode, path)
            app = Program.app;
            window = Program.window;
            Program.Helpers.debug_event('ProcLoad', ...
                'mode=%s path=%s', string(mode), string(path));

            d = uiprogressdlg(window,"Title","NeuroPAL ID","Message","Initializing Processing Tab...",'Indeterminate','off');    
            app.flags = struct();
            Methods.ChunkyMethods.clear_spectral_filtered_cache(app);
            if isappdata(app.CELL_ID, 'proc_mip_cache')
                rmappdata(app.CELL_ID, 'proc_mip_cache');
            end
            if isappdata(app.CELL_ID, 'proc_render_cache')
                rmappdata(app.CELL_ID, 'proc_render_cache');
            end
            if isappdata(app.CELL_ID, 'proc_raw_cache')
                rmappdata(app.CELL_ID, 'proc_raw_cache');
            end
            if isappdata(app.CELL_ID, 'proc_histogram_signature')
                rmappdata(app.CELL_ID, 'proc_histogram_signature');
            end
            if isappdata(app.CELL_ID, 'proc_render_view_dims')
                rmappdata(app.CELL_ID, 'proc_render_view_dims');
            end
            app.rotation_stack.cache = struct('Colormap', {{}}, 'Video', {{}});
            gammas = [];
            
            [filepath, name, ext] = fileparts(path);

            switch mode
                case "image"
                    Program.Routines.GUI.add_volume('Colormap')
                    mat_file = fullfile(filepath, [name, '.mat']);
                    if ~isfile(mat_file)
                        DataHandling.NeuroPALImage.open(path);
                        path = mat_file;
                    end

                    app.proc_image = matfile(mat_file);

                    vol_size = size(app.proc_image, 'data');
                    nx = vol_size(2);
                    ny = vol_size(1);
                    nz = vol_size(3);
                    nc = vol_size(4);
                    nt = 1;

                    prefs = app.proc_image.prefs;
                    gammas = prefs.gamma;
                    Program.Helpers.debug_event('ProcLoad', ...
                        'image prefs: size=%s gamma=%s is_Z_flip=%d RGBW=%s DIC=%s GFP=%s', ...
                        mat2str(vol_size), ...
                        mat2str(gammas(:)'), ...
                        Program.Helpers.struct_field(prefs, 'is_Z_flip', 0), ...
                        mat2str(Program.Helpers.struct_field(prefs, 'RGBW', [])), ...
                        mat2str(Program.Helpers.struct_field(prefs, 'DIC', [])), ...
                        mat2str(Program.Helpers.struct_field(prefs, 'GFP', [])));

                    % Using intmax is faster as it avoids loading the
                    % entire variable, but it also distorts the histograms.
                    % max_val = double(intmax(class(app.proc_image.data(1, 1, 1, 1))));
                    maximum_value = double(max(app.proc_image.data, [], 'all'));

                    app.VolumeDropDown.Value = 'Colormap';
                    app.data_flags.('NeuroPAL_Volume') = 1;
                    Program.Routines.GUI.toggle_colormap();

                case "video"
                    Program.Routines.GUI.add_volume('Video')
                    Program.Routines.Videos.load(path);
                    maximum_value = double(intmax(class(app.retrieve_frame(3))));

                    nx = app.video_info.nx;
                    ny = app.video_info.ny;
                    nz = app.video_info.nz;
                    nc = app.video_info.nc;
                    nt = app.video_info.nt;

                    app.VolumeDropDown.Value = 'Video';
                    app.data_flags.('Video_Volume') = 1;
                    
                    Program.Routines.GUI.toggle_video();
            end
    
            d.Value = 2 / 5;
            d.Message = sprintf('Calculating threshold...');
            Program.GUIHandling.set_thresholds(app, maximum_value);
    
            d.Value = 3 / 5;
            d.Message = sprintf('Mapping channels...');
            Program.Handlers.channels.initialize(path);
    
            d.Value = 4 / 5;
            d.Message = sprintf('Configuring GUI...');
            daspect(app.proc_xyAxes, [1 1 1]);

            if nc < 4
                app.ProcHistogramGrid.RowHeight = {'1x'};
            end
            
            Program.Routines.GUI.set_limits(nx, ny, nz, nt);
            Program.GUIHandling.install_processing_slider_callbacks(app);
            Program.GUIHandling.install_processing_histogram_callbacks(app);
            Program.GUIHandling.install_processing_advanced_callback(app);
            Program.GUIHandling.configure_processing_color_panel(app);
            Program.GUIHandling.configure_processing_sidebar_layout(app);

            app.ProcXYFactorEditField.Enable = 'on';
            app.ProcZSlicesEditField.Enable = 'on';
            app.ProcZSlicesEditField.Limits = [1, max(1, nz)];
            app.ProcZSlicesEditField.RoundFractionalValues = 'on';
            app.ProcZSlicesEditField.ValueDisplayFormat = '%.0f';
            app.ProcTStartEditField.Limits = [1, max(1, nt)];
            app.ProcTStopEditField.Limits = [1, max(1, nt)];
            app.ProcTStartEditField.RoundFractionalValues = 'on';
            app.ProcTStopEditField.RoundFractionalValues = 'on';

            set(app.proc_xEditField, 'Enable', 'off');
            set(app.proc_yEditField, 'Enable', 'off');
    
            gammas = Program.Helpers.expand_gamma( ...
                gammas, ...
                length(Program.GUIHandling.pos_prefixes));
            for n=1:length(Program.GUIHandling.pos_prefixes)
                app.(sprintf('%s_GammaEditField', Program.GUIHandling.pos_prefixes{n})).Value = gammas(n);
            end

            if mode == "image"
                synced = Program.Helpers.sync_processing_from_main(app, mat_file);
                Program.Helpers.debug_event('ProcLoad', ...
                    'sync_processing_from_main=%d final_gammas=%s', ...
                    synced, mat2str(gammas(:)'));
            end
    
            d.Value = 5 / 5;
            d.Message = sprintf('Drawing image...');
            app.drawProcImage();
            Program.GUIHandling.capture_processing_defaults(app, lower(string(app.VolumeDropDown.Value)), true);

            app.ImageProcessingTab.Tag = 'rendered';
            set(app.ProcessingButton, 'Visible', 'off');
            set(app.ProcessingGridLayout, 'Visible', 'on');

            app.TabGroup.SelectedTab = app.ImageProcessingTab;
            drawnow limitrate nocallbacks;
            Program.GUIHandling.apply_processing_responsive_layout(app);
            close(d)

            check = uiconfirm(app.CELL_ID, "We recommend starting by cropping your image to ensure that there is no superfluous space taking up memory. Do you want to do so now?", "NeuroPAL_ID", "Options", ["Yes", "No, skip cropping."]);
            switch check
                case "Yes"
                    app.ProcCropImageButtonPushed([]);
                    Program.GUIHandling.gui_lock(app, 'unlock', 'processing_tab');
                case "No, skip cropping."
                    app.drawProcImage();
                    Program.GUIHandling.gui_lock(app, 'unlock', 'processing_tab');
            end

            Program.GUIHandling.gui_lock(app, 'unlock', 'processing_tab');
end
