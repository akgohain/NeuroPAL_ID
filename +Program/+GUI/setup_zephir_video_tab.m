function setup_zephir_video_tab(app)
%SETUP_ZEPHIR_VIDEO_TAB Rebuild the video tab around the ZephIR workflow.
% This intentionally reparents existing App Designer components instead of
% deleting them, so legacy callbacks and backend handles remain valid.

if nargin < 1 || isempty(app) || ~isvalid(app)
    return
end

layout_version = 20;
if isappdata(app.CELL_ID, 'zephir_video_ui_setup') && ...
        getappdata(app.CELL_ID, 'zephir_video_ui_setup') && ...
        isappdata(app.CELL_ID, 'zephir_video_ui_layout_version') && ...
        isequal(getappdata(app.CELL_ID, 'zephir_video_ui_layout_version'), layout_version)
    Program.GUI.update_zephir_video_tab(app);
    return
end

setappdata(app.CELL_ID, 'zephir_video_ui_setup', true);
setappdata(app.CELL_ID, 'zephir_video_ui_layout_version', layout_version);

root = app.VideoGridLayout;
root.Tag = 'zephir-video-root';
root.ColumnWidth = {'1x'};
root.RowHeight = {'1x', 18, 350};
root.ColumnSpacing = 0;
root.RowSpacing = 6;
root.Padding = [8 6 8 8];
root.BackgroundColor = [0.94 0.95 0.96];

remove_header(app, root);
left_grid = setup_left_workstation(app, root);
setup_viewer(app, left_grid);
setup_navigation(app, left_grid);
toggle_button = setup_workflow_toggle(app, root);
workflow_panel = setup_workflow_tabs(app, root);
apply_workflow_collapse_state(app, root, workflow_panel, toggle_button);
setup_video_tracking_copy(app);
wrap_action_callbacks(app);

Program.GUI.update_zephir_video_tab(app);
end

function grid = setup_left_workstation(~, root)
panel = tagged_panel(root, 'zephir-left-workstation', '');
panel.BorderType = 'none';
panel.BackgroundColor = [0.94 0.95 0.96];
panel.Layout.Row = 1;
panel.Layout.Column = 1;

grid = tagged_grid(panel, 'zephir-left-workstation-grid');
grid.ColumnWidth = {'1x'};
grid.RowHeight = {'1x', 76};
grid.RowSpacing = 8;
grid.Padding = [0 0 0 0];
grid.BackgroundColor = panel.BackgroundColor;
end

function setup_viewer(app, parent_grid)
app.Panel_55.Parent = parent_grid;
app.Panel_55.Layout.Row = 1;
app.Panel_55.Layout.Column = 1;
app.Panel_55.Title = '';
app.Panel_55.FontWeight = 'bold';
app.Panel_55.BackgroundColor = [0.08 0.09 0.10];

app.GridLayout2_2.ColumnWidth = {'1x', 150, 24};
app.GridLayout2_2.RowHeight = {'1.35x', '0.50x', 26};
app.GridLayout2_2.ColumnSpacing = 3;
app.GridLayout2_2.RowSpacing = 3;
app.GridLayout2_2.Padding = [8 8 8 8];
app.GridLayout2_2.BackgroundColor = [0.08 0.09 0.10];

format_axis(app.xyAxes, 'XY');
format_axis(app.xzAxes, 'XZ');
format_axis(app.yzAxes, 'YZ');
Program.GUI.configure_zephir_video_axes(app);
end

function setup_navigation(app, parent_grid)
app.Panel_34.Parent = parent_grid;
app.Panel_34.Layout.Row = 2;
app.Panel_34.Layout.Column = 1;
app.Panel_34.BorderType = 'line';
app.Panel_34.BackgroundColor = [0.98 0.98 0.96];

app.GridLayout40.ColumnWidth = {250, '1x'};
app.GridLayout40.RowHeight = {'1x'};
app.GridLayout40.Padding = [8 6 8 6];
app.GridLayout40.ColumnSpacing = 8;

app.Panel_35.Parent = app.GridLayout40;
app.Panel_35.Layout.Row = 1;
app.Panel_35.Layout.Column = 1;
app.Panel_35.BackgroundColor = [0.98 0.98 0.96];
app.GridLayout41.BackgroundColor = [0.98 0.98 0.96];

app.Panel_36.Parent = app.GridLayout40;
app.Panel_36.Layout.Row = 1;
app.Panel_36.Layout.Column = 2;
app.GridLayout42.ColumnWidth = {70, '1x'};
app.GridLayout42.BackgroundColor = [0.98 0.98 0.96];
app.GridLayout43.BackgroundColor = [0.98 0.98 0.96];
app.GridLayout44.BackgroundColor = [0.98 0.98 0.96];

