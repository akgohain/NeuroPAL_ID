function load(file, parent_token)
    if nargin < 2, parent_token = ''; end
    job = Program.HeavyJob.acquire('Video loading', parent_token);
    job_cleanup = onCleanup(@() delete(job));
    app = Program.app;
    app.video_path = file;

    d = uiprogressdlg(app.CELL_ID,'Title','Loading video...','Indeterminate','on');
    progress_cleanup = onCleanup(@() local_close_progress(d));

    if ~isdeployed
        app.script_dir = fullfile(pwd, '+Wrapper');
        app.script_ext = '.py';
    else
        if ispc
            app.script_dir = fullfile(pwd, '\lib\bin\windows\');
            app.script_ext = '.exe';
        elseif ismac
            ctfroot_path = ctfroot;
            for i = 1:4
                ctfroot_path = fileparts(ctfroot_path);
            end
            app.script_dir = fullfile(ctfroot_path, 'lib/bin/macos/');
            app.script_ext = '';
        end
    end

    %% GUI Initialization

    % Click Handler
    Program.GUIHandling.init_click_states(app);

    app.AdjustNeuronMarkerAlignmentPanel.Parent = app.DefaultTabGroup.Parent;
    app.AdjustNeuronMarkerAlignmentPanel.Layout = app.DefaultTabGroup.Layout;

    app.AdvancedParameterPanel.Parent = app.BasicParameterPanel.Parent;
    app.AdvancedParameterPanel.Layout = app.BasicParameterPanel.Layout;
    
    app.GridSearchPanel.Parent = app.AdvancedParameterPanel.Parent;
    app.GridSearchPanel.Layout = app.AdvancedParameterPanel.Layout;

    %% Load Video

    % Isolate file format
    [~, ~, format] = fileparts(app.video_path);
    format = lower(format);

    % Select loading function based on file format
    switch format
        case '.h5'
            app.load_h5(app.video_path);
        case '.nwb'
            app.load_nwb(app.video_path);
        case '.nd2'
            app.load_nd2(app.video_path);
        case {'.tif', '.tiff'}
            app.load_tif(app.video_path);
        otherwise
            if isprop(app, 'CELL_ID') && isvalid(app.CELL_ID)
                uialert(app.CELL_ID, ...
                    sprintf('Unsupported video format: %s', format), ...
                    'Unsupported video format');
            end
            close(d);
            return
    end

    % Older App Designer loaders may return a representative HDF5 chunk in
    % bitDepth. Retaining that chunk wastes memory and obscures the sample
    % type; keep only its class name.
    if isfield(app.video_info, 'bitDepth') && ...
            isnumeric(app.video_info.bitDepth) && ~isscalar(app.video_info.bitDepth)
        app.video_info.bitDepth = class(app.video_info.bitDepth);
    end

    Program.Helpers.clear_video_view_state(app);

    app.xyAxes.XLim = [1, app.video_info.nx];
    app.xyAxes.YLim = [1, app.video_info.ny];
    %xy_aspectRatio = app.video_info.nx / app.video_info.ny;
    %app.xyAxes.DataAspectRatio = [1, 1/xy_aspectRatio, 1];

    % Define slider limits and values based on video
    app.tSlider.Limits = [1, app.video_info.nt];
    Program.Helpers.configure_video_controls(app);

    app.vert_zSlider.Limits = [1, app.video_info.nz];
    app.vert_zSlider.Value = round(app.video_info.nz/2);

    app.hor_zSlider.Limits = [1, app.video_info.nz];
    app.hor_zSlider.Value = round(app.video_info.nz/2);

    app.xSlider.Limits = [1, app.video_info.nx];
    app.xSlider.Value = round(app.video_info.nx/2);

    app.ySlider.Limits = [1, app.video_info.ny];
    app.ySlider.Value = round(app.video_info.ny/2);

    tx = round(app.video_info.nx/2);
    ty = round(app.video_info.ny/2);
    tz = round(app.video_info.nz/2);

    % Render Frame 1
    app.visual_composer(1, tz, ty, tx);
    app.data_flags.('Video_Volume') = 1;

    Program.GUIHandling.refresh_processing_volume_dropdown(app, 'Video');
    Program.GUIHandling.hide_startup_load_buttons(app);
    Program.GUIHandling.gui_lock(app, 'enable', 'video_tab');
    Program.GUIHandling.gui_lock(app, 'enable', 'processing_tab');

    set(app.VideoGridLayout, 'Visible', 'on');
    Program.GUI.refresh_zephir_video_tab(app);
    close(d);
end

function local_close_progress(d)
try
    if ~isempty(d) && isvalid(d), close(d); end
catch
end
end
