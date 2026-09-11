function render(t, z, x, y, app)
    %RENDER Refresh the video projections and annotation overlays.
    if nargin < 5 || isempty(app), app = Program.app; end

    if nargin < 1 || isempty(t)
        t = round(app.tSlider.Value);
    end
    if app.OverlaylastIDdframeCheckBox_2.Value
        earlier_frames = app.id_frames(app.id_frames < app.tSlider.Value);
        if ~isempty(earlier_frames), t = max(earlier_frames); end
    end
   
    if nargin < 2 || isempty(z)
        z = round(app.hor_zSlider.Value);
    end
    
    if nargin < 4 || isempty(y)
        y = round(app.xSlider.Value);
    end
    
    if nargin < 3 || isempty(x)
        x = round(app.video_info.ny-app.ySlider.Value);
    end
    
    Program.Validation.frame_in_bounds(t);
    Program.Validation.slice_in_bounds(z);
    render = Program.Helpers.video_render_views(app, t, z, x, y, app.OverlayFrameMIPCheckBox.Value);

    proj = fieldnames(render);
    for p=1:length(proj)
        projection = proj{p};
        arr = render.(projection);

        if strcmp(projection, 'yz')
            arr = permute(arr, [2, 1, 3]);
        end

        render.(projection) = Program.Helpers.scale_video_projection(app,arr);
    end
    
    xy_img = Program.Helpers.set_video_image(app.xyAxes, render.xy, 'npal_video_xy');
    xz_img = Program.Helpers.set_video_image(app.xzAxes, render.yz, 'npal_video_xz');
    yz_img = Program.Helpers.set_video_image(app.yzAxes, render.xz, 'npal_video_yz');

    Program.Helpers.sl_sync();
    
    xy_img.ButtonDownFcn = {@app.ImageClicked};
    xz_img.ButtonDownFcn = {@app.ImageClicked};
    yz_img.ButtonDownFcn = {@app.ImageClicked};
    
    app.xyAxes.XLim = [1, size(render.xy, 2)];
    app.xyAxes.YLim = [1, size(render.xy, 1)];
    app.xzAxes.XLim = [1, size(render.yz, 2)];
    app.xzAxes.YLim = [1, size(render.yz, 1)];
    app.yzAxes.XLim = [1, size(render.xz, 2)];
    app.yzAxes.YLim = [1, size(render.xz, 1)];

    Program.Helpers.draw_video_cursor(x, y, z);

    delete(findobj(app.xyAxes,'Type','images.roi.Point'));
    delete(findobj(app.yzAxes,'Type','images.roi.Point'));
    delete(findobj(app.xzAxes,'Type','images.roi.Point'));

    if any(app.id_frames == app.tSlider.Value)
        app.roi_draw(app.xSlider.Value, app.ySlider.Value, z, t)
    end
end
