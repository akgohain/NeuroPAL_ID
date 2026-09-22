function test_multichannel_workflow(c)
%TEST_MULTICHANNEL_WORKFLOW Check selection, acceptance and saved-session round trips.
assert(~c.Busy && ~isempty(c.Candidates) && strcmp(c.Provenance.input_mode,'multi_channel'));
saved=struct('session',c.Analysis.session(),'rows',c.Rows,'candidates',c.Candidates, ...
    'candidate_frame',c.CandidateFrame,'next_id',c.NextID,'history',{c.History},'provenance',c.Provenance, ...
    'frame',c.Frame.Value,'channel',c.Channel.Value,'slice',c.Slice.Value,'selection',c.View.Selection, ...
    'preferred',c.View.PreferredID,'origins',c.Origins,'excluded',c.Excluded, ...
    'snapshots',{c.View.Review.Snapshots},'snapshot_bytes',c.View.Review.SnapshotBytes);
cleanup=onCleanup(@() restore(c,saved));
settings=Tracking.DetectionChannels.get(c); controls=getappdata(c.Grid,'detection_channels');
for mode={'Single channel','Multi-channel'}
    c.DetectionMode.Value=mode{1}; c.View.detectionModeChanged();
    assert(strcmp(controls.panel.Visible,'on')==strcmp(mode{1},'Multi-channel'));
end
c.View.setBusy(true); assert(strcmp(controls.table.Enable,'off') && strcmp(controls.radius.Enable,'off'));
c.View.setBusy(false); assert(strcmp(controls.table.Enable,'on'));
Tracking.DetectionChannels.restore(c,struct('channels',settings.channels(1),'merge_radius_um',2));
c.Calibration.Value=true;
expect(@() c.detect(),'Tracking:Channels');
Tracking.DetectionChannels.restore(c,settings);
roundtrip=jsondecode(jsonencode(c.Analysis.session()));
Tracking.DetectionChannels.restore(c,struct('channels',[],'merge_radius_um',0));
c.Analysis.restoreSession(roundtrip); assert(isequal(Tracking.DetectionChannels.get(c),settings));
legacy=roundtrip; legacy.detection_mode='RGBW'; legacy.rgbw_channels='0 1 2 3';
c.Analysis.restoreSession(legacy); assert(strcmp(c.RGBW.Visible,'on'));
if c.Source.nc<4, expect(@() c.detect(),'Tracking:RGBWChannels'); end
c.Analysis.restoreSession(roundtrip);
c.DetectionMode.Items={'Single channel','Multi-channel'}; c.DetectionMode.Value='Multi-channel';

% A blank source channel must not clear pending results or the tracking reference.
c.frameData(); blank=[];
for channel=0:c.Source.nc-1
    if ~any(c.Cache(:,:,:,channel+1)>0,'all'), blank=channel; break; end
end
if ~isempty(blank)
    before=struct('rows',c.Rows,'candidates',c.Candidates,'reference',c.Reference.Value,'history',{c.History}, ...
        'snapshots',{c.View.Review.Snapshots},'next_id',c.NextID,'provenance',c.Provenance);
    c.DetectionMode.Value='Single channel'; c.DetectionChannel.Value=blank; c.detect();
    assert(isequaln(c.Rows,before.rows) && isequaln(c.Candidates,before.candidates));
    assert(c.Reference.Value==before.reference && c.NextID==before.next_id);
    assert(isequaln(c.History,before.history) && isequaln(c.Provenance,before.provenance));
    assert(isequaln(c.View.Review.Snapshots,before.snapshots));
end
c.Analysis.restoreSession(roundtrip); c.Frame.Value=c.CandidateFrame;
selected=c.Provenance.source_metadata.selected_channels;
c.Channel.Value=selected(end);
if any(ismember(c.Candidates(:,[2 7]),c.Rows(:,[2 7]),'rows'))
    expect(@() c.accept(),'Tracking:ExistingSeeds');
end
c.Rows=zeros(0,7); c.Excluded=zeros(0,2); c.Origins=containers.Map('KeyType','char','ValueType','char');
expected=c.Candidates; c.accept(); assert(isempty(c.Candidates) && isequal(c.Rows,expected));
folder=tempname; mkdir(folder); folder_cleanup=onCleanup(@() rmdir(folder,'s'));
export=c.save(folder); c.Rows=zeros(0,7); c.load(fullfile(export.directory,'annotations.h5'));
assert(isequal(c.Rows,expected) && strcmp(c.DetectionMode.Value,'Multi-channel'));
assert(isequal(Tracking.DetectionChannels.get(c),settings));
assert(isequal(c.Provenance.selected_channels(:),saved.provenance.selected_channels(:)));
assert(isequal(c.Provenance.source_channels,saved.provenance.source_channels));
fprintf('MULTICHANNEL_UI_ACCEPT_EXPORT_RELOAD_EMPTY_PRESERVATION=PASS\n');
end
function restore(c,saved)
    c.Rows=saved.rows; c.Candidates=saved.candidates; c.CandidateFrame=saved.candidate_frame;
    c.NextID=saved.next_id; c.History=saved.history; c.Provenance=saved.provenance;
    c.Origins=saved.origins; c.Excluded=saved.excluded;
    c.Analysis.restoreSession(saved.session); c.Frame.Value=saved.frame; c.Channel.Value=saved.channel; c.Slice.Value=saved.slice;
    c.View.Selection=saved.selection; c.View.PreferredID=saved.preferred;
    c.View.Review.Snapshots=saved.snapshots; c.View.Review.SnapshotBytes=saved.snapshot_bytes;
    c.View.detectionModeChanged(); c.render();
end

function expect(callback,identifier)
try, callback(); catch ME, assert(strcmp(ME.identifier,identifier),ME.message); return; end
error('test:MissingError','Expected %s',identifier);
end