app.tSlider.MajorTicks = [];
app.tSlider.MinorTicks = [];
app.tSlider.ValueChangedFcn = @(src, event)Program.GUI.handle_zephir_time_slider(app, event.Value, true);
app.tSlider.ValueChangingFcn = @(src, event)Program.GUI.handle_zephir_time_slider(app, event.Value, false);
app.xSlider.MinorTicks = [];
app.ySlider.MinorTicks = [];
app.hor_zSlider.MinorTicks = [];
app.vert_zSlider.MinorTicks = [];
set_tooltip(app.tSlider, 'Frame/time navigation. Drag to preview and release to settle on a frame.');
set_tooltip(app.xSlider, 'X crosshair position in the XY and XZ views.');
set_tooltip(app.ySlider, 'Y crosshair position in the XY and YZ views.');
set_tooltip(app.hor_zSlider, 'Z slice position.');
set_tooltip(app.vert_zSlider, 'Z slice position, mirrored for the vertical control.');
end

function toggle_button = setup_workflow_toggle(app, root)
toggle_panel = tagged_panel(root, 'zephir-workflow-toggle-panel', '');
toggle_panel.BorderType = 'none';
toggle_panel.BackgroundColor = [0.94 0.95 0.96];
toggle_panel.Layout.Row = 2;
toggle_panel.Layout.Column = 1;

toggle_grid = tagged_grid(toggle_panel, 'zephir-workflow-toggle-grid');
toggle_grid.ColumnWidth = {'1x', 28, '1x'};
toggle_grid.RowHeight = {'1x'};
toggle_grid.Padding = [0 0 0 0];
toggle_grid.ColumnSpacing = 0;
toggle_grid.BackgroundColor = toggle_panel.BackgroundColor;

old_status = findobj(toggle_grid, 'Tag', 'zephir_workflow_status_label');
for idx = 1:numel(old_status)
    if isvalid(old_status(idx)) && isprop(old_status(idx), 'Visible')
        old_status(idx).Visible = 'off';
    end
end

toggle_button = findobj(toggle_grid, 'Tag', 'zephir_workflow_toggle_button');
if isempty(toggle_button) || ~isvalid(toggle_button(1))
    toggle_button = uibutton(toggle_grid, 'push', 'Tag', 'zephir_workflow_toggle_button');
else
    toggle_button = toggle_button(1);
end
toggle_button.Layout.Row = 1;
toggle_button.Layout.Column = 2;
toggle_button.Text = '^';
toggle_button.FontSize = 13;
toggle_button.FontWeight = 'bold';
toggle_button.BackgroundColor = [0.94 0.95 0.96];
toggle_button.Tooltip = 'Hide workflow/settings.';
toggle_button.ButtonPushedFcn = @(src, event)toggle_workflow_panel(app, root, src);
end

function workflow_panel = setup_workflow_tabs(app, root)
workflow_panel = tagged_panel(root, 'zephir-right-workflow-panel', '');
workflow_panel.BorderType = 'none';
workflow_panel.BackgroundColor = [0.94 0.95 0.96];
workflow_panel.Layout.Row = 3;
workflow_panel.Layout.Column = 1;

right_grid = tagged_grid(workflow_panel, 'zephir-right-workflow-grid');
right_grid.ColumnWidth = {'1x', 330};
right_grid.RowHeight = {'1x'};
right_grid.ColumnSpacing = 8;
right_grid.RowSpacing = 0;
right_grid.Padding = [0 0 0 0];
right_grid.BackgroundColor = workflow_panel.BackgroundColor;

app.DefaultTabGroup.Parent = right_grid;
app.DefaultTabGroup.Layout.Row = 1;
app.DefaultTabGroup.Layout.Column = 1;
app.DefaultTabGroup.Tag = 'zephir-workflow-tabs';

app.NeuronInformationPanel.Parent = right_grid;
app.NeuronInformationPanel.Layout.Row = 1;
app.NeuronInformationPanel.Layout.Column = 2;
app.NeuronInformationPanel.Title = 'Selected Worldline';
compact_selected_worldline_panel(app);

setup_dataset_tab(app);
setup_reference_tab(app);
setup_run_tab(app);
review_tab = setup_review_tab(app);
setup_activity_tab(app);
app.DefaultTabGroup.Children = [ ...
    app.AnnotationSupportTab; ...
    app.ParametersTab; ...
    app.CreditTab; ...
    review_tab; ...
    app.ActivityTab];

app.DefaultTabGroup.SelectedTab = app.AnnotationSupportTab;

if isvalid(app.WorkflowPanel)
    app.WorkflowPanel.Visible = 'off';
    app.WorkflowPanel.Parent = workflow_panel;
end
end

