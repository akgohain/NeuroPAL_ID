function initialized = initialize(app)
    % Keep the researcher's existing MATLAB figures open.
    initialized=false;
    if nargin<1, app=Program.ProgramInfo.app(); end
    existing=getappdata(groot,'neuropal_active_app');
    if ~isempty(existing) && isvalid(existing) && isgraphics(existing.CELL_ID)
        if ~isequal(existing,app), delete(app); end
        figure(existing.CELL_ID);
        initialized=isequal(existing,app);
        return;
    end
    setappdata(groot,'neuropal_active_app',app);
    setappdata(app.CELL_ID,'npal_startup_complete',false);
    initialization_guard=onCleanup(@() finish_startup(app));

    % Using mlapptools because Matlab refuses to give me focus control.
    % This warning needs to shut up :-)
    % mlapptools.getWebWindow (line 337)
    warning off MATLAB:ui:javaframe:PropertyToBeRemoved;

    window = app.CELL_ID;
    % Keep cleanup in user code so App Designer preserves it when saving.
    window.DeleteFcn = @(~, ~) Program.Helpers.cleanup_ui_runtime(app);

    if ~isdeployed
        % If we're running in dev mode, add Data & External Dependencies to
        % path.
        root=Runtime.Configuration.appRoot();
        addpath(genpath(fullfile(root, "Data")));
        addpath(genpath(fullfile(root, "External_Dependencies")));
    end

    d = uiprogressdlg(window, "Title","NeuroPAL ID","Message","Starting NeuroPAL_ID...",'Indeterminate','on');
    startup_cleanup=onCleanup(@() Runtime.Installer.close(d));
    app.logEvent('Main','Starting NeuroPAL_ID...', 1);
    app.logEvent('Main','Resizing NeuroPAL_ID...', 1);

    Program.Helpers.resize_window();
    Program.Routines.GUI.toggle_buttons();
    Program.Handlers.dialogue.active([]);

    % Load the application preferences.
    is_loaded = Program.GUIPreferences.load();

    % Log the change.
    if exist('TraceHistory', 'class')
        app.log = TraceHistory.Instance;
        app.log.setup({'startupFcn'});
    end

    % Are we using the parallelization toolbox?
    parallel_tb = ver('parallel');
    if isempty(parallel_tb)
        app.is_parallel = false;
    end

    % Initialize the structured properties.
    Program.GUIHandling.init_click_states(app);
    Program.GUIHandling.install_open_callbacks(app);
    Program.GUIHandling.install_metadata_callbacks(app);
    Program.GUIHandling.install_help_callbacks(app);
    Runtime.Settings.install(app);
    Program.GUIHandling.hide_main_click_mode_control(app);
    Program.GUIHandling.hide_next_neuron_mode_control(app);
    Program.GUIHandling.configure_main_detect_id_controls(app);
    Program.GUIHandling.configure_main_z_controls(app);
    Program.GUIHandling.remove_redundant_processing_menus(app);
    Program.CallbackBoundary.install(app);
    Program.GUIHandling.configure_log_tab(app);
    app.neuron_marker.shape = 'c';
    app.neuron_marker.color.edge = [0,0,0];
    Program.GUIHandling.prepare_unloaded_module_views(app);
    Program.GUIHandling.ensure_processing_color_ui(app);
    Program.GUIHandling.configure_processing_sidebar_layout(app);
    Program.GUIHandling.update_processing_zslider_visibility(app);
    Program.GUI.setup_zephir_video_tab(app);
    Program.GUIHandling.gui_lock(app, 'disable', 'identification_tab');
    Program.GUIHandling.gui_lock(app, 'disable', 'processing_tab');
    Program.GUIHandling.gui_lock(app, 'disable', 'video_tab');
    Program.GUIHandling.update_main_id_workflow_state(app);
    Program.GUI.update_zephir_video_tab(app);

    % Initialize the neuron birth times.
    [app.hermaphrodite_neurons.names, ...
        app.hermaphrodite_neurons.birth_stages, ~] = ...
        Neurons.NeuronBirth.getHermaphroditeBirthText();
    [app.male_neurons.names, ...
        app.male_neurons.birth_stages, ~] = ...
        Neurons.NeuronBirth.getMaleBirthText();

    app.logEvent('Main','Setting up GUI...', 1);
    % Setup the GUI.
    if is_loaded
        GUIPrefs = Program.GUIPreferences.instance();

        % Are we showing the neuron birth times?
        if GUIPrefs.is_show_birth_times
            app.ToggleBirthTimesMenu.Text = 'Hide Birth Times';
        end

        % Are auto-completing neuron names?
        app.AutoNameCheckBox.Value = GUIPrefs.is_auto_name;

        % Are we auto-updating neuron IDs?
        if ~GUIPrefs.is_autoID_updates
            app.ToggleAutoIDUpdatesMenu.Text = 'Enable Auto-ID Updates';
        end

        % Update the detector toggle label from the saved backend.
        switch GUIPrefs.get_detection_backend()
            case 'mp'
                app.ToggleNeuronDetectionMenu.Text = 'Use NN-Detect Neurons';
            case 'nn'
                app.ToggleNeuronDetectionMenu.Text = 'Use Cellpose-Detect Neurons';
            case 'cellpose'
                app.ToggleNeuronDetectionMenu.Text = 'Use YOLO-Detect Neurons';
            case 'yolo'
                app.ToggleNeuronDetectionMenu.Text = 'Use MP-Detect Neurons';
            case {'spotiflow_supervised', 'detection_moe'}
                app.ToggleNeuronDetectionMenu.Text = 'Use MP-Detect Neurons';
        end
        Program.GUIHandling.install_cellpose_mask_button(app);

        % This is a new user, give them some help!
    else

        % Show the instructions.
        try
            uialert(app.CELL_ID, Program.ProgramInfo.getInstructionsMsg(), ...
                'NeuroPAL ID instructions', 'Icon', 'info');
        catch ME
            msg = getReport(ME, 'extended', 'hyperlinks', 'off');
            uialert(app.CELL_ID, ...
                {'Cannot open instructions!', '', 'Error:', msg}, ...
                'Display Instructions', 'Icon', 'error');
            return;
        end

        % Save the GUI preferences.
        Program.GUIPreferences.save();
    end

    close(d);
    setappdata(app.CELL_ID,'npal_startup_complete',true);
    initialized=true;
end

function finish_startup(app)
    if isvalid(app) && isgraphics(app.CELL_ID) && ...
            isequal(getappdata(app.CELL_ID,'npal_startup_complete'),true)
        return;
    end
    if isequal(getappdata(groot,'neuropal_active_app'),app)
        rmappdata(groot,'neuropal_active_app');
    end
    if isvalid(app), delete(app); end
end
