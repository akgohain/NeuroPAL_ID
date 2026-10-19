function test_reference_constraints(c)
%TEST_REFERENCE_CONSTRAINTS Keep neuron identities across multiple reference frames.
assert(~c.Busy && c.Source.nt>=5);
saved=struct('session',c.Analysis.session(),'rows',c.Rows,'candidates',c.Candidates, ...
    'candidate_frame',c.CandidateFrame,'next_id',c.NextID,'history',{c.History},'provenance',c.Provenance, ...
    'frame',c.Frame.Value,'channel',c.Channel.Value,'slice',c.Slice.Value,'selection',c.View.Selection, ...
    'preferred',c.View.PreferredID,'origins',c.Origins,'excluded',c.Excluded, ...
    'add_mode',c.View.AddMode,'add_identity',c.View.AddIdentity,'add_frame',c.View.AddFrame,'add_replace',c.View.AddReplace,'cursor',c.Cursor, ...
    'snapshots',{c.View.Review.Snapshots},'snapshot_bytes',c.View.Review.SnapshotBytes);
cleanup=onCleanup(@() restore(c,saved));
c.View.Playback.stop(); c.History={}; c.Provenance=struct();
c.Origins=containers.Map('KeyType','char','ValueType','char'); c.Excluded=zeros(0,2);
c.Rows=[11 2 2 2 2 .9 0;12 2 3 3 2 .8 min(1,c.Source.nc-1)];
c.Candidates=[13 4 2.25 2 2 .7 0;14 4 3.25 3 2 .6 min(1,c.Source.nc-1)];
c.NextID=15; c.CandidateFrame=4; c.Reference.Value=2; c.First.Value=1; c.Last.Value=5;
c.Frame.Value=4; c.Channel.Value=0; c.render();
assert(Tracking.ReferenceConstraints.needed(c));
assert(strcmp(c.Buttons.accept.Text,'Match neurons…'));
expect(@() c.accept(),'Tracking:ReferenceIdentity');
expect(@() Tracking.ReferenceConstraints.assign(c,99,11),'Tracking:ReferenceCandidate');
expect(@() Tracking.ReferenceConstraints.assign(c,13,99),'Tracking:ReferenceIdentity');
c.Frame.Value=3;
expect(@() Tracking.ReferenceConstraints.assign(c,13,11),'Tracking:CandidateView');
c.Frame.Value=4; c.render();
Tracking.ReferenceConstraints.assign(c,13,11);
assert(size(c.Rows,1)==3 && size(c.Candidates,1)==1 && c.Reference.Value==2 && c.NextID==15);
assert(isequal(c.Rows(end,:),[11 4 2.25 2 2 1 0]) && strcmp(c.Origins('11:4'),'reviewed'));
expect(@() Tracking.ReferenceConstraints.assign(c,14,11),'Tracking:ExistingObservation');
Tracking.ReferenceConstraints.open(c);
controls=getappdata(c.Grid,'reference_constraints_controls');
assert(isequal(controls.target.ItemsData,[11 12]) && numel(controls.list.Items)==1);
c.View.setBusy(true); assert(strcmp(controls.apply.Enable,'off')); c.View.setBusy(false);
Tracking.ReferenceConstraints.assign(c,14,12);
assert(isempty(c.Candidates) && numel(unique(c.Rows(:,1)))==2 && c.Reference.Value==2);
c.checkTrackingSeeds(true);
original=c.Rows; c.Candidates=[15 4 2.5 2 2 .5 0]; c.NextID=16;
Tracking.ReferenceConstraints.assign(c,15,11,true);
assert(c.Rows(c.Rows(:,1)==11 & c.Rows(:,2)==4,3)==2.5);
c.View.Review.undo();
assert(isequal(c.Rows,original) && isequal(c.Candidates,[15 4 2.5 2 2 .5 0]));
c.Candidates=zeros(0,7);
c.Frame.Value=5; c.render(); Tracking.ReferenceConstraints.place(c,12);
assert(c.View.AddMode && c.View.AddIdentity==12 && c.View.AddFrame==5);
c.Cursor=[3.5 3 2;3.5 3 2]; c.Slice.Value=2; c.View.AddMode=false; c.add();
assert(isequal(c.Rows(end,:),[12 5 3.5 3 2 1 c.Channel.Value]) && c.NextID==16 && c.Reference.Value==2);
assert(strcmp(c.Origins('12:5'),'reviewed'));
before=c.Rows; Tracking.ReferenceConstraints.place(c,11); c.Frame.Value=4;
expect(@() c.add(),'Tracking:ReferenceIdentity'); assert(isequal(c.Rows,before)); c.View.AddMode=false;
c.Frame.Value=5; c.render();
names=struct('id',{11,12},'name',{'AVAL','AVAR'},'confidence',{1,1},'source',{'reviewed','reviewed'});
Tracking.NeuronNames.set(c,names);