function toggle_workflow_panel(app, root, toggle_button)
is_collapsed = false;
if isappdata(app.CELL_ID, 'zephir_workflow_collapsed')
    is_collapsed = getappdata(app.CELL_ID, 'zephir_workflow_collapsed');
end
setappdata(app.CELL_ID, 'zephir_workflow_collapsed', ~is_collapsed);
workflow_panel = findobj(root, 'Tag', 'zephir-right-workflow-panel');
if isempty(workflow_panel) || ~isvalid(workflow_panel(1))
    return
end
apply_workflow_collapse_state(app, root, workflow_panel(1), toggle_button);
end

function apply_workflow_collapse_state(app, root, workflow_panel, toggle_button)
is_collapsed = false;
if isappdata(app.CELL_ID, 'zephir_workflow_collapsed')
    is_collapsed = getappdata(app.CELL_ID, 'zephir_workflow_collapsed');
end

if is_collapsed
    root.RowHeight = {'1x', 18, 1};
    workflow_panel.Visible = 'off';
    toggle_button.Text = 'v';
    toggle_button.Tooltip = 'Show workflow/settings.';
else
    root.RowHeight = {'1x', 18, 350};
    workflow_panel.Visible = 'on';
    toggle_button.Text = '^';
    toggle_button.Tooltip = 'Hide workflow/settings.';
end
end

function setup_dataset_tab(app)
app.AnnotationSupportTab.Title = '1 Recording';
hide_if_valid(app.GridLayout7_2);

grid = tagged_grid(app.AnnotationSupportTab, 'zephir-dataset-tab-grid');
grid.ColumnWidth = {'1x', '1x'};
grid.RowHeight = {'1x'};
grid.ColumnSpacing = 8;
grid.RowSpacing = 0;
grid.Padding = [8 8 8 8];

source_panel = uipanel(grid, 'Title', 'Video source');
source_panel.Layout.Row = 1;
source_panel.Layout.Column = 1;
source_panel.FontWeight = 'bold';
source_grid = uigridlayout(source_panel, 'ColumnWidth', {'1x'}, ...
    'RowHeight', {22, 22, 22, 22, 22, 22, '1x'}, ...
    'Padding', [10 8 10 8], 'RowSpacing', 4);
app.TrackingButton.Tag = 'zephir-open-video-button';
app.TrackingButton.Visible = 'off';
set_tooltip(app.TrackingButton, 'Open or replace the tracked video dataset. Prefer File > Open.');
source_file_label = tagged_label(source_grid, 'zephir_dataset_file');
source_file_label.Layout.Row = 1;
source_file_label.Layout.Column = 1;
source_file_label.WordWrap = 'off';
source_folder_label = tagged_label(source_grid, 'zephir_dataset_folder');
source_folder_label.Layout.Row = 2;
source_folder_label.Layout.Column = 1;
source_folder_label.WordWrap = 'off';
source_dims_label = tagged_label(source_grid, 'zephir_dataset_dims');
source_dims_label.Layout.Row = 3;
source_dims_label.Layout.Column = 1;
source_dims_label.WordWrap = 'off';
source_format_label = tagged_label(source_grid, 'zephir_dataset_format');
source_format_label.Layout.Row = 4;
source_format_label.Layout.Column = 1;
source_format_label.WordWrap = 'off';
source_channels_label = tagged_label(source_grid, 'zephir_dataset_channels');
source_channels_label.Layout.Row = 5;
source_channels_label.Layout.Column = 1;
source_channels_label.WordWrap = 'off';
source_scale_label = tagged_label(source_grid, 'zephir_dataset_scale');
source_scale_label.Layout.Row = 6;
source_scale_label.Layout.Column = 1;
source_scale_label.WordWrap = 'off';
source_memory_label = tagged_label(source_grid, 'zephir_dataset_memory');
source_memory_label.Layout.Row = 7;
source_memory_label.Layout.Column = 1;
source_memory_label.Visible = 'on';
hide_zephir_artifact_panel(app.AnnotationSupportTab);

display_panel = uipanel(grid, 'Title', 'Viewer display');
display_panel.Layout.Row = 1;
display_panel.Layout.Column = 2;
display_panel.FontWeight = 'bold';
display_grid = uigridlayout(display_panel);
display_grid.ColumnWidth = {'1x', '1x', '1x'};
display_grid.RowHeight = {18, 24, 26, 26, 18, 24, '1x'};
display_grid.Padding = [10 6 10 8];
display_grid.RowSpacing = 2;
display_grid.ColumnSpacing = 12;
compact_viewer_display_controls(app, display_grid);
set_tooltip(display_panel, 'Viewer display controls affect only the rendered preview, not the saved video data.');
end

