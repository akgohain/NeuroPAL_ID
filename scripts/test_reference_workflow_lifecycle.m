function test_reference_workflow_lifecycle()
%TEST_REFERENCE_WORKFLOW_LIFECYCLE Preserve close ownership through failure and replacement.
folder=tempname; mkdir(folder); folderCleanup=onCleanup(@() rmdir(folder,'s'));
window=uifigure('Visible','off'); windowCleanup=onCleanup(@() delete_window(window));
group=uitabgroup(window); previousTab=uitab(group,'Title','Main'); videoTab=uitab(group,'Title','Video');
legacy=uigridlayout(videoTab,[1 1]); fileMenu=uimenu(window,'Text','File');
app=struct('CELL_ID',window,'TabGroup',group,'VideoTrackingTab',videoTab, ...
    'VideoGridLayout',legacy,'XY',struct('FontSize',10),'OpenMenu',uimenu(fileMenu,'Text','Open'));
group.SelectedTab=previousTab;
setappdata(window,'workflow_lifecycle_closes',0);
setappdata(window,'workflow_lifecycle_wrappers',0);
window.CloseRequestFcn={@record_close,'original'};
baseline=window.CloseRequestFcn; % Graphics can normalize callback-cell orientation.
window.WindowKeyPressFcn=@(~,~) []; baselineKey=window.WindowKeyPressFcn;
source=struct('file',fullfile(folder,'frames.h5'),'source_id','workflow-lifecycle', ...
    'nx',4,'ny',3,'nz',2,'nc',1,'nt',2,'dtype','single', ...
    'axis_order','TZCYX','spacing_measured',false,'spacing_um_xyz',[1 1 1]);
h5create(source.file,'/data',[3 4 2 1 2],'Datatype','single');
h5write(source.file,'/data',ones(3,4,2,1,2,'single'));

% A reader-construction failure must preserve its original exception and handler.
bad=rmfield(source,'dtype'); expected=capture_failure(@() Tracking.FrameReader(bad));
failure=capture_failure(@() Tracking.ReferenceWorkflow(app,bad));
assert(strcmp(failure.identifier,expected.identifier) && strcmp(failure.message,expected.message));
assert(isequal(window.CloseRequestFcn,baseline) && strcmp(legacy.Visible,'on'));
assert(group.SelectedTab==previousTab);

% A late construction failure must also dispose the completed view and playback.
windows=numel(findall(groot,'Type','figure'));
workers=numel(timerfindall('Name','NeuroPAL video playback'));
children=numel(videoTab.Children);
pixels=ones(3,4,2,1,2,'single'); pixels(1)=NaN; h5write(source.file,'/data',pixels);
failure=capture_failure(@() Tracking.ReferenceWorkflow(app,source));
assert(strcmp(failure.identifier,'Tracking:Frame'));
assert(isequal(window.CloseRequestFcn,baseline) && isequal(window.WindowKeyPressFcn,baselineKey));
assert(strcmp(legacy.Visible,'on') && isempty(videoTab.Tag) && group.SelectedTab==previousTab);
assert(numel(videoTab.Children)==children && numel(findall(groot,'Type','figure'))==windows);
assert(numel(timerfindall('Name','NeuroPAL video playback'))==workers);
h5write(source.file,'/data',ones(3,4,2,1,2,'single'));

% Deleting an older workflow cannot overwrite a newer workflow's handler.
first=Tracking.ReferenceWorkflow(app,source); firstCleanup=onCleanup(@() delete_workflow(first));
firstClose=window.CloseRequestFcn;
second=Tracking.ReferenceWorkflow(app,source); secondCleanup=onCleanup(@() delete_workflow(second));
secondClose=window.CloseRequestFcn; reader=first.Reader; worker=first.View.Playback.Worker;
first.App=[]; delete(first);
assert(~isvalid(reader) && ~isvalid(worker));
assert(isequal(window.CloseRequestFcn,secondClose));
secondClose(window,[]); assert(getappdata(window,'workflow_lifecycle_closes')==1);
delete(second);
assert(isequal(window.CloseRequestFcn,firstClose));
restored=window.CloseRequestFcn; restored(window,[]);
assert(getappdata(window,'workflow_lifecycle_closes')==2);

% A later wrapper keeps ownership and can forward through a disposed workflow.
window.CloseRequestFcn=baseline;
workflow=Tracking.ReferenceWorkflow(app,source); workflowCleanup=onCleanup(@() delete_workflow(workflow));
previous=window.CloseRequestFcn;
wrapper=@(src,event) forward_close(src,event,previous);
window.CloseRequestFcn=wrapper;
wrapper=window.CloseRequestFcn;
delete(workflow.View); delete(workflow);
assert(isequal(window.CloseRequestFcn,wrapper));
wrapper(window,[]);
assert(getappdata(window,'workflow_lifecycle_wrappers')==1);
assert(getappdata(window,'workflow_lifecycle_closes')==3);

% A queued callback after figure disposal cannot dereference the retired workflow.
delete(window); previous(window,[]);
fprintf('REFERENCE_WORKFLOW_FAILED_REPLACED_CLOSE_LIFECYCLE=PASS\n');
end

function failure=capture_failure(action)
try
    action();
catch failure
    return;
end
error('Tracking:LifecycleTestMissingFailure','Expected construction failure.');
end

function record_close(src,~,token)
assert(strcmp(token,'original'));
setappdata(src,'workflow_lifecycle_closes',getappdata(src,'workflow_lifecycle_closes')+1);
end

function forward_close(src,event,previous)
setappdata(src,'workflow_lifecycle_wrappers',getappdata(src,'workflow_lifecycle_wrappers')+1);
Tracking.ReferenceWorkflow.invokeClose(previous,src,event);
end

function delete_workflow(workflow)
if isvalid(workflow), delete(workflow); end
end

function delete_window(window)
if isvalid(window), delete(window); end
end
