function test_main_keyboard_navigation(app)
%TEST_MAIN_KEYBOARD_NAVIGATION Keep keyboard slices and the slider together.
if nargin < 1, app = Program.app; end
original_tab = app.TabGroup.SelectedTab;
original_z = app.ZSlider.Value;
cleanup = onCleanup(@() local_restore(app, original_tab, original_z));
app.TabGroup.SelectedTab = app.NeuroPALIDTab;
nz = size(app.image_data, 3);
assert(nz >= 4, 'Open a volume with at least four Z slices.');
commit = app.ZSlider.ValueChangedFcn;
commit(app.ZSlider, struct('Value', 2));
revision = Program.Helpers.main_display_source_revision(app);
image_handle = getappdata(app.XY, 'main_slice_image');
limits = {app.XY.XLim, app.XY.YLim};

% Repeated presses advance from the committed position, in both directions.
keys = {'rightarrow', 'rightarrow', 'leftarrow', 'leftarrow', 'leftarrow', 'leftarrow'};
expected = [3 4 3 2 1 1];
for k = 1:numel(keys)
    local_press(app, keys{k});
    local_assert_slice(app, expected(k), image_handle);
end
commit(app.ZSlider, struct('Value', nz));
local_press(app, 'rightarrow');
local_assert_slice(app, nz, image_handle);

% A queued drag preview cannot overwrite a keyboard step after it commits.
commit(app.ZSlider, struct('Value', 2));
app.ZSlider.ValueChangingFcn(app.ZSlider, struct('Value', nz));
local_press(app, 'rightarrow');
preview = getappdata(app.CELL_ID, 'main_slice_preview');
preview.flush();
local_assert_slice(app, 3, image_handle);
assert(isequal(Program.Helpers.main_display_source_revision(app), revision));
assert(isequal({app.XY.XLim, app.XY.YLim}, limits));
fprintf('MAIN_KEYBOARD_NAVIGATION=PASS\n');
end

function local_press(app, key)
callback = app.CELL_ID.KeyPressFcn;
Program.GUIHandling.invoke_gui_callback(callback, app.CELL_ID, struct('Key', key));
end

function local_assert_slice(app, z, image_handle)
assert(app.ZSlider.Value == z, 'Keyboard navigation did not update the slider.');
view = Program.Helpers.main_display_view_cache(app);
assert(view.z_gui == z, 'The displayed slice does not match the slider.');
assert(isequal(image_handle, getappdata(app.XY, 'main_slice_image')));
assert(isequal(image_handle.CData, view.display_slice));
assert(view.projection_cache_hit);
end

function local_restore(app, tab, z)
app.ZSlider.ValueChangedFcn(app.ZSlider, struct('Value', z));
app.TabGroup.SelectedTab = tab;
end