function hide_zephir_artifact_panel(parent)
old_panel = findobj(parent, 'Title', 'ZephIR artifacts');
for idx = 1:numel(old_panel)
    if isvalid(old_panel(idx)) && isprop(old_panel(idx), 'Visible')
        old_panel(idx).Visible = 'off';
    end
end
end

function remove_header(app, root)
header = findobj(root, 'Tag', 'zephir-video-header');
for idx = 1:numel(header)
    if isvalid(header(idx))
        preserve_tracking_button(app, root);
        delete(header(idx));
    end
end
end

function preserve_tracking_button(app, root)
if isempty(app.TrackingButton) || ~isvalid(app.TrackingButton)
    return
end

try
    app.TrackingButton.Parent = root;
    app.TrackingButton.Layout.Row = 1;
    app.TrackingButton.Layout.Column = 2;
    app.TrackingButton.Visible = 'off';
catch
end
end

function compact_viewer_display_controls(app, display_grid)
% Flatten these controls into the parent grid. Nested titled panels were
% clipping slider thumbs/tick chrome in short workflow rows.
if isvalid(app.ColorControlPanel)
    app.ColorControlPanel.Visible = 'off';
end
if isvalid(app.Panel_40)
    app.Panel_40.Visible = 'off';
end

labels = {app.RSliderLabel, app.GSliderLabel, app.BSliderLabel};
sliders = {app.RSlider, app.GSlider, app.BSlider};
for idx = 1:3
    labels{idx}.Parent = display_grid;
    labels{idx}.Layout.Row = 1;
    labels{idx}.Layout.Column = idx;
    labels{idx}.FontSize = 13;
    labels{idx}.HorizontalAlignment = 'center';
    sliders{idx}.Parent = display_grid;
    sliders{idx}.Layout.Row = 2;
    sliders{idx}.Layout.Column = idx;
    sliders{idx}.FontSize = 9;
    sliders{idx}.MajorTicks = [];
    set_slider_tick_labels(sliders{idx}, {});
    sliders{idx}.MinorTicks = [];
    set_tooltip(sliders{idx}, 'Display-only RGB gain for the orthogonal video viewer.');
end

app.OverlayFrameMIPCheckBox.Parent = display_grid;
app.OverlayFrameMIPCheckBox.Layout.Row = 3;
app.OverlayFrameMIPCheckBox.Layout.Column = 1;
app.OverlayFrameMIPCheckBox.Text = 'MIP';
app.OverlayFrameMIPCheckBox.FontSize = 11;
set_tooltip(app.OverlayFrameMIPCheckBox, 'Display maximum-intensity projections instead of the current z slice.');

app.ShowallneuronsCheckBox.Parent = display_grid;
app.ShowallneuronsCheckBox.Layout.Row = 3;
app.ShowallneuronsCheckBox.Layout.Column = 2;
app.ShowallneuronsCheckBox.Text = 'All markers';
app.ShowallneuronsCheckBox.FontSize = 11;
set_tooltip(app.ShowallneuronsCheckBox, 'Show markers for all annotated worldlines at the current frame.');

app.OverlaylastIDdframeCheckBox.Parent = display_grid;
app.OverlaylastIDdframeCheckBox.Layout.Row = 3;
app.OverlaylastIDdframeCheckBox.Layout.Column = 3;
app.OverlaylastIDdframeCheckBox.Text = 'Last ID';
app.OverlaylastIDdframeCheckBox.FontSize = 11;
set_tooltip(app.OverlaylastIDdframeCheckBox, 'Overlay the nearest earlier ID frame.');

crosshair_toggle = tagged_checkbox(display_grid, 'zephir_viewer_crosshair_toggle', 'Crosshair');
crosshair_toggle.Layout.Row = 4;
crosshair_toggle.Layout.Column = 1;
crosshair_toggle.Value = viewer_bool(app, 'zephir_show_video_crosshair', true);
crosshair_toggle.ValueChangedFcn = @(src, event)set_viewer_bool(app, ...
    'zephir_show_video_crosshair', logical(src.Value), true);
set_tooltip(crosshair_toggle, 'Show or hide the orthogonal crosshair.');

live_orthos_toggle = tagged_checkbox(display_grid, 'zephir_viewer_live_orthos_toggle', 'Live XZ/YZ');
live_orthos_toggle.Layout.Row = 4;
live_orthos_toggle.Layout.Column = [2 3];
live_orthos_toggle.Value = viewer_bool(app, 'zephir_live_orthos_during_drag', false);
live_orthos_toggle.ValueChangedFcn = @(src, event)set_viewer_bool(app, ...
    'zephir_live_orthos_during_drag', logical(src.Value), false);
set_tooltip(live_orthos_toggle, 'Also refresh XZ/YZ while dragging the time slider. Slower for large/lazy videos.');

