function test_main_keyboard_guard(app)
%TEST_MAIN_KEYBOARD_GUARD Reject unloaded sources and controls that consume typing.
if nargin < 1, app = Program.app; end
window = uifigure('Visible', 'off');
cleanup = onCleanup(@() delete(window));
text = uieditfield(window, 'text');
numeric = uieditfield(window, 'numeric');
area = uitextarea(window);
spinner = uispinner(window);
dropdown = uidropdown(window);

% Small state fixtures exercise source availability without altering open pixels.
state = struct('TabGroup', struct('SelectedTab', app.NeuroPALIDTab), ...
    'NeuroPALIDTab', app.NeuroPALIDTab, 'ImageProcessingTab', app.ImageProcessingTab, ...
    'image_data', zeros(2, 2, 3, 'uint8'), 'proc_image', [], ...
    'VolumeDropDown', struct('Value', 'Colormap'), 'video_info', struct());
assert(Program.Helpers.main_shortcut_allowed(state, []));
for focused = {text, numeric, area, spinner, dropdown}
    assert(~Program.Helpers.main_shortcut_allowed(state, focused{1}));
end
state.image_data = [];
assert(~Program.Helpers.main_shortcut_allowed(state, []));
state.TabGroup.SelectedTab = app.LogTab;
assert(~Program.Helpers.main_shortcut_allowed(state, []));
state.TabGroup.SelectedTab = app.VideoTrackingTab;
assert(~Program.Helpers.main_shortcut_allowed(state, []));
state.TabGroup.SelectedTab = app.ImageProcessingTab;
assert(~Program.Helpers.main_shortcut_allowed(state, []));
state.VolumeDropDown.Value = 'Video';
assert(~Program.Helpers.main_shortcut_allowed(state, []));
state.video_info = struct('nx', 4, 'ny', 4, 'nz', 3, 'nt', 10, 'nc', 1);
assert(Program.Helpers.main_shortcut_allowed(state, []));
state.video_info.nz = 0;
assert(~Program.Helpers.main_shortcut_allowed(state, []));
fprintf('MAIN_KEYBOARD_SOURCE_AND_FOCUS_GUARD=PASS\n');
end
