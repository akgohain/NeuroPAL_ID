function open(path)
    Program.HeavyJob.assertIdle();
    app = Program.app;
    Program.GUIHandling.install_main_processing_sync_callbacks(app);

    % Are we already opening a file?
    if app.is_opening_file
        return;
    end
    app.is_opening_file = true;
    opening_guard = onCleanup(@() local_finish_open(app));
    
    % Unselect any neurons.
    Program.Handlers.neurons.unselect_neuron();
    if ~isempty(app.id_file) && exist(app.id_file, 'file')
        source = dbstack();
        if numel(source) < 2 || ~contains(source(2).name, 'pass_to_main')
            Program.Handlers.neurons.save_id_file();
        end
    end

    GUI_prefs = Program.GUIPreferences.instance();
    if nargin == 0
        % Setup the file chooser's path.
        %path = '../';
        path = GUI_prefs.image_dir;

        % Ask the user which file they want.
        file_info = [path ';*.mat;*.czi;*.nd2;*.tif;*.tiff;*.h5;*.nwb'];
        app.CELL_ID.Visible = 'off'; % Hack On! * Matlab can't seem to put the modal dialogue in the foreground
        [name, path, ~] = uigetfile(file_info, 'Select Worm Image');
        app.CELL_ID.Visible = 'on'; % Hack Off! * Matlab can't seem to put the modal dialogue in the foreground
        if name == 0
            app.is_opening_file = false;
            return; % user cancelled
        end

        % Load the file.
        d = uiprogressdlg(app.CELL_ID,'Title','Loading file...',...
    'Indeterminate','on');

        if app.DisplayNeuronActivityMenu.Checked
            app.DisplayNeuronActivityMenu.Checked = ~app.DisplayNeuronActivityMenu.Checked;
            app.TabGroup4.SelectedTab = app.MaximumIntensityProjectionTab;
        end

        filename = [path, name];
        close(d)
        if Tracking.ReferenceWorkflow.supports(filename)
            local_open_reference(app, filename);
            return;
        end
        try
            proc_code = app.proc_check("image", filename);
        catch ME
            [~, ~, ext] = fileparts(filename);
            if strcmpi(ext, '.nwb')
                Program.Helpers.debug_event('OpenFile', ...
                    'Skipping proc_check for "%s" because nwbRead failed during size probing: %s', ...
                    filename, ME.message);
                proc_code = filename;
            else
                rethrow(ME);
            end
        end
        d = uiprogressdlg(app.CELL_ID,'Title','Loading file...',...
    'Indeterminate','on');
        if proc_code == 1
            close(d);
            app.is_opening_file = false;
            return
        end
    else
        [~, name] = fileparts(path);
        filename = path;

        % Load the file.
        d = uiprogressdlg(app.CELL_ID,'Title','Reloading processed file...', 'Indeterminate','on');

        if app.DisplayNeuronActivityMenu.Checked
            app.DisplayNeuronActivityMenu.Checked = ~app.DisplayNeuronActivityMenu.Checked;
            app.TabGroup4.SelectedTab = app.MaximumIntensityProjectionTab;
        end
    end

    if Tracking.ReferenceWorkflow.supports(filename)
        close(d);
        local_open_reference(app, filename);
        return;
    end

    progress_cleanup = onCleanup(@() local_close_progress(d));
    app.logEvent('Main',sprintf('Loading file from %s...', filename), 1)

    % Save the path in our preferences.
    GUI_prefs.image_dir = path;
    GUI_prefs.save();

    job = Program.HeavyJob.acquire('Image loading');
    job_cleanup = onCleanup(@() delete(job));
    try                
        [data, info, prefs, worm, mp, neurons, np_file, id_file] = ...
            DataHandling.NeuroPALImage.open(filename);
    catch ME
        Program.Helpers.debug_event('OpenFile', ...
            'Cannot read "%s": %s', filename, getReport(ME, 'extended', 'hyperlinks', 'off'));
        if strcmp(ME.identifier, 'DataHandling:LargeFile:Cancelled')
            uialert(app.CELL_ID, ...
                {ME.message, 'Reopen the source file to resume from the saved checkpoint.'}, ...
                'Conversion Paused', 'Icon', 'info');
        elseif any(strcmp(ME.identifier, ...
                {'DataHandling:NeuroPALImage:ND2VideoInImageLoader', ...
                 'DataHandling:ND2:VideoNotImage'}))
            uialert(app.CELL_ID, ...
                {['"' filename '" is an ND2 time series, not a single NeuroPAL image volume.'], ...
                 ME.message, ...
                 'Use the Video Tracking loader instead.'}, ...
                'Video File Selected in Image Loader', 'Icon', 'warning');
        else
            msg = getReport(ME, 'extended', 'hyperlinks', 'off');
            uialert(app.CELL_ID, ...
                {['Cannot read "' filename '"!'], ['Error:' msg]}, ...
                'Image File Failure', 'Icon', 'error');
        end
        app.is_opening_file = false;
        return;
    end

    % Check the worm info.
    if ~Program.Validation.worm(worm)
        app.is_opening_file = false;
        return
    end

    % Fix the prefs for z-axis orientation.
    if ~isfield(prefs, 'z_center')
        prefs.z_center = ceil(size(data,3) / 2);
        prefs.is_Z_LR = true;
        prefs.is_Z_flip = true;
    end

    % Setup the file.
    Program.HeavyJob.assertIdle(job.Token);
    app.image_file = np_file;
    app.id_file = [];
    app.image_prefs = prefs;

    % Setup the image.
    app.image_name = name; %strrep(name, '_', '\_');
    app.image_data = data;
    if isappdata(app.CELL_ID, 'proc_runtime_dirty')
        rmappdata(app.CELL_ID, 'proc_runtime_dirty');
    end

    % Z-score the image.
    app.image_data_zscored = [];

    % Load and update the gamma.
    gamma_size = length(app.gamma_RGBW_DIC_GFP_index);
    if isscalar(prefs.gamma)
        app.image_gamma = ones(gamma_size, 1);
        app.image_gamma(1:3) = prefs.gamma;
        app.image_prefs.gamma = app.image_gamma;
    elseif length(prefs.gamma) < gamma_size
        app.image_gamma = ones(gamma_size, 1);
        app.image_gamma(1:length(prefs.gamma)) = prefs.gamma;
        app.image_prefs.gamma = app.image_gamma;
    else
        app.image_gamma = prefs.gamma;
    end

    % Load the image scale and info.
    app.image_um_scale = info.scale;
    app.image_info = info;

    % Setup the color channels.
    RGBW = prefs.RGBW;
    RGBW_nan = isnan(RGBW);
    RGBW(RGBW_nan) = 1; % default unassigned colors to channel 1
    channels_str = arrayfun(@num2str, 1:size(app.image_data, 4), 'UniformOutput', false);
    % Red.
    app.RDropDown.Items = channels_str;
    app.RDropDown.Value = app.RDropDown.Items{RGBW(1)};
    app.RCheckBox.Value = true;
    % Green.
    app.GDropDown.Items = channels_str;
    app.GDropDown.Value = app.GDropDown.Items{RGBW(2)};
    app.GCheckBox.Value = true;
    % Blue.
    app.BDropDown.Items = channels_str;
    app.BDropDown.Value = app.BDropDown.Items{RGBW(3)};
    app.BCheckBox.Value = true;
    % White.
    app.WDropDown.Items = channels_str;
    if size(app.image_data, 4)>3
        app.WDropDown.Value = app.WDropDown.Items{RGBW(4)};
    end
    app.WCheckBox.Value = false;
    % DIC.
    app.DICDropDown.Items = channels_str;
    if ~isnan(prefs.DIC)
        try
            app.DICDropDown.Value = app.DICDropDown.Items{prefs.DIC};
        catch
            app.DICDropDown.Value = app.DICDropDown.Items{end};
        end
    end
    app.DICCheckBox.Value = false;
    % GFP.
    app.GFPDropDown.Items = channels_str;
    if ~isnan(prefs.GFP)
        try
            app.GFPDropDown.Value = app.GFPDropDown.Items{prefs.GFP};
        catch
            app.GFPDropDown.Value = app.GFPDropDown.Items{end};
        end
    end
    app.GFPCheckBox.Value = false;

    % Setup the worm info.
    app.worm = worm;
    app.BodyDropDown.Value = worm.body;
    if any(strcmp(app.AgeDropDown.Items, worm.age))
        app.AgeDropDown.Value = worm.age;
    else
        app.AgeDropDown.Value = 'Adult';
        app.worm.age = 'Adult';
    end
    app.SexDropDown.Value = worm.sex;
    app.StrainEditField.Value = worm.strain;
    app.SubjectNotesTextArea.Value = worm.notes;

    % Enable the image GUI.
    Program.GUIHandling.gui_lock(app, 'enable', 'identification_tab');
    Program.GUIHandling.gui_lock(app, 'disable', 'neuron_gui');

    % Did we detect neurons?
    app.id_file = id_file;
    app.mp_params = mp;
    read_nwb_neurons = 0;
    nwb_data = [];
    if ~isempty(neurons)
        app.image_neurons = neurons;
        Program.GUIHandling.gui_lock(app, 'enable', 'neuron_gui');
        Program.Helpers.debug_log('DEBUG: Set app.image_neurons with %d neurons\n', length(neurons.neurons));
    elseif contains(filename,'.nwb')
        % For NWB files, even if neurons is empty, don't override with empty object
        % The loadNP function should have already tried to load from NWB
        Program.Helpers.debug_log('DEBUG: NWB file detected but no neurons loaded\n');
        
        % Check for legacy NWB neuron data format for backwards
        % compatibility. Use HDF5 first so broken ExternalLinks in unrelated
        % NWB objects do not block image opening.
        if DataHandling.Helpers.nwb.has_neuropal_segmentation(filename)
            Program.Helpers.debug_event('NWB', ...
                ['NWB segmentation metadata found in "%s", but automatic ' ...
                 'MatNWB neuron import is skipped during image open.'], ...
                filename);
        end

        app.image_neurons = Neurons.Image([], worm.body, 'scale', app.image_um_scale');
    else
        app.image_neurons = Neurons.Image([], worm.body, 'scale', app.image_um_scale');
        Program.Helpers.debug_log('DEBUG: Created empty Neurons.Image object\n');
    end

    % Restrict the slider to the z stack.
    num_z_slices = size(app.image_data, 3);
    if num_z_slices <= 1
        uialert(app.CELL_ID, 'The image is not a volume!', ...
            'Image Not a Volume', 'Icon', 'error');
        app.is_opening_file = false;
        return;
    end
    initial_z_slice = round(num_z_slices / 2);
    Program.Helpers.configure_main_zslider(app, num_z_slices, initial_z_slice);

    % Setup the z-axis orientation.
    app.ZCenterEditField.Value = round((prefs.z_center - 1) * info.scale(3), 1);
    if prefs.is_Z_LR
        app.ZAxisDropDown.Value = 'L/R';
        app.ZLeftLabel.Text = 'LEFT';
        app.ZRightLabel.Text = 'RIGHT';
    else
        app.ZAxisDropDown.Value = 'D/V';
        app.ZLeftLabel.Text = 'DORSAL';
        app.ZRightLabel.Text = 'VENTRAL';
    end

    % Setup the max projection.
    Program.Helpers.ensure_main_image_axes(app);
    daspect(app.XY,[1 1 1]);
    daspect(app.MaxProjection,[1 1 1]);
    axis(app.MaxProjection, 'off');
    Program.Helpers.fill_axes_parent(app.XY);
    Program.Helpers.fill_axes_parent(app.MaxProjection);

    % Label the image.
    app.XY.Title.Interpreter = 'none';
    app.XY.Title.String = app.image_name;
    app.XY.TitleFontSizeMultiplier = 2;
    app.XY.TitleFontWeight = 'bold';
    Program.Helpers.configure_image_axes_ticks( ...
        app.XY, size(app.image_data), info.scale(1:2), ...
        'XLim', [0, size(app.image_data, 2)], ...
        'YLim', [0, size(app.image_data, 1)]);

    % The supported handler above has already unselected the previous
    % neuron. Clear the index again after replacing image_neurons, without
    % calling the app's private UnselectNeuron method from this package.
    app.selected_neuron = [];

    % Draw everything.
    app.UserNeuronIDsListBox.Items = {};
    app.UserNeuronIDsListBox.ItemsData = [];
    app.UserNeuronIDsListBox.Value = {};

    if ismember('is_matched', fieldnames(app.image_prefs))
        if app.image_prefs.is_matched == 1
            app.image_data(:, :, :, app.image_info.RGBW(1:3)) = Methods.run_histmatch(app.image_data, app.image_info.RGBW);
        end
    end
    
    Program.Routines.ID.render();
    Program.Routines.ID.hot_neuron_reset();

    if read_nwb_neurons == 1
        app.load_neurons_from_nwb(nwb_data, job.Token);
        Program.GUIHandling.gui_lock(app, 'enable', 'neuron_gui');
    end

    % Go to the middle.
    Program.Helpers.configure_main_zslider(app, num_z_slices, initial_z_slice);

    % Draw the neurons in this z-slice.
    Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
    close(d)

    Program.Helpers.drag_event_listeners(app);
    
    % Done.
    app.is_opening_file = false;
    clear opening_guard
    app.data_flags.('NeuroPAL_Volume') = 1;

    set(app.VolumeDropDown, 'Enable', 'on');
    
    Program.GUIHandling.refresh_processing_volume_dropdown(app, 'Colormap');
    Program.GUIHandling.hide_startup_load_buttons(app);
    Program.GUIHandling.gui_lock(app, 'enable', 'processing_tab');

    set(app.IdGridLayout, 'Visible', 'on');
    set(app.ProcessingGridLayout, 'Visible', 'on');
    set(app.IdButton, 'Visible', 'off');
    set(app.ProcessingButton, 'Visible', 'off');
    Program.GUIHandling.update_main_id_workflow_state(app);
    app.TabGroup.SelectedTab = app.NeuroPALIDTab;
    drawnow;
end

function local_close_progress(d)
try
    if ~isempty(d) && isvalid(d), close(d); end
catch
end
end

function local_finish_open(app)
% Never leave the open guard latched after a callback error.
try
    if ~isempty(app) && isvalid(app)
        app.is_opening_file = false;
        app.CELL_ID.Visible = 'on';
    end
catch
end
end

function local_open_reference(app, filename)
% Report a video import failure without leaving the file opener latched.
try
    Tracking.ReferenceWorkflow.open(app, filename);
catch ME
    Program.Helpers.debug_event('OpenFile', '%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    uialert(app.CELL_ID, ME.message, 'Cannot Open Recording');
end
end
