function test_reference_safety(c)
%TEST_REFERENCE_SAFETY Keep pending work, reviewed centers and restore operations safe.
assert(~c.Busy && c.Source.nt>=5);
saved=struct('session',c.Analysis.session(),'rows',c.Rows,'candidates',c.Candidates, ...
    'candidate_frame',c.CandidateFrame,'next_id',c.NextID,'history',{c.History},'provenance',c.Provenance, ...
    'frame',c.Frame.Value,'channel',c.Channel.Value,'slice',c.Slice.Value,'selection',c.View.Selection, ...
    'preferred',c.View.PreferredID,'origins',c.Origins,'excluded',c.Excluded, ...
    'cancelled',c.Cancelled, ...
    'snapshots',{c.View.Review.Snapshots},'snapshot_bytes',c.View.Review.SnapshotBytes);
cleanup=onCleanup(@() restore(c,saved));
folder=tempname; mkdir(folder); folder_cleanup=onCleanup(@() rmdir(folder,'s'));
c.Rows=zeros(0,7); c.Candidates=[11 2 2 2 2 .9 0]; c.CandidateFrame=2;
expected=c.Candidates;
expect(@() c.save(folder),'Tracking:PendingCandidates');
expect(@() c.load(fullfile(folder,'missing.h5')),'Tracking:ExistingSeeds');
expect(@() c.loadProgress(),'Tracking:PendingCandidates');
expect(@() c.extractActivity(),'Tracking:PendingCandidates');
expect(@() c.exportActivity(folder),'Tracking:PendingCandidates');
assert(isempty(c.Rows) && isequal(c.Candidates,expected) && numel(dir(folder))==2);
c.Cancelled=true; expect(@() c.checkDetectionContext(c.Frame.Value,c.Channel.Value),'Tracking:Cancelled');
c.Cancelled=false; expect(@() c.checkDetectionContext(c.Frame.Value+1,c.Channel.Value),'Tracking:StaleDetection');
assert(isempty(c.Rows) && isequal(c.Candidates,expected));
c.Candidates=zeros(0,7);

Tracking.ReferenceFrames.open(c);
response=struct('frames',[1 3],'channel',0,'source_id',c.Source.source_id,'frame_index_base',0,'method','test');
Tracking.ReferenceFrames.restore(c,response);
controls=getappdata(c.Grid,'reference_frames_controls'); assert(~isempty(controls.list.Items));
Tracking.ReferenceFrames.restore(c,[]);
assert(isempty(controls.list.Items) && strcmp(controls.use.Enable,'off')); Tracking.ReferenceFrames.use(c);
Tracking.ReferenceFrames.restore(c,response);
if c.Source.nc>1
    frame=c.Frame.Value; channel=c.Channel.Value; controls.channel.Value=1;
    callback=controls.channel.ValueChangedFcn; callback(controls.channel,[]);
    assert(isempty(controls.list.Items) && strcmp(controls.use.Enable,'off'));
    Tracking.ReferenceFrames.use(c); assert(c.Frame.Value==frame && c.Channel.Value==channel);
end
Tracking.ReferenceFrames.restore(c,response);

before=c.Analysis.session(); bad=before; bad.first=min(2,c.Source.nt);
bad.reference_frames.source_id='other-recording';
expect(@() c.Analysis.restoreSession(bad),'Tracking:ReferenceFrames');
assert(isequaln(before,c.Analysis.session()));
bad=before; bad.first=min(2,c.Source.nt); bad.detection_settings=struct('use_model_default',false,'score_threshold',2);
expect(@() c.Analysis.restoreSession(bad),'Tracking:DetectionSettings');
assert(isequaln(before,c.Analysis.session()));
bad=before; bad.last=c.Source.nt+1;
expect(@() c.Analysis.restoreSession(bad),'Tracking:SessionSettings');
assert(isequaln(before,c.Analysis.session()));

c.Rows=[11 2 2 2 2 1 0;12 3 3 3 2 .5 0]; c.Excluded=[11 2]; c.NextID=13;
c.Origins=containers.Map({'11:2','12:3'},{'confirmed','zephir'});
names=struct('id',{11,12},'name',{'AVAL','AVAR'},'confidence',{1,1},'source',{'reviewed','reviewed'});
Tracking.NeuronNames.set(c,names);
incoming=c.observations();
incoming(1).x=2.5; incoming(1).provenance='zephir'; incoming(1).excluded=false; incoming(1).name='old-name';
incoming(2).x=3.25; incoming(2).name='old-name';
incoming(3)=incoming(1); incoming(3).t=4;
c.mergeTracks(incoming);
assert(isequal(c.Rows(1,:),[11 2 2 2 2 1 0]));
assert(c.Rows(c.Rows(:,1)==12 & c.Rows(:,2)==3,3)==3.25);
assert(any(c.Rows(:,1)==11 & c.Rows(:,2)==4) && ismember([11 2],c.Excluded,'rows'));
assert(strcmp(c.Origins('11:2'),'confirmed') && isequal(Tracking.NeuronNames.get(c),names));
old=c.Rows; c.mergeTracks(c.observations()); assert(isequal(c.Rows,old));

output=c.save(folder); provenance=fullfile(output.directory,'provenance.json');
record=jsondecode(fileread(provenance)); record.detection.session.detection_settings.score_threshold=2;
fid=fopen(provenance,'w'); guard=onCleanup(@() fclose(fid)); fwrite(fid,jsonencode(record),'char'); clear guard
c.Rows=zeros(0,7); before=c.Analysis.session(); next=c.NextID; origins=c.Origins;
expect(@() c.load(fullfile(output.directory,'annotations.h5')),'Tracking:DetectionSettings');
assert(isempty(c.Rows) && c.NextID==next && isequal(c.Origins,origins) && isequaln(before,c.Analysis.session()));
fprintf('REFERENCE_PENDING_CHECKPOINT_TRANSACTIONAL_RESTORE=PASS\n');
end

function restore(c,saved)
c.Rows=saved.rows; c.Candidates=saved.candidates; c.CandidateFrame=saved.candidate_frame;
c.NextID=saved.next_id; c.History=saved.history; c.Provenance=saved.provenance;
c.Origins=saved.origins; c.Excluded=saved.excluded;
c.Cancelled=saved.cancelled;
c.Analysis.restoreSession(saved.session); c.Frame.Value=saved.frame; c.Channel.Value=saved.channel; c.Slice.Value=saved.slice;
c.View.Selection=saved.selection; c.View.PreferredID=saved.preferred;
c.View.Review.Snapshots=saved.snapshots; c.View.Review.SnapshotBytes=saved.snapshot_bytes;
window=getappdata(c.Grid,'reference_frames_window'); if ~isempty(window) && isvalid(window), window.Visible='off'; end
c.render();
end

function expect(callback,identifier)
try, callback(); catch ME, assert(strcmp(ME.identifier,identifier),ME.message); return; end
error('test:MissingError','Expected %s',identifier);
end
