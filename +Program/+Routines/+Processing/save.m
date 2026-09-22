function saved = save()
    saved = false;
    Program.HeavyJob.assertIdle();
    app = Program.app;
    actions = Program.GUIHandling.processing_file_actions(app);

    switch app.VolumeDropDown.Value
        case 'Colormap'
            if ~isempty(actions)
                if ~Program.Helpers.apply_processing_preview_action(app, actions)
                    return
                end
            end

            Program.Helpers.sync_main_display_from_processing(app, false);
            if ~Program.Helpers.write_processing_colormap_to_file(app), return; end
            Program.Routines.Processing.render();
            Program.Routines.ID.render();

        case 'Video'
            if ~isempty(actions)
                Program.Handlers.dialogue.add_task('Updating file...');
            end
            if ~Methods.ChunkyMethods.apply_video(app, actions), return; end
            if ~isempty(actions)
                Program.Handlers.dialogue.resolve();
            end
        otherwise
            return
    end

    saved = true;
    app.flags = struct();
    if isappdata(app.CELL_ID, 'proc_runtime_dirty')
        rmappdata(app.CELL_ID, 'proc_runtime_dirty');
    end
    Program.GUIHandling.set_thresholds(app, 255);
    Program.GUIHandling.sanitize_processing_downsample_fields(app);
    app.ProcXYFactorEditField.Value = 1;
    dims = Program.GUIHandling.processing_source_dims(app);
    app.ProcZSlicesEditField.Value = dims(3);
    if strcmp(app.VolumeDropDown.Value, 'Colormap'), Program.ProcessingSession.capture(app); end
    if strcmp(app.VolumeDropDown.Value, 'Video')
        Program.GUIHandling.capture_processing_defaults(app, 'video', true);
    end
    Program.GUIHandling.update_processing_commit_state(app);
    Methods.ChunkyMethods.clear_spectral_filtered_cache(app);
    if isappdata(app.CELL_ID, 'proc_mip_cache')
        rmappdata(app.CELL_ID, 'proc_mip_cache');
    end
    if isappdata(app.CELL_ID, 'proc_view_cache')
        rmappdata(app.CELL_ID, 'proc_view_cache');
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
end
