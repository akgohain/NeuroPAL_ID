function test_main_slider(app)
%TEST_MAIN_SLIDER Verify that release commits Z without rebuilding the volume.
if nargin < 1, app = Program.app; end
original_z = app.ZSlider.Value;
cleanup = onCleanup(@() local_restore(app, original_z));
view = Program.Helpers.main_display_view_cache(app);
revision = Program.Helpers.main_display_source_revision(app);
projection = app.MaxProjection.Children;
limits = {app.XY.XLim, app.XY.YLim};
callback = app.ZSlider.ValueChangedFcn;
z = min(3, size(app.image_data, 3));

% Release must work even when the last drag event was not drawn.
callback(app.ZSlider, struct('Value', z));
assert(app.ZSlider.Value == z);
current = Program.Helpers.main_display_view_cache(app);
assert(current.z_gui == z);
assert(current.projection_cache_hit);
assert(isequal(current.max_projection, view.max_projection));
assert(isequal(Program.Helpers.main_display_source_revision(app), revision));
assert(isequal(app.MaxProjection.Children, projection));
assert(isequal({app.XY.XLim, app.XY.YLim}, limits));
image_handle = getappdata(app.XY, 'main_slice_image');
assert(isequal(image_handle.CData, current.display_slice));

% Repeated releases remain cache hits and preserve the same graphics object.
callback(app.ZSlider, struct('Value', z));
assert(isequal(image_handle, getappdata(app.XY, 'main_slice_image')));
assert(isequal(Program.Helpers.main_display_source_revision(app), revision));

% Drag previews do not feed intermediate positions back into the slider.
controller = getappdata(app.CELL_ID, 'main_slice_preview');
changing = app.ZSlider.ValueChangingFcn;
for preview_z = [8 17 29 6 14]
    changing(app.ZSlider, struct('Value', preview_z));
end
controller.flush();
assert(app.ZSlider.Value == z);
preview = Program.Helpers.main_display_view_cache(app);
assert(preview.z_gui == 14);
changing(app.ZSlider, struct('Value', 30));
callback(app.ZSlider, struct('Value', 16));
controller.flush();
pause(0.1);
assert(app.ZSlider.Value == 16);
current = Program.Helpers.main_display_view_cache(app);
assert(current.z_gui == 16);
assert(isequal(image_handle.CData, current.display_slice));
assert(isequal(Program.Helpers.main_display_source_revision(app), revision));
fprintf('MAIN_SLIDER=PASS\n');
end

function local_restore(app, z)
app.ZSlider.Value = z;
Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
end
