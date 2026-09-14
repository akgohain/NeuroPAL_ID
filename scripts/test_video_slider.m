function test_video_slider()
%TEST_VIDEO_SLIDER Check pending previews, final refresh, and timer cleanup.
old_path = path;
addpath(fullfile(fileparts(mfilename('fullpath')),'fixtures'));
root = tempname;
try
    mkdir(root);
    app = VideoViewTestApp();
catch exception
    if exist(root,'dir') == 7, rmdir(root,'s'); end
    path(old_path);
    rethrow(exception);
end
cleanup = onCleanup(@() local_finish(app,root,old_path));
file = fullfile(root,'video.h5');
data = reshape(uint8(1:3*4*2*1*5),3,4,2,1,5);
h5create(file,'/data',size(data),'Datatype','uint8');
h5write(file,'/data',data);
app.video_info = Program.Helpers.h5_video_info(file);

Program.GUI.handle_zephir_time_slider(app,2,false);
Program.GUI.handle_zephir_time_slider(app,5,false);
worker = getappdata(app.CELL_ID,'video_tslider_timer');
stop(worker);
worker.TimerFcn(worker,[]);
state = getappdata(app.CELL_ID,'video_tslider_state');
assert(state.target == 5 && state.rendered == state.revision);
assert(isempty(app.full_refreshes) && app.tEditField.Value == 5);
handle = findobj(app.xyAxes,'Type','image','Tag','npal_video_xy');
expected = Program.Helpers.scale_video_projection(app,reshape(data(:,:,1,:,5),3,4,1));
assert(isequal(handle.CData,expected));

Program.GUI.handle_zephir_time_slider(app,4,true);
assert(isequal(app.full_refreshes,4) && app.tSlider.Value == 4);
assert(strcmp(worker.Running,'off'));
worker.TimerFcn(worker,[]);
assert(isequal(handle.CData,expected),'A pending preview replaced a final refresh.');
Program.Helpers.clear_video_view_state(app);
assert(~isvalid(worker));
assert(~isappdata(app.CELL_ID,'video_tslider_state'));
assert(~isappdata(app.CELL_ID,'video_projection_cache'));

app.OverlayFrameMIPCheckBox.Value = true;
Program.GUI.handle_zephir_time_slider(app,2,false);
assert(~isappdata(app.CELL_ID,'video_tslider_timer'));
assert(isequal(handle.CData,expected));
Program.GUI.handle_zephir_time_slider(app,2,true);
assert(isequal(app.full_refreshes,[4 2]));
app.OverlayFrameMIPCheckBox.Value = false;
app.OverlaylastIDdframeCheckBox_2.Value = true;
Program.GUI.handle_zephir_time_slider(app,3,false);
assert(~isappdata(app.CELL_ID,'video_tslider_timer'));
app.OverlaylastIDdframeCheckBox_2.Value = false;
Program.GUI.handle_zephir_time_slider(app,3,false);
worker = getappdata(app.CELL_ID,'video_tslider_timer');
Program.GUI.clear_zephir_time_slider(app);
assert(~isvalid(worker));
clear cleanup
fprintf('VIDEO_SLIDER=PASS\n');
end

function local_finish(app,root,old_path)
% Delete fixture objects before removing their class definitions from path.
restore = onCleanup(@() path(old_path));
delete(app);
if exist(root,'dir') == 7, rmdir(root,'s'); end
end
