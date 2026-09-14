function pass_to_main()
    Program.HeavyJob.assertIdle();
    app = Program.app;

    switch app.VolumeDropDown.Value
        case 'Colormap'
            Program.Helpers.sync_main_display_from_processing(app, true);
            app.TabGroup.SelectedTab = app.NeuroPALIDTab;

        case 'Video'
            Program.Routines.Videos.load(app.video_info.file);
            app.TabGroup.SelectedTab = app.VideoTrackingTab;
    end
end
