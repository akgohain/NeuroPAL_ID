function save()
    app = Program.app;
    actions = Program.GUIHandling.processing_file_actions(app);
    had_file_actions = ~isempty(actions);

    if had_file_actions
        Program.Handlers.dialogue.add_task('Updating file...');
    end

    switch app.VolumeDropDown.Value
        case 'Colormap'
            Methods.ChunkyMethods.apply_colormap(app, actions);

        case 'Video'
            Methods.ChunkyMethods.apply_video(app, actions);
    end

    app.flags = struct();
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
    if had_file_actions
        Program.Handlers.dialogue.resolve();
        prompt = "Successfully updated file. Load into main tab?";
    else
        prompt = "No file-backed processing operations were pending. Load the current preview state into the main tab?";
    end

    check = uiconfirm(Program.window, ...
        prompt, "NeuroPAL_ID", ...
        "Options",["Yes", "No"]);
    if strcmp(check, "Yes")
        Program.Routines.Processing.pass_to_main();
    end
end
