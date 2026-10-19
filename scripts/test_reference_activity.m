function test_reference_activity(w)
%TEST_REFERENCE_ACTIVITY Check linked traces against the actual extracted run.
assert(~w.Busy && ~isempty(w.Rows) && w.activityCurrent());
view=w.View; analysis=w.Analysis;
saved=struct('session',analysis.session(),'rows',w.Rows,'candidates',w.Candidates, ...
    'candidate_frame',w.CandidateFrame,'origins',copy_map(w.Origins),'next_id',w.NextID, ...
    'excluded',w.Excluded,'activity_rows',w.ActivityRows,'activity_excluded',w.ActivityExcluded, ...
    'activity_settings',w.ActivitySettings,'frame',w.Frame.Value,'channel',w.Channel.Value, ...
    'slice',w.Slice.Value,'preferred',view.PreferredID,'selection',view.Selection, ...
    'label_mode',view.LabelMode.Value,'labels',view.Labels.Value, ...
    'mode',analysis.Mode.Value,'population',logical(analysis.Mode.UserData), ...
    'snapshots',{view.Review.Snapshots},'snapshot_bytes',view.Review.SnapshotBytes,'status',w.Status.Text);
cleanup=onCleanup(@() restore(w,saved));
view.Playback.stop(); view.Preview.cancel(); view.FramePreview.cancel();
if analysis.Mode.UserData, analysis.population(); end
analysis.showActivity();
assert(~isempty(analysis.IDs) && ~isempty(analysis.Frames));
measured=w.Rows(ismember(w.Rows(:,2),analysis.Frames) & ismember(w.Rows(:,1),analysis.IDs),:);
assert(~isempty(measured),'The activity fixture has no accepted observation in its measured range.');
frame=measured(1,2); view.navigate(frame);
view.LabelMode.Value='Selected'; w.render();
assert(numel(findobj(w.Axes,'Tag','reference_label'))<=1);
available=find(view.ListRows(:,8)==0 & ismember(view.ListRows(:,1),analysis.IDs));
assert(~isempty(available) && ~isempty(view.NeuronList.ItemsData));
index=available(min(2,numel(available)));
view.NeuronList.Value=view.NeuronList.ItemsData(index); view.chooseList();
identity=view.PreferredID;
assert(identity==view.ListRows(index,1));
assert(contains(analysis.Axes.Title.String,Tracking.NeuronNames.label(w,identity,true)));
next=min(w.Source.nt,frame+1); if next==frame, next=max(1,frame-1); end
view.navigate(next); assert(view.PreferredID==identity);
select_observation(w,identity,frame);

% Population and each available single-neuron mode use the extracted arrays.
file=fullfile(w.ActivityDirectory,'activity.h5');
analysis.population(); heatmap=findobj(analysis.Axes,'Type','image');
expected=h5read(file,'/dff');
assert(isscalar(heatmap) && isequal(size(heatmap.CData),[numel(analysis.IDs) numel(analysis.Frames)]));
assert(isequaln(double(heatmap.CData),double(expected)));
analysis.population();
assert(~analysis.Mode.UserData && strcmp(analysis.Mode.Enable,'on'));
index=find(analysis.IDs==identity,1); nt=numel(analysis.Frames);
options=analysis.ResultOptions;
assert(isfield(options,'signal_channel') && isfield(options,'reference_channel'));
original_signal=analysis.Controls.signal.Value;
if w.Source.nc>1
    analysis.Controls.signal.Value=mod(original_signal+1,w.Source.nc);
    assert(~w.activityCurrent());
end
modes=cellstr(string(analysis.Mode.Items)); assert(~isempty(modes));
for i=1:numel(modes)
    dataset='';
    switch modes{i}
        case 'ΔF/F', dataset='/dff';
        case 'Fluorescence', dataset='/signal';
        case 'Raw fluorescence', dataset=sprintf('/raw/channel_%d',options.signal_channel);
        case 'Reference fluorescence'
            if options.reference_channel>=0, dataset=sprintf('/raw/channel_%d',options.reference_channel); end
        otherwise, error('Tracking:ActivityTestMode','Add an explicit expected dataset for activity view %s.',modes{i});
    end
    analysis.Mode.Value=modes{i}; analysis.render();
    curve=findobj(analysis.Axes,'Tag','activity_trace');
    assert(isscalar(curve),'Each single-neuron mode must create one activity trace.');
    if isempty(dataset), expected=nan(1,nt);
    else, expected=double(h5read(file,dataset,[index 1],[1 nt])); end
    assert(isequaln(double(curve.YData(:)),expected(:)),modes{i});
    assert(isequal(double(curve.XData(:)),double(analysis.Frames(:))));
