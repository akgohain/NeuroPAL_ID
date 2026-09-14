function test_processing_canvas(app)
%TEST_PROCESSING_CANVAS Keep slice changes inside the processing grid cell.
if nargin < 1, app = Program.app; end
original_tab = app.TabGroup.SelectedTab;
cleanup = onCleanup(@() set(app.TabGroup, 'SelectedTab', original_tab));
app.TabGroup.SelectedTab = app.ImageProcessingTab;
Program.GUIHandling.install_processing_slider_callbacks(app);
Program.Helpers.sync_processing_from_main(app);
Program.Routines.Processing.render();
drawnow;
ax = app.proc_xyAxes;
img = getappdata(ax, 'proc_frame_handle');
position = ax.Position;
nz = size(app.image_data, 3);
for z = [1 nz 2 nz-1 16]
    Program.GUIHandling.handle_processing_primary_zslider_change(app, z, false);
    drawnow;
    assert(isequal(getappdata(ax, 'proc_frame_handle'), img));
    assert(numel(findall(ax, 'Type', 'image')) == 1);
    assert(max(abs(ax.Position - position)) < 1);
    assert(app.proc_zSlider.Value == z);
    assert(app.proc_vert_zSlider.Value == nz + 1 - z);
end
assert(ax.Layout.Row == 1);
assert(ax.Position(2) > app.proc_zSlider.Position(2));
scale = Program.Helpers.processing_axis_scale(app, 'xy');
assert(abs(ax.DataAspectRatio(1)/ax.DataAspectRatio(2) - scale(2)/scale(1)) < 1e-10);
assert(isequal(app.proc_zSlider.MajorTickLabels, ...
    arrayfun(@(v) sprintf('%d', v), app.proc_zSlider.MajorTicks, 'UniformOutput', false)));
Program.GUIHandling.handle_processing_vertical_zslider_change(app, 1, false);
assert(app.proc_zSlider.Value == nz);
Program.GUIHandling.handle_processing_vertical_zslider_change(app, nz, false);
assert(app.proc_zSlider.Value == 1);
Program.GUIHandling.handle_processing_primary_zslider_change(app, 16, false);
for name = {'MajorTicks', 'MajorTickLabels', 'MinorTicks', 'FontSize', 'FontWeight'}
    assert(isequal(app.proc_zSlider.(name{1}), app.ZSlider.(name{1})));
end
preview = getappdata(app.CELL_ID, 'proc_slice_preview');
for z = [3 30 7]
    app.proc_zSlider.ValueChangingFcn(app.proc_zSlider, struct('Value', z));
end
preview.flush();
assert(app.proc_zSlider.Value == 7);
app.proc_zSlider.ValueChangingFcn(app.proc_zSlider, struct('Value', 30));
app.proc_zSlider.ValueChangedFcn(app.proc_zSlider, struct('Value', 16));
preview.flush();
assert(app.proc_zSlider.Value == 16);

fprintf('PROCESSING_CANVAS=PASS\n');
end