app.MarkerSizeLabel.Parent = display_grid;
app.MarkerSizeLabel.Layout.Row = 5;
app.MarkerSizeLabel.Layout.Column = [1 3];
app.MarkerSizeLabel.FontSize = 12;
app.MarkerSizeLabel.HorizontalAlignment = 'center';
app.MarkerSizeSlider.Parent = display_grid;
app.MarkerSizeSlider.Layout.Row = 6;
app.MarkerSizeSlider.Layout.Column = [1 3];
app.MarkerSizeSlider.FontSize = 9;
app.MarkerSizeSlider.MajorTicks = [];
set_slider_tick_labels(app.MarkerSizeSlider, {});
app.MarkerSizeSlider.MinorTicks = [];
set_tooltip(app.MarkerSizeSlider, 'Display size for annotated worldline markers.');
end

function setup_reference_tab(app)
app.ParametersTab.Title = '2 Reference';
hide_if_valid(app.GridLayout58);

grid = tagged_grid(app.ParametersTab, 'zephir-reference-tab-grid');
grid.ColumnWidth = {390, '1x'};
grid.RowHeight = {'1x'};
grid.ColumnSpacing = 8;
grid.RowSpacing = 0;
grid.Padding = [8 8 8 8];

actions = uipanel(grid, 'Title', 'Seed sparse reference annotations');
actions.Layout.Row = 1;
actions.Layout.Column = 1;
actions.FontWeight = 'bold';
action_grid = uigridlayout(actions);
action_grid.ColumnWidth = {'1x', '1x'};
action_grid.RowHeight = {30, 30, 30};
action_grid.Padding = [8 5 8 6];
action_grid.RowSpacing = 5;
action_grid.ColumnSpacing = 6;

place_button(app.ImportexistingtracksButton, action_grid, 1, 1, ...
    'Import existing tracks');
place_button(app.InsertNeuroPALNeuronsButton, action_grid, 1, 2, ...
    'Import NeuroPAL neurons');
place_button(app.InsertlastIDdFrameButton, action_grid, 2, 1, ...
    'Copy previous ID frame');
place_button(app.RecommendFramesButton, action_grid, 2, 2, ...
    'Reference frames');
place_button(app.SaveAnnotationsButton, action_grid, 3, [1 2], ...
    'Save ZephIR annotations');
set_tooltip(app.ImportexistingtracksButton, 'Load TrackMate/XML/H5/NWB annotations as ZephIR reference worldlines.');
set_tooltip(app.InsertNeuroPALNeuronsButton, 'Seed the video from neurons currently loaded in the NeuroPAL ID tab.');
set_tooltip(app.InsertlastIDdFrameButton, 'Copy worldline locations from the nearest earlier annotated frame.');
set_tooltip(app.RecommendFramesButton, 'Ask ZephIR to suggest diverse reference frames for annotation.');
set_tooltip(app.SaveAnnotationsButton, 'Write the current sparse annotations/worldlines for ZephIR.');

app.BookmarkedFramesPanel.Parent = grid;
app.BookmarkedFramesPanel.Layout.Row = 1;
app.BookmarkedFramesPanel.Layout.Column = 2;
app.BookmarkedFramesPanel.Title = 'Reference frame queue';
app.GridLayout8_2.RowHeight = {'1x', 30};
app.BookmarkListBox.Layout.Row = 1;
app.BookmarkListBox.Layout.Column = [1 4];
app.BookmarkNameEditField.Layout.Row = 2;
app.SetBookmarkButton.Layout.Row = 2;
app.GotoBookmarkButton.Layout.Row = 2;
app.DeleteBookmarkButton.Layout.Row = 2;
set_tooltip(app.BookmarkedFramesPanel, 'Reference frames to inspect and annotate before tracking.');
end

function setup_run_tab(app)
app.CreditTab.Title = '3 Run';
hide_if_valid(app.GridLayout14_3);

grid = tagged_grid(app.CreditTab, 'zephir-run-tab-grid');
grid.ColumnWidth = {360, '1x'};
grid.RowHeight = {126, 78, '1x'};
grid.ColumnSpacing = 8;
grid.RowSpacing = 8;
grid.Padding = [8 8 8 8];

quick = tagged_panel(grid, 'zephir-run-preset-panel', 'Run preset');
quick.Layout.Row = 1;
quick.Layout.Column = 1;
quick.FontWeight = 'bold';
quick_grid = tagged_grid(quick, 'zephir-run-preset-grid');
quick_grid.ColumnWidth = {'1x', '1x'};
quick_grid.RowHeight = {22, 54};
quick_grid.Padding = [8 4 8 6];
quick_grid.RowSpacing = 2;

