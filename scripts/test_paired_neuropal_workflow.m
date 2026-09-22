function report = test_paired_neuropal_workflow(c,reference,output)
%TEST_PAIRED_NEUROPAL_WORKFLOW Validate named seeds, tracking and saved activity.
assert(~c.Busy);
if isempty(reference)
    provenance=getappdata(c.Grid,'paired_reference_provenance'); alignment=provenance.alignment;
    assert(~isempty(c.Rows) && all(c.Rows(:,2)==c.Reference.Value));
else
    assert(~isempty(reference.Positions) && ~isempty(reference.Predictions));
    assert(isempty(c.Rows) && isempty(c.Candidates));
    assert(any(strlength(reference.Names)>0) && ~any(reference.Names=="FAILED"));
    reference.align(); assert(reference.Alignment.correlation>.9);
    alignment=reference.Alignment;
    reference.Buttons.use.ButtonPushedFcn([],[]); assert(~isvalid(reference) && ~c.Busy);
end
reference_count=size(c.Rows,1); names=Tracking.NeuronNames.get(c);
assert(numel(names)==reference_count && any(strcmp({names.source},'auto-id')));
c.View.setStage(3); c.First.Value=1; c.Last.Value=25; c.Reference.Value=1;
c.TrackingChannel.Value=0; c.WindowSize.Value=13; c.Epochs.Value=10;
started=tic; c.Buttons.track.ButtonPushedFcn([],[]); tracking_seconds=toc(started);
assert(~c.Busy);
assert(size(c.Rows,1)==25*reference_count && numel(unique(c.Rows(:,1)))==reference_count);
assert(isequal(unique(c.Rows(:,2)),(1:25)'));
assert(isequal(Tracking.NeuronNames.get(c),names));
observations=c.observations();
for i=1:numel(observations)
    record=names([names.id]==observations(i).track_id);
    assert(strcmp(observations(i).name,record.name) && strcmp(observations(i).identity_source,record.source));
end
c.Analysis.Controls.signal.Value=0; c.Analysis.Controls.radius.Value='5 5 1.5';
started=tic; c.Buttons.activity.ButtonPushedFcn([],[]); activity_seconds=toc(started);
assert(~c.Busy);
assert(c.activityCurrent());
c.View.setStage(4); c.Frame.Value=1; c.Slice.Value=12; c.render();
saved=test_named_activity_roundtrip(c,output);
report=struct('neuron_count',reference_count,'tracked_frames',25,'tracking_seconds',tracking_seconds, ...
    'activity_seconds',activity_seconds,'tracking_directory',c.TrackDirectory,'activity_directory',c.ActivityDirectory, ...
    'session_directory',saved.session_directory,'alignment',alignment,'name_roundtrip_passed',true);
file=fopen(fullfile(output,'workflow-validation.json'),'w'); cleanup=onCleanup(@() fclose(file));
fprintf(file,'%s',jsonencode(report));
fprintf('PAIRED_NEUROPAL_WORKFLOW=PASS (%d neurons, 25 frames)\n',reference_count);
end
