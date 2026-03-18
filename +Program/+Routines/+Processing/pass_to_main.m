function pass_to_main()
    app = Program.app;

    switch app.VolumeDropDown.Value
        case 'Colormap'
            Program.Routines.open(app.proc_image.Properties.Source);
            Program.Helpers.sync_main_from_processing(app);
            app.TabGroup.SelectedTab = app.NeuroPALIDTab;

        case 'Video'
            Program.Routines.Videos.load(app.video_info.file);
            app.TabGroup.SelectedTab = app.VideoTrackingTab;
    end
end