configure_gpu_auto(app);
move_pair(app.AllowRotationsSwitchLabel, app.AllowRotationsSwitch, quick_grid, 1);
move_pair(app.MotionPredictionSwitchLabel, app.MotionPredictionSwitch, quick_grid, 2);

run_panel = tagged_panel(grid, 'zephir-run-execute-panel', 'Execute tracking');
run_panel.Layout.Row = 2;
run_panel.Layout.Column = 1;
run_panel.FontWeight = 'bold';
run_grid = tagged_grid(run_panel, 'zephir-run-execute-grid');
run_grid.ColumnWidth = {'1x'};
run_grid.RowHeight = {'1x'};
run_grid.Padding = [8 8 8 12];
place_button(app.TrackNeuronsButton, run_grid, 1, 1, 'Run ZephIR');
app.TrackNeuronsButton.FontSize = 12;
app.TrackNeuronsButton.BackgroundColor = [0.86 0.16 0.13];
app.TrackNeuronsButton.FontColor = [1 1 1];
set_tooltip(app.TrackNeuronsButton, 'Run ZephIR from saved sparse annotations, or resume from an existing checkpoint.');

app.AdvSetTab.Parent = grid;
app.AdvSetTab.Layout.Row = [1 3];
app.AdvSetTab.Layout.Column = 2;
app.AdvSetTab.AutoResizeChildren = 'on';
compact_advanced_general_tab(app);
delete_stale_run_panels(grid);
end

function review_tab = setup_review_tab(app)
review_tab = findobj(app.DefaultTabGroup, 'Type', 'uitab', ...
    'Tag', 'zephir-review-tab');
if isempty(review_tab) || ~isvalid(review_tab(1))
    review_tab = uitab(app.DefaultTabGroup);
else
    review_tab = review_tab(1);
end
review_tab.Title = '4 ID';
review_tab.Tag = 'zephir-review-tab';

grid = tagged_grid(review_tab, 'zephir-review-tab-grid');
grid.ColumnWidth = {'1x', 280, 260};
grid.RowHeight = {'1x'};
grid.ColumnSpacing = 8;
grid.RowSpacing = 0;
grid.Padding = [8 8 8 8];

app.WorldlineInformationPanel.Parent = grid;
app.WorldlineInformationPanel.Layout.Row = 1;
app.WorldlineInformationPanel.Layout.Column = 1;
app.WorldlineInformationPanel.Title = 'Tracked worldlines';

app.Panel_39.Parent = grid;
app.Panel_39.Layout.Row = 1;
app.Panel_39.Layout.Column = 2;
app.Panel_39.Title = 'ID overlays';

review_actions = uipanel(grid, 'Title', 'Correction tools');
review_actions.Layout.Row = 1;
review_actions.Layout.Column = 3;
review_actions.FontWeight = 'bold';
review_grid = uigridlayout(review_actions);
review_grid.ColumnWidth = {'1x'};
review_grid.RowHeight = {34, 34};
review_grid.Padding = [8 5 8 8];
review_grid.RowSpacing = 6;
place_button(app.ManipulateNeuronsButton, review_grid, 1, 1, ...
    'Batch-adjust selected tracks');
place_button(app.AutosegmentFrameButton, review_grid, 2, 1, ...
    'Autosegment current frame');
set_tooltip(app.ManipulateNeuronsButton, 'Open batch alignment tools for selected worldlines.');
set_tooltip(app.AutosegmentFrameButton, 'Run current-frame segmentation to propose marker locations.');
end

function setup_activity_tab(app)
app.ActivityTab.Title = '5 Activity';
app.GridLayout3.ColumnWidth = {150, '1x'};
app.GridLayout4.RowHeight = {35, 35, 35, '1x', 35};

place_button(app.ExtractActivityButton, app.GridLayout4, 1, 1, ...
    'Extract activity');
set_tooltip(app.ExtractActivityButton, 'Extract fluorescence traces from accepted ZephIR worldlines.');
app.LoadStimulusFileButton.Layout.Row = 2;
app.ScanforIssuesButton.Layout.Row = 3;
app.ActivityListBox.Layout.Row = 4;
app.SaveExitButton.Layout.Row = 5;
end

function setup_video_tracking_copy(app)
if isprop(app, 'OverlayNeuroPALvolCheckBox') && isvalid(app.OverlayNeuroPALvolCheckBox)
    app.OverlayNeuroPALvolCheckBox.Text = 'Overlay NeuroPAL image';
end

if isprop(app, 'OverlayNeuroPALvolCheckBox_2') && isvalid(app.OverlayNeuroPALvolCheckBox_2)
    app.OverlayNeuroPALvolCheckBox_2.Text = 'Overlay NeuroPAL image';
end