end
analysis.Controls.signal.Value=original_signal;
assert(w.activityCurrent());
analysis.Mode.Value=modes{1}; analysis.render();

% Excluding and undoing an observation must invalidate and restore measurements.
select_observation(w,identity,frame);
view.Exclude.Value=~ismember([identity frame],w.Excluded,'rows'); view.exclude();
assert(~w.activityCurrent() && contains(analysis.Axes.Title.String,'out of date'));
view.Review.undo(); assert(w.activityCurrent());
excluded=w.Excluded; rows=w.Rows;
w.Excluded=unique([excluded;identity frame],'rows'); observations=w.observations();
for i=1:numel(observations), observations(i).excluded=false; end
w.mergeTracks(observations);
assert(ismember([identity frame],w.Excluded,'rows') && isequal(w.Rows,rows));
w.Excluded=excluded; assert(w.activityCurrent());
old=analysis.Controls.radius.Value; measurement=analysis.options(); radius=measurement.radius_xyz;
radius(1)=radius(1)+1; analysis.Controls.radius.Value=num2str(radius);
assert(~w.activityCurrent()); analysis.Controls.radius.Value=old;
assert(w.activityCurrent());

session=analysis.session(); old_window=w.WindowSize.Value;
w.WindowSize.Value=2; if old_window==2, w.WindowSize.Value=3; end
analysis.restoreSession(session); assert(w.WindowSize.Value==old_window);
session.activity_current=false; analysis.restoreSession(session); assert(~w.activityCurrent());
session.activity_current=true; analysis.restoreSession(session); assert(w.activityCurrent());
assert(session.next_id==w.NextID);

% Deleting a track removes its exclusion/origins but never reuses its ID.
select_observation(w,identity,frame);
next_id=w.NextID; rows=w.Rows; origins=copy_map(w.Origins);
w.Excluded=unique([excluded;identity frame],'rows'); view.removeSelection();
assert(~any(w.Rows(:,1)==identity) && ~any(w.Excluded(:,1)==identity));
assert(~any(startsWith(w.Origins.keys,sprintf('%d:',identity))));
assert(w.NextID==next_id && ~w.activityCurrent());
w.Rows=rows; w.Origins=origins; w.Excluded=excluded; view.PreferredID=identity;
observations=w.observations(); w.NextID=next_id+1; w.setRows(observations);
assert(w.NextID==next_id+1);
clear cleanup
assert(isequal(w.Rows,saved.rows) && isequal(w.Excluded,saved.excluded) && w.NextID==saved.next_id);
assert(isequal(sort(w.Origins.keys),sort(saved.origins.keys)));
assert(isequal(values(w.Origins,sort(w.Origins.keys)),values(saved.origins,sort(saved.origins.keys))));
assert(isequaln(view.Review.Snapshots,saved.snapshots) && view.Review.SnapshotBytes==saved.snapshot_bytes);
assert(w.activityCurrent());
fprintf('REFERENCE_ACTIVITY_LINKS_EXTRACTED_ARRAYS_INVALIDATION_SESSION=PASS\n');
end

function select_observation(w,identity,frame)
index=find(w.Rows(:,1)==identity & w.Rows(:,2)==frame,1);
assert(~isempty(index),'Select an accepted observation inside the measured range.');
w.View.select(w.Rows(index,:),false);
assert(isequal(w.View.Selection,[0 identity frame]));
end

function copy=copy_map(original)
copy=containers.Map('KeyType',original.KeyType,'ValueType',original.ValueType);
keys=original.keys;
for i=1:numel(keys), copy(keys{i})=original(keys{i}); end
end

function restore(w,saved)
view=w.View; analysis=w.Analysis;
view.Playback.stop(); view.Preview.cancel(); view.FramePreview.cancel();
w.Rows=saved.rows; w.Candidates=saved.candidates; w.CandidateFrame=saved.candidate_frame;
w.Origins=saved.origins; w.Excluded=saved.excluded; w.NextID=saved.next_id;
analysis.restoreSession(saved.session);
w.ActivityRows=saved.activity_rows; w.ActivityExcluded=saved.activity_excluded; w.ActivitySettings=saved.activity_settings;
w.NextID=saved.next_id; w.Frame.Value=saved.frame; w.Channel.Value=saved.channel; w.Slice.Value=saved.slice;
view.PreferredID=saved.preferred; view.Selection=saved.selection;
view.LabelMode.Value=saved.label_mode; view.Labels.Value=saved.labels;
analysis.Mode.Value=saved.mode;
if logical(analysis.Mode.UserData)~=saved.population, analysis.population(); end
view.Review.Snapshots=saved.snapshots; view.Review.SnapshotBytes=saved.snapshot_bytes;
analysis.PlotKey={}; w.render(); w.Status.Text=saved.status;
end
