function reset_id_render(arr)
    app = Program.app;

    nx = size(arr, 2);
    ny = size(arr, 1);

    scale = app.image_info.scale;

    % Setup the max projection.
    daspect(app.XY, [1 1 1]);
    daspect(app.MaxProjection, [1 1 1]);
    axis(app.MaxProjection, 'off');
    Program.Helpers.fill_axes_parent(app.XY);
    Program.Helpers.fill_axes_parent(app.MaxProjection);

    % Constrain the image.
    app.XY.XLim = [0, nx];
    app.XY.YLim = [0, ny];

    % Label the image.
    app.XY.Title.Interpreter = 'none';
    app.XY.Title.String = app.image_name;
    app.XY.TitleFontSizeMultiplier = 2;
    app.XY.TitleFontWeight = 'bold';

    Program.Helpers.configure_image_axes_ticks( ...
        app.XY, [ny, nx], scale(1:2), ...
        'XLim', [0, nx], ...
        'YLim', [0, ny], ...
        'TargetXTicks', 9, ...
        'TargetYTicks', 6);
end