if isprop(app, 'EnableinvolumeeditingCheckBox') && isvalid(app.EnableinvolumeeditingCheckBox)
    app.EnableinvolumeeditingCheckBox.Text = 'Enable in-image editing.';
end
end

function configure_gpu_auto(app)
has_gpu = local_gpu_available();

if isvalid(app.UseGPUSwitch)
    try
        if has_gpu
            app.UseGPUSwitch.Value = 'On';
        else
            app.UseGPUSwitch.Value = 'Off';
        end
    catch
        try
            app.UseGPUSwitch.Value = has_gpu;
        catch
        end
    end
    app.UseGPUSwitch.Visible = 'off';
    app.UseGPUSwitch.Enable = 'off';
    set_tooltip(app.UseGPUSwitch, ...
        'ZephIR uses GPU automatically when MATLAB detects one.');
end

if isvalid(app.UseGPUSwitchLabel)
    app.UseGPUSwitchLabel.Visible = 'off';
    app.UseGPUSwitchLabel.Text = '';
end
end

function tf = local_gpu_available()
try
    tf = gpuDeviceCount("available") > 0;
catch
    try
        tf = gpuDeviceCount > 0;
    catch
        tf = false;
    end
end
end

function compact_selected_worldline_panel(app)
if isprop(app.NeuronInformationPanel, 'Scrollable')
    app.NeuronInformationPanel.Scrollable = 'on';
end

app.GridLayout9_2.ColumnWidth = {86, '1x'};
app.GridLayout9_2.RowHeight = {17, 17, 17, 17, 17, 17, 17, 20};
app.GridLayout9_2.RowSpacing = 1;
app.GridLayout9_2.Padding = [8 1 8 1];

place_label_field(app.NameEditFieldLabel, app.NameEditField, 1);
place_label_field(app.ColorLabel, app.ColorButton, 2);
place_label_field(app.ProvenanceEditFieldLabel, app.ProvenanceEditField, 3);
place_label_field(app.XCoordinateEditFieldLabel, app.XCoordinateEditField, 4);
place_label_field(app.YCoordinateEditFieldLabel, app.YCoordinateEditField, 5);
place_label_field(app.ZCoordinateEditFieldLabel, app.ZCoordinateEditField, 6);
place_label_field(app.WorldlineIDEditFieldLabel, app.WorldlineIDEditField, 7);

app.Button.Layout.Row = 8;
app.Button.Layout.Column = 1;
app.Button_2.Layout.Row = 8;
app.Button_2.Layout.Column = 2;

fields = { ...
    app.NameEditField, app.ColorButton, app.ProvenanceEditField, ...
    app.XCoordinateEditField, app.YCoordinateEditField, app.ZCoordinateEditField, ...
    app.WorldlineIDEditField, app.Button, app.Button_2};
for n = 1:numel(fields)
    control = fields{n};
    if isvalid(control) && isprop(control, 'FontSize')
        control.FontSize = 10;
    end
end

labels = { ...
    app.NameEditFieldLabel, app.ColorLabel, app.ProvenanceEditFieldLabel, ...
    app.XCoordinateEditFieldLabel, app.YCoordinateEditFieldLabel, ...
    app.ZCoordinateEditFieldLabel, app.WorldlineIDEditFieldLabel};
for n = 1:numel(labels)
    label = labels{n};
    if isvalid(label) && isprop(label, 'FontSize')
        label.FontSize = 10;
    end
end

set_tooltip(app.NeuronInformationPanel, ...
    'Selected ZephIR worldline metadata and current frame coordinates.');
end

function compact_advanced_general_tab(app)
if isempty(app.GridLayout31) || ~isvalid(app.GridLayout31)
    return
end

app.GridLayout31.ColumnWidth = {'1x'};
app.GridLayout31.RowHeight = {164, '1x', 1};
app.GridLayout31.Padding = [6 6 6 6];

app.TrackingSelectionPanel.Layout.Row = 1;
app.TrackingSelectionPanel.Layout.Column = 1;
app.TrackingSelectionPanel.AutoResizeChildren = 'on';
if isprop(app.TrackingSelectionPanel, 'Scrollable')
    app.TrackingSelectionPanel.Scrollable = 'on';
end
app.GridLayout49.ColumnWidth = {105, '1x', 14, 90, '1x'};
app.GridLayout49.RowHeight = {34, 74};
app.GridLayout49.Padding = [10 8 10 12];
app.GridLayout49.RowSpacing = 5;
app.TrackspecificregionButton.FontSize = 12;
app.TrackspecificneuronsButton.FontSize = 12;
end

