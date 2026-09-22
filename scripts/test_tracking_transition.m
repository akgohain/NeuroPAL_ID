function test_tracking_transition(c)
%TEST_TRACKING_TRANSITION Check seed guards without starting a tracking job.
assert(~c.Busy && c.Source.nt>=4);
saved=struct('rows',c.Rows,'candidates',c.Candidates,'origins',c.Origins, ...
    'first',c.First.Value,'last',c.Last.Value,'reference',c.Reference.Value,'stage',c.View.Stage, ...
    'snapshots',{c.View.Review.Snapshots},'snapshot_bytes',c.View.Review.SnapshotBytes);
cleanup=onCleanup(@() restore(c,saved));
c.View.Playback.stop(); c.View.setStage(2);
c.Rows=zeros(0,7); c.Candidates=zeros(0,7);
c.Origins=containers.Map('KeyType','char','ValueType','char');
c.First.Value=1; c.Last.Value=4; c.Reference.Value=2;
c.View.Review.Snapshots={struct('sentinel',true)};
expect(@() c.checkTrackingSeeds(false),'Tracking:NoSeeds');
expect(@() c.track(),'Tracking:NoSeeds');

seeds=[1 2 1 1 1 .9 0; 2 2 1 1 1 .8 min(1,c.Source.nc-1)];
c.Candidates=seeds;
expect(@() c.checkTrackingSeeds(false),'Tracking:PendingCandidates');
c.Rows=seeds;
expect(@() c.track(),'Tracking:PendingCandidates');
assert(isequal(c.Rows,seeds) && isequal(c.Candidates,seeds));
c.Candidates=zeros(0,7);
c.checkTrackingSeeds(true);
callback=c.Buttons.continueTracking.ButtonPushedFcn;
callback(c.Buttons.continueTracking,[]);
assert(c.View.Stage==3 && ~c.Busy);
c.View.setStage(2); c.Busy=true;
callback(c.Buttons.continueTracking,[]);
assert(c.View.Stage==2 && c.Busy); c.Busy=false;
c.View.setBusy(true); assert(strcmp(c.Buttons.continueTracking.Enable,'off'));
c.View.setBusy(false); assert(strcmp(c.Buttons.continueTracking.Enable,'on'));

c.Reference.Value=1;
expect(@() c.track(),'Tracking:ReferenceSeeds');
% Continue must allow entering Track to change reference and range settings.
callback(c.Buttons.continueTracking,[]); assert(c.View.Stage==3);
c.Reference.Value=2.5;
expect(@() c.track(),'Tracking:ReferenceRange');
c.Reference.Value=2; c.First.Value=3;
expect(@() c.track(),'Tracking:ReferenceRange');
c.First.Value=1;
c.Rows(end+1,:)=[3 3 1 1 1 .7 0];
expect(@() c.track(),'Tracking:IncompleteReference');
c.Origins('3:3')='zephir'; c.checkTrackingSeeds(true);
c.Origins('3:3')='confirmed';
expect(@() c.track(),'Tracking:IncompleteReference');
c.Last.Value=2; c.checkTrackingSeeds(true);
assert(isequal(c.View.Review.Snapshots,{struct('sentinel',true)}));
fprintf('TRACKING_TRANSITION_GUARDS=PASS\n');
end

function restore(c,saved)
c.Busy=false; c.Rows=saved.rows; c.Candidates=saved.candidates; c.Origins=saved.origins;
c.First.Value=saved.first; c.Last.Value=saved.last; c.Reference.Value=saved.reference;
c.View.Review.Snapshots=saved.snapshots; c.View.Review.SnapshotBytes=saved.snapshot_bytes;
c.View.setStage(saved.stage); c.View.setBusy(false); c.render();
end

function expect(callback,identifier)
try, callback(); catch ME, assert(strcmp(ME.identifier,identifier),ME.message); return; end
error('test:MissingError','Expected %s',identifier);
end
