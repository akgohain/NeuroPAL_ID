function test_unloaded_navigation(app)
%TEST_UNLOADED_NAVIGATION Switching empty tabs must not try to load a volume.
assert(isempty(app.image_data));
original_tab = app.TabGroup.SelectedTab;
cleanup = onCleanup(@() set(app.TabGroup, 'SelectedTab', original_tab));
callback = app.TabGroup.SelectionChangedFcn;
for tab = [app.ImageProcessingTab, app.VideoTrackingTab, app.NeuroPALIDTab]
    old_tab = app.TabGroup.SelectedTab;
    app.TabGroup.SelectedTab = tab;
    callback(app.TabGroup, struct('OldValue', old_tab, 'NewValue', tab));
    assert(isempty(app.image_data));
    assert(~app.is_opening_file);
end
assert(strcmp(app.ImageProcessingTab.Tag, 'raw'));
fprintf('UNLOADED_NAVIGATION=PASS\n');
end
