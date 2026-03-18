function save()
    app = Program.app;
    actions = fieldnames(app.flags);
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
