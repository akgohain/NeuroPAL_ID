function test_reference_marker_editing(c)
%TEST_REFERENCE_MARKER_EDITING Let center edits pass through neuron markers.
assert(~c.Busy && c.Source.nt>=2 && all([c.Source.nx c.Source.ny c.Source.nz]>=4));
v=c.View;
saved=struct('session',c.Analysis.session(),'rows',c.Rows,'candidates',c.Candidates, ...
    'candidate_frame',c.CandidateFrame,'next_id',c.NextID,'origins',c.Origins,'excluded',c.Excluded, ...
    'frame',c.Frame.Value,'channel',c.Channel.Value,'slice',c.Slice.Value,'cursor',c.Cursor, ...
    'selection',v.Selection,'preferred',v.PreferredID,'stage',v.Stage,'display',v.DisplayMode.Value, ...
    'correct',v.CorrectMode,'add',v.AddMode,'add_identity',v.AddIdentity,'add_frame',v.AddFrame,'add_replace',v.AddReplace, ...
    'snapshots',{v.Review.Snapshots},'snapshot_bytes',v.Review.SnapshotBytes);
cleanup=onCleanup(@() restore(c,saved));
v.Playback.stop(); v.FramePreview.cancel(); v.Preview.cancel();
c.Rows=[11 2 3 3 2 .9 0;12 2 3 3 2 .8 0];
c.Candidates=[21 2 3 3 2 .7 0]; c.CandidateFrame=2; c.NextID=22;
c.Excluded=zeros(0,2); c.Origins=containers.Map('KeyType','char','ValueType','char');
c.ActivityDirectory=''; c.Reference.Value=2; c.Frame.Value=2; c.Channel.Value=0; c.Slice.Value=2;
v.CorrectMode=false; v.AddMode=false; v.Selection=[false 11 2]; v.PreferredID=11; c.render();

% Use the axes' actual point; no synthetic native mouse events are required.
expected=click_center(c);
if isequal(c.Rows(1,3:5),expected)
    c.Rows(:,3)=2; c.Candidates(:,3)=2; c.render();
end
original=c.Rows; pending=c.Candidates;
v.armCorrect(); expected=click_center(c);
v.markerClick(c.Axes,[],[]);
assert(~v.CorrectMode && isequal(v.Selection,[false 11 2]));
assert(isequal(c.Rows(1,3:5),expected) && c.Rows(1,6)==1);
assert(isequal(c.Rows(2,:),original(2,:)) && isequal(c.Candidates,pending));
assert(strcmp(c.Origins('11:2'),'reviewed'));
v.Review.undo(); assert(isequal(c.Rows,original) && isequal(c.Candidates,pending));

% Ordinary clicks still cycle overlapping neurons when no edit is armed.
v.markerClick(c.Axes,[],[]);
assert(isequal(v.Selection,[false 12 2]) && v.PreferredID==12);
assert(isequal(c.Rows,original));

% Candidate centers use the same edit route and retain their pending state.
v.select(c.Candidates(1,:),true); v.armCorrect(); expected=click_center(c);
v.markerClick(c.Axes,[],[]);
assert(~v.CorrectMode && isequal(v.Selection,[true 21 2]));
assert(isequal(c.Candidates(1,3:5),expected) && c.Candidates(1,6)==1);
assert(isequal(c.Rows,original));
v.Review.undo(); assert(isequal(c.Candidates,pending));

% Projection clicks must not consume an edit or change its selected neuron.
v.select(c.Rows(1,:),false); v.armCorrect(); selection=v.Selection;
c.Cursor=[7 8 0;7 8 0]; cursor=c.Cursor;
v.markerClick(v.Projection,[],[]); v.imageClick(v.Projection);
assert(v.CorrectMode && isequal(v.Selection,selection) && isequal(c.Cursor,cursor));
assert(isequal(c.Rows,original) && isequal(c.Candidates,pending));
c.Busy=true; v.markerClick(c.Axes,[],[]); c.Busy=false;
assert(v.CorrectMode && isequal(c.Rows,original));

% Adding on top of a marker adds a center instead of selecting that marker.
v.CorrectMode=false; v.armAdd(); expected=click_center(c);
v.markerClick(v.Projection,[],[]); v.imageClick(v.Projection);
assert(v.AddMode && isequal(c.Rows,original) && isequal(c.Cursor,cursor));
v.markerClick(c.Axes,[],[]);
assert(~v.AddMode && size(c.Rows,1)==size(original,1)+1 && c.NextID==23);
assert(isequal(c.Rows(end,:),[22 2 expected 1 0]) && isequal(c.Candidates,pending));
v.Review.undo(); assert(isequal(c.Rows,original) && c.NextID==22 && isequal(c.Candidates,pending));
fprintf('REFERENCE_MARKER_CORRECT_ADD_UNDO_PROJECTION_BUSY=PASS\n');
end

function xyz=click_center(c)
point=c.Axes.CurrentPoint;
xyz=min([c.Source.nx c.Source.ny c.Source.nz],max(1,[point(1,1:2) round(c.Slice.Value)]));
end

function restore(c,saved)
v=c.View; c.Busy=false;
c.Rows=saved.rows; c.Candidates=saved.candidates; c.CandidateFrame=saved.candidate_frame;
c.NextID=saved.next_id; c.Origins=saved.origins; c.Excluded=saved.excluded; c.Cursor=saved.cursor;
c.Analysis.restoreSession(saved.session);
c.Frame.Value=saved.frame; c.Channel.Value=saved.channel; c.Slice.Value=saved.slice;
v.Selection=saved.selection; v.PreferredID=saved.preferred;
v.CorrectMode=saved.correct; v.AddMode=saved.add; v.AddIdentity=saved.add_identity;
v.AddFrame=saved.add_frame; v.AddReplace=saved.add_replace;
v.DisplayMode.Value=saved.display;
v.Review.Snapshots=saved.snapshots; v.Review.SnapshotBytes=saved.snapshot_bytes;
v.setStage(saved.stage); v.setBusy(false); c.render();
end