response=struct('frames',[1 3 3],'channel',0,'source_id',c.Source.source_id,'frame_index_base',0,'method','test');
Tracking.ReferenceFrames.restore(c,response); Tracking.ReferenceFrames.open(c);
recommendations=getappdata(c.Grid,'reference_frames_controls');
assert(isequal(recommendations.list.ItemsData,[2 4]));
assert(all(contains(recommendations.list.Items,'2 reference centers')));
manual=c.Rows; c.Rows=[manual;99 1 2 2 2 0 0;99 2 2 2 2 0 0;99 4 2 2 2 0 0];
keys={'99:1','99:2','99:4'}; for i=1:numel(keys), c.Origins(keys{i})='zephir'; end
propagated=response; propagated.frames=[0 1 3]; Tracking.ReferenceFrames.populate(c,propagated);
assert(strcmp(recommendations.list.Items{1},'Frame 1'));
assert(all(contains(recommendations.list.Items(2:3),'2 reference centers')));
c.Rows=manual; remove(c.Origins,keys); Tracking.ReferenceFrames.restore(c,response);
for bad={struct('frames',[1 c.Source.nt],'channel',0),struct('frames',1,'channel',c.Source.nc), ...
        struct('frames',1,'channel',0,'frame_index_base',1),struct('frames',1,'channel',0,'source_id','different')}
    expect(@() Tracking.ReferenceFrames.restore(c,bad{1}),'Tracking:ReferenceFrames');
end
folder=tempname; mkdir(folder); folder_cleanup=onCleanup(@() rmdir(folder,'s'));
expected=c.Rows; output=c.save(folder); c.Rows=zeros(0,7); c.load(fullfile(output.directory,'annotations.h5'));
assert(isequal(c.Rows,expected) && c.Reference.Value==2);
stored=getappdata(c.Grid,'reference_frame_recommendations'); assert(isequal(stored.frames,[1 3]));
observations=c.observations(); assert(all(ismember({observations.name},{'AVAL','AVAR'})));
c.checkTrackingSeeds(true);
fprintf('MULTI_REFERENCE_MATCH_IDENTITY_UNDO_SESSION=PASS\n');
end

function restore(c,saved)
c.Rows=saved.rows; c.Candidates=saved.candidates; c.CandidateFrame=saved.candidate_frame;
c.NextID=saved.next_id; c.History=saved.history; c.Provenance=saved.provenance;
c.Origins=saved.origins; c.Excluded=saved.excluded;
c.Analysis.restoreSession(saved.session); c.Frame.Value=saved.frame; c.Channel.Value=saved.channel; c.Slice.Value=saved.slice;
c.View.Selection=saved.selection; c.View.PreferredID=saved.preferred;
c.View.AddMode=saved.add_mode; c.View.AddIdentity=saved.add_identity;
c.View.AddFrame=saved.add_frame; c.View.AddReplace=saved.add_replace; c.Cursor=saved.cursor;
c.View.Review.Snapshots=saved.snapshots; c.View.Review.SnapshotBytes=saved.snapshot_bytes;
for key={'reference_constraints_window','reference_frames_window'}
    window=getappdata(c.Grid,key{1}); if ~isempty(window) && isvalid(window), window.Visible='off'; end
end
c.render();
end

function expect(callback,identifier)
try, callback(); catch ME, assert(strcmp(ME.identifier,identifier),ME.message); return; end
error('test:MissingError','Expected %s',identifier);
end
