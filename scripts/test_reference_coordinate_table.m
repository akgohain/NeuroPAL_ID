function test_reference_coordinate_table(c)
%TEST_REFERENCE_COORDINATE_TABLE Keep delayed table actions on their ID/frame.
assert(~c.Busy && c.Source.nt>=3 && all([c.Source.nx c.Source.ny c.Source.nz]>=3));
v=c.View;
saved=struct('session',c.Analysis.session(),'rows',c.Rows,'candidates',c.Candidates, ...
    'next_id',c.NextID,'origins',c.Origins,'excluded',c.Excluded, ...
    'frame',c.Frame.Value,'channel',c.Channel.Value,'slice',c.Slice.Value, ...
    'selection',v.Selection,'preferred',v.PreferredID,'stage',v.Stage, ...
    'snapshots',{v.Review.Snapshots},'snapshot_bytes',v.Review.SnapshotBytes, ...
    'had_table',~isempty(v.TableWindow) && isvalid(v.TableWindow));
if saved.had_table, saved.table_visible=v.TableWindow.Visible; end
cleanup=onCleanup(@() restore(c,saved));
v.Playback.stop(); v.FramePreview.cancel(); v.Preview.cancel();
c.Rows=[11 2 2 2 2 .9 0;12 3 3 3 2 .8 min(1,c.Source.nc-1)];
c.Candidates=zeros(0,7); c.Excluded=zeros(0,2);
c.Origins=containers.Map('KeyType','char','ValueType','char');
c.Frame.Value=2; c.Channel.Value=0; c.render(); v.openTable();
table=v.CoordinateTable;
assert(isvalid(table) && isequal(table.Data,c.Rows));
old_edit=table.CellEditCallback; old_select=table.CellSelectionCallback;

% Simulate a callback queued before the displayed observations were reordered.
c.Rows=c.Rows([2 1],:); c.render();
assert(isequal(table.Data,c.Rows));
old_select(table,struct('Indices',[1 3]));
assert(isequal(v.Selection,[false 11 2]));
old_edit(table,struct('Indices',[1 3],'NewData',2.25));
assert(c.Rows(c.Rows(:,1)==11,3)==2.25 && c.Rows(c.Rows(:,1)==12,3)==3);
assert(strcmp(c.Origins('11:2'),'reviewed') && isequal(table.Data,c.Rows));

% An observation changed since that display must not receive an old edit.
stale_edit=table.CellEditCallback; before=c.Rows;
c.Rows(c.Rows(:,1)==11,3)=2.5; c.render();
snapshots=numel(v.Review.Snapshots);
stale_edit(table,struct('Indices',[2 3],'NewData',2.75));
assert(c.Rows(c.Rows(:,1)==11,3)==2.5 && isequal(table.Data,c.Rows));
assert(numel(v.Review.Snapshots)==snapshots);
assert(isequal(c.Rows(c.Rows(:,1)==12,:),before(before(:,1)==12,:)));

% Deletion must reject both an old edit and an old selection without rebinding.
deleted_edit=table.CellEditCallback; deleted_select=table.CellSelectionCallback;
c.Rows(c.Rows(:,1)==11,:)=[]; c.render();
expected=c.Rows; selection=v.Selection;
deleted_edit(table,struct('Indices',[2 4],'NewData',2.75));
deleted_select(table,struct('Indices',[2 4]));
assert(isequal(c.Rows,expected) && isequal(table.Data,expected));
assert(isequal(v.Selection,selection) && numel(v.Review.Snapshots)==snapshots);
current_edit=table.CellEditCallback;
current_edit(table,struct('Indices',[1 3],'PreviousData',2,'NewData',3.25));
assert(isequal(c.Rows,expected) && isequal(table.Data,expected));

% A worker disables the visible table and queued edits remain harmless.
busy_edit=table.CellEditCallback; c.Busy=true; v.setBusy(true);
assert(strcmp(table.Enable,'off'));
busy_edit(table,struct('Indices',[1 3],'NewData',3.25));
assert(isequal(c.Rows,expected) && isequal(table.Data,expected));
c.Busy=false; v.setBusy(false); assert(strcmp(table.Enable,'on'));

% Reopening refreshes even when a caller has changed rows before rendering.
c.Rows(end+1,:)=[13 2 2 3 2 1 0]; v.openTable();
assert(isequal(v.CoordinateTable,table) && isequal(table.Data,c.Rows));
delete(v.TableWindow); v.openTable();
assert(isvalid(v.CoordinateTable) && isequal(v.CoordinateTable.Data,c.Rows));
fprintf('REFERENCE_COORDINATE_TABLE_STABLE_ID_STALE_BUSY_REFRESH=PASS\n');
end

function restore(c,saved)
v=c.View; c.Busy=false;
c.Rows=saved.rows; c.Candidates=saved.candidates; c.NextID=saved.next_id;
c.Origins=saved.origins; c.Excluded=saved.excluded;
c.Analysis.restoreSession(saved.session);
c.Frame.Value=saved.frame; c.Channel.Value=saved.channel; c.Slice.Value=saved.slice;
v.Selection=saved.selection; v.PreferredID=saved.preferred;
v.Review.Snapshots=saved.snapshots; v.Review.SnapshotBytes=saved.snapshot_bytes;
v.setStage(saved.stage); v.setBusy(false); c.render();
if ~isempty(v.TableWindow) && isvalid(v.TableWindow)
    if saved.had_table, v.TableWindow.Visible=saved.table_visible;
    else, delete(v.TableWindow); v.TableWindow=[]; v.CoordinateTable=[]; end
end
end
