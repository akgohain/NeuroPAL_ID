function render()
    %% Draw the annotated image (image volume & neuron markers).

    app = Program.app;

    % Is there an image?
    if isempty(app.image_data)
        return;
    end

    app.logEvent('Main','Drawing image...', 1);
    Program.GUIHandling.install_cellpose_mask_button(app);
    Program.GUIHandling.install_yolo_boxes_button(app);
    Program.Helpers.ensure_main_image_axes(app);

    state = Program.Handlers.channels.main_state(app);
    Program.Helpers.debug_event('IDRender', ...
        'channels rgb=[%d %d %d] w=%d dic=%d gfp=%d checks=%s gamma=%s image_size=%s', ...
        state.r.idx, state.g.idx, state.b.idx, ...
        state.white.idx, state.dic.idx, state.gfp.idx, ...
        mat2str([state.r.bool state.g.bool state.b.bool ...
                 state.white.bool state.dic.bool state.gfp.bool]), ...
        mat2str(app.image_gamma(:)'), ...
        mat2str(size(app.image_data)));
    view_cache = Program.Helpers.render_main_display_view(app, app.ZSlider.Value, ...
        Program.Helpers.main_display_view_cache(app));
    Program.Helpers.main_display_view_cache(app, view_cache);
    app.image_view = view_cache.render_volume;
    Program.Helpers.debug_array_summary('IDRender', 'image_view.max_projection', view_cache.max_projection);

    % Redraw the max projection.
    % Note: the image only shows RGB. We added the other channels
    % (W, DIC, GFP) to the RGB in order to show these as well.
    Program.Helpers.fill_axes_parent(app.MaxProjection);
    image(app.MaxProjection, squeeze(view_cache.max_projection));
    Program.Helpers.fill_axes_parent(app.MaxProjection);

    % Redraw the Z-slice.
    Program.Routines.ID.get_slice(app.ZSlider, view_cache, app.XY);
end
