function test_video_playback_lifecycle()
%TEST_VIDEO_PLAYBACK_LIFECYCLE Keep failed/replaced playback out of keyboard dispatch.
window=uifigure('Visible','off');
cleanup=onCleanup(@() delete_window(window));
setappdata(window,'playback_test_keys',0);
setappdata(window,'playback_test_wrappers',0);
baseline={@record_key,'existing-dispatcher'};
window.WindowKeyPressFcn=baseline;
baseline=window.WindowKeyPressFcn;
app=struct('CELL_ID',window,'TabGroup',struct('SelectedTab',1),'VideoTrackingTab',2);
view=struct('Controller',struct('App',app,'Source',struct('nt',3)));
event=struct('Key','leftarrow','Modifier',{{}});

% Failed outer construction may destroy the view before playback cleanup runs.
parent=uipanel(window); previousResize=@(~,~) [];
parent.SizeChangedFcn=previousResize;
try
    fail_after_install(view,parent);
    error('Tracking:LifecycleTestMissingFailure','Expected construction failure.');
catch exception
    assert(strcmp(exception.identifier,'Tracking:LifecycleTestFailure'));
end
assert(isequal(window.WindowKeyPressFcn,baseline));
assert(isequal(parent.SizeChangedFcn,previousResize));
failed=getappdata(window,'playback_test_failed_key');
failed(window,event);
assert(getappdata(window,'playback_test_keys')==1);
assert(~isvalid(getappdata(window,'playback_test_failed_worker')));
delete(parent);

% Disposing an older instance must preserve the replacement's current callback.
firstParent=uipanel(window); secondParent=uipanel(window);
first=Tracking.VideoPlayback(view,firstParent); firstKey=first.KeyCallback;
second=Tracking.VideoPlayback(view,secondParent); secondKey=second.KeyCallback;
delete(first);
assert(isequal(window.WindowKeyPressFcn,secondKey));
secondKey(window,event);
assert(getappdata(window,'playback_test_keys')==2);
% Even a live playback with a disposed view must delegate to the original owner.
second.View=[]; second.Playing=true; tick=second.Worker.TimerFcn;
tick([],[]); assert(~second.Playing);
secondKey(window,event);
assert(getappdata(window,'playback_test_keys')==3);
delete(second);
assert(isequal(window.WindowKeyPressFcn,firstKey));
restored=window.WindowKeyPressFcn; restored(window,event);
assert(getappdata(window,'playback_test_keys')==4);
delete(firstParent); delete(secondParent);

% A dispatcher installed later (such as ManualID) must retain ownership and state.
window.WindowKeyPressFcn=baseline;
parent=uipanel(window); playback=Tracking.VideoPlayback(view,parent);
previous=playback.KeyCallback;
wrapper=@(src,event) forward_key(src,event,previous);
window.WindowKeyPressFcn=wrapper;
playback.View=[]; delete(playback);
assert(isequal(window.WindowKeyPressFcn,wrapper));
wrapper(window,event);
assert(getappdata(window,'playback_test_wrappers')==1);
assert(getappdata(window,'playback_test_keys')==5);
delete(parent);

% Parent disposal also retires queued timer, resize, and keyboard callbacks.
window.WindowKeyPressFcn=baseline;
parent=uipanel(window); playback=Tracking.VideoPlayback(view,parent);
key=playback.KeyCallback; resize=playback.ResizeCallback;
worker=playback.Worker; tick=worker.TimerFcn;
delete(parent);
assert(~isvalid(playback) && ~isvalid(worker));
assert(isequal(window.WindowKeyPressFcn,baseline));
resize([],[]); tick([],[]); Tracking.VideoPlayback.deleteIfAlive(playback);
key(window,event);
assert(getappdata(window,'playback_test_keys')==6);
fprintf('VIDEO_PLAYBACK_FAILED_REPLACED_CALLBACK_LIFECYCLE=PASS\n');
end

function fail_after_install(view,parent)
playback=Tracking.VideoPlayback(view,parent);
cleanup=onCleanup(@() delete(playback));
setappdata(view.Controller.App.CELL_ID,'playback_test_failed_key',playback.KeyCallback);
setappdata(view.Controller.App.CELL_ID,'playback_test_failed_worker',playback.Worker);
playback.View=[];
error('Tracking:LifecycleTestFailure','Simulated failure after playback installation.');
end

function record_key(src,event,token)
assert(strcmp(token,'existing-dispatcher') && strcmp(event.Key,'leftarrow'));
setappdata(src,'playback_test_keys',getappdata(src,'playback_test_keys')+1);
end

function forward_key(src,event,previous)
setappdata(src,'playback_test_wrappers',getappdata(src,'playback_test_wrappers')+1);
Tracking.VideoPlayback.invokeKey(previous,src,event);
end

function delete_window(window)
if isvalid(window), delete(window); end
end
