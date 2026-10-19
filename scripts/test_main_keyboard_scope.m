function test_main_keyboard_scope(app)
%TEST_MAIN_KEYBOARD_SCOPE Main image shortcuts must not act on unrelated tabs.
if nargin < 1, app = Program.app; end
tab = app.TabGroup.SelectedTab;
cleanup = onCleanup(@() set(app.TabGroup, 'SelectedTab', tab));
z = app.ZSlider.Value;
limits = {app.XY.XLim, app.XY.YLim};
channels = [app.RCheckBox.Value, app.GCheckBox.Value, app.BCheckBox.Value, ...
    app.WCheckBox.Value, app.DICCheckBox.Value, app.GFPCheckBox.Value];
labels = app.show_labels;
callback = app.CELL_ID.KeyPressFcn;
for other = [app.LogTab, app.VideoTrackingTab]
    app.TabGroup.SelectedTab = other;
    for key = {'leftarrow', 'rightarrow', 'uparrow', 'downarrow', 'h', 'j', 'k', 'r', 'i', '3', '4', '5', '6'}
        Program.GUIHandling.invoke_gui_callback(callback, app.CELL_ID, struct('Key', key{1}, 'Modifier', {{}}));
    end
    assert(app.ZSlider.Value == z);
    assert(isequal({app.XY.XLim, app.XY.YLim}, limits));
    assert(isequal([app.RCheckBox.Value, app.GCheckBox.Value, app.BCheckBox.Value, ...
        app.WCheckBox.Value, app.DICCheckBox.Value, app.GFPCheckBox.Value], channels));
    assert(isequal(app.show_labels, labels));
end
fprintf('MAIN_KEYBOARD_TAB_SCOPE=PASS\n');
end
