function crop()
    app = Program.GUIHandling.app;

    Program.GUIHandling.processing_roi_lock(app, 'lock');
    roi_lock_cleanup = onCleanup(@() Program.GUIHandling.processing_roi_lock(app, 'unlock'));
    check = uiconfirm(app.CELL_ID, "Draw a bounding box on the volume to crop the image.", "NeuroPAL_ID", "Options", ["OK", "Cancel"]);
    if ~strcmp(check, "OK")
        return
    end

    roi = drawrectangle(app.proc_xyAxes,'Color','black','StripeColor','m');
    clear roi_lock_cleanup

    Program.crop_rotate_gui.draw(app, roi);

    if app.EnabledebugmenuCheckBox.Value
        Program.Routines.Debug.rotation();
    end
end
