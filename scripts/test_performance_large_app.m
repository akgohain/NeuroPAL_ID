function report = test_performance_large_app(image_path, video_path, output)
%TEST_PERFORMANCE_LARGE_APP Exercise repeated image loads and live H5 navigation.
arguments
    image_path (1,1) string
    video_path (1,1) string
    output (1,1) string
end
if ~isfolder(output), mkdir(output); end
app = visualize_light;
cleanup = onCleanup(@() delete(app));
report = struct();
for run = 1:2
    started = tic;
    Program.Routines.open(char(image_path));
    report.open_seconds(run) = toc(started);
    assert(~isempty(app.image_data));
    assert(isempty(app.image_data_zscored));
    raw = app.image_data;
    usage = whos('raw');
    report.raw_bytes = usage.bytes;
    view = Program.Helpers.main_display_view_cache(app);
    pixels = view.display_slice;
    projection = view.max_projection;
    usage = whos('pixels','projection');
    report.display_pixel_bytes = sum([usage.bytes]);
    assert(report.display_pixel_bytes == 2*size(raw,1)*size(raw,2)*3);
    clear raw view pixels projection
    fprintf('LARGE_APP image open %d: %.3f seconds\n',run,report.open_seconds(run));
end
processed_source = string(app.image_file);
exportapp(app.CELL_ID,fullfile(output,'image.png'));
started = tic;
Program.Routines.Videos.load(char(video_path));
report.video_open_seconds = toc(started);
assert(isempty(app.video_info.bitDepth) || isscalar(app.video_info.bitDepth) || ...
    ischar(app.video_info.bitDepth) || isstring(app.video_info.bitDepth));
report.video_dimensions = [app.video_info.ny app.video_info.nx app.video_info.nz app.video_info.nc app.video_info.nt];
app.OverlayFrameMIPCheckBox.Value = false;
app.OverlaylastIDdframeCheckBox_2.Value = false;
for tab = reshape(app.TabGroup.Children,1,[])
    if strcmp(tab.Title,'Video Tracking'), app.TabGroup.SelectedTab = tab; end
end
image_handle = findobj(app.xyAxes,'Tag','npal_video_xy');
assert(isscalar(image_handle));
report.video_slice_seconds = zeros(1,10);
for i = 1:10
    target = mod(i*17-1,app.video_info.nt)+1;
    Program.GUI.handle_zephir_time_slider(app,target,false);
    drawnow;
    started = tic;
    Program.GUI.handle_zephir_time_slider(app,target,true);
    drawnow;
    report.video_slice_seconds(i) = toc(started);
    assert(isequal(findobj(app.xyAxes,'Tag','npal_video_xy'),image_handle));
    cache = getappdata(app.CELL_ID,'video_projection_cache');
    assert(cache.bytes <= 32*1024^2);
end
report.video_slice_p95_seconds = prctile(report.video_slice_seconds,95);
exportapp(app.CELL_ID,fullfile(output,'video.png'));
Program.GUI.clear_zephir_time_slider(app);
assert(~isappdata(app.CELL_ID,'video_tslider_timer'));
test_processing_save_cancel(app,processed_source);
report.status = 'passed';
fid = fopen(fullfile(output,'report.json'),'w');
file_cleanup = onCleanup(@() fclose(fid));
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
fprintf('LARGE_PERFORMANCE_APP=PASS video p95=%.3f seconds\n',report.video_slice_p95_seconds);
end