function delete_stale_run_panels(parent)
expected_tags = ["zephir-run-preset-panel", "zephir-run-execute-panel"];
stale_titles = ["Run preset", "Execute tracking", "Advanced ZephIR parameters"];
panels = findobj(parent, 'Type', 'uipanel');
for idx = 1:numel(panels)
    panel = panels(idx);
    if ~isvalid(panel)
        continue
    end
    tag = string(panel.Tag);
    title_text = string(panel.Title);
    if any(expected_tags == tag)
        continue
    end
    if any(stale_titles == title_text)
        delete(panel);
    end
end
end

function place_label_field(label, field, row)
label.Layout.Row = row;
label.Layout.Column = 1;
field.Layout.Row = row;
field.Layout.Column = 2;
end

function set_slider_tick_labels(slider, labels)
if isprop(slider, 'MajorTickLabels')
    try
        slider.MajorTickLabels = labels;
    catch
    end
end
end

function wrap_action_callbacks(app)
buttons = { ...
    app.TrackingButton, app.ImportexistingtracksButton, ...
    app.InsertNeuroPALNeuronsButton, app.InsertlastIDdFrameButton, ...
    app.RecommendFramesButton, app.SaveAnnotationsButton, ...
    app.TrackNeuronsButton, app.ExtractActivityButton, ...
    app.ManipulateNeuronsButton, app.AutosegmentFrameButton};

for n = 1:numel(buttons)
    btn = buttons{n};
    if isempty(btn) || ~isvalid(btn) || ~isprop(btn, 'ButtonPushedFcn')
        continue
    end
    if isempty(getappdata(btn, 'zephir_original_button_callback'))
        setappdata(btn, 'zephir_original_button_callback', btn.ButtonPushedFcn);
        btn.ButtonPushedFcn = @(src, event)Program.GUI.invoke_zephir_video_callback(app, src, event);
    end
end
end

function panel = tagged_panel(parent, tag, title_text)
panel = findobj(parent, 'Tag', tag);
if isempty(panel) || ~isvalid(panel(1))
    panel = uipanel(parent, 'Tag', tag);
else
    panel = panel(1);
end
if nargin >= 3
    panel.Title = title_text;
end
end

function grid = tagged_grid(parent, tag)
grid = findobj(parent, 'Tag', tag);
if isempty(grid) || ~isvalid(grid(1))
    grid = uigridlayout(parent, 'Tag', tag);
else
    grid = grid(1);
end
end

function label = tagged_label(parent, tag)
label = findobj(parent, 'Tag', tag);
if isempty(label) || ~isvalid(label(1))
    label = uilabel(parent, 'Tag', tag);
else
    label = label(1);
end
label.WordWrap = 'on';
end

function checkbox = tagged_checkbox(parent, tag, text)
checkbox = findobj(parent, 'Tag', tag);
if isempty(checkbox) || ~isvalid(checkbox(1))
    checkbox = uicheckbox(parent, 'Tag', tag);
else
    checkbox = checkbox(1);
end
checkbox.Text = text;
checkbox.FontSize = 11;
end

function value = viewer_bool(app, key, default_value)
value = default_value;
try
    if isappdata(app.CELL_ID, key)
        value = logical(getappdata(app.CELL_ID, key));
    end
catch
end
end

function set_viewer_bool(app, key, value, should_rerender)
try
    setappdata(app.CELL_ID, key, logical(value));
catch
end

if nargin >= 4 && should_rerender
    rerender_video(app);
end
end

function rerender_video(app)
try
    if isprop(app, 'video_info') && isstruct(app.video_info) && ...
            isfield(app.video_info, 'file') && ~isempty(app.video_info.file)
        app.visual_composer();
    end
catch
end
end

function hide_if_valid(component)
if ~isempty(component) && isvalid(component) && isprop(component, 'Visible')
    component.Visible = 'off';
end
end

function format_axis(ax, label)
ax.Color = [0.02 0.03 0.03];
ax.XColor = [0.75 0.78 0.80];
ax.YColor = [0.75 0.78 0.80];
ax.Toolbar.Visible = 'off';
ax.Box = 'off';
ax.XTick = [];
ax.YTick = [];
ax.Clipping = 'on';
title(ax, label, 'Color', [0.75 0.78 0.80]);
end

function place_button(button, parent, row, col, text)
button.Parent = parent;
button.Layout.Row = row;
button.Layout.Column = col;
button.Text = text;
button.FontSize = 13;
button.Visible = 'on';
end

function move_pair(label, control, parent, col)
label.Parent = parent;
label.Layout.Row = 1;
label.Layout.Column = col;
label.HorizontalAlignment = 'center';
control.Parent = parent;
control.Layout.Row = 2;
control.Layout.Column = col;
end

function set_tooltip(component, tip)
if isempty(component) || ~isvalid(component) || ~isprop(component, 'Tooltip')
    return
end
component.Tooltip = tip;
end
