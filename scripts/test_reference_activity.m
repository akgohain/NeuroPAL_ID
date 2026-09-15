function test_reference_activity(w)
%TEST_REFERENCE_ACTIVITY Check linked traces and measurement invalidation.
assert(~isempty(w.Rows) && w.activityCurrent());
view=w.View; analysis=w.Analysis;
frame=w.Frame.Value; selection=view.PreferredID; excluded=w.Excluded; mode=analysis.Mode.Value;
cleanup=onCleanup(@() restore(w,frame,selection,excluded,mode));
view.LabelMode.Value='Selected'; w.render();
assert(numel(findobj(w.Axes,'Tag','reference_label'))<=1);
view.NeuronList.Value=2; view.chooseList();
identity=view.PreferredID;
assert(contains(analysis.Axes.Title.String,sprintf('Neuron %d',identity)));
w.Frame.Value=min(w.Source.nt,frame+1); w.render();
assert(view.PreferredID==identity);
analysis.Mode.Value='Population ΔF/F'; analysis.render();
heatmap=findobj(analysis.Axes,'Type','image');
assert(isequal(size(heatmap.CData),[numel(analysis.IDs) numel(analysis.Frames)]));
analysis.Mode.Value='ΔF/F'; analysis.render();
view.Exclude.Value=true; view.exclude();
assert(~w.activityCurrent()); assert(contains(analysis.Axes.Title.String,'out of date'));
view.Exclude.Value=false; view.exclude();
assert(w.activityCurrent());
w.Excluded=[identity w.Frame.Value]; observations=w.observations();
for i=1:numel(observations), observations(i).excluded=false; end
w.mergeTracks(observations); assert(ismember([identity w.Frame.Value],w.Excluded,'rows'));
w.Excluded=excluded;
old=analysis.Controls.radius.Value; analysis.Controls.radius.Value='4 4 1';
assert(~w.activityCurrent()); analysis.Controls.radius.Value=old;
assert(w.activityCurrent());
session=analysis.session(); old_window=w.WindowSize.Value; w.WindowSize.Value=2;
analysis.restoreSession(session); assert(w.WindowSize.Value==old_window);
session.activity_current=false; analysis.restoreSession(session); assert(~w.activityCurrent());
session.activity_current=true; analysis.restoreSession(session); assert(w.activityCurrent());
assert(session.next_id==w.NextID);
file=fullfile(w.ActivityDirectory,'activity.h5');
index=find(analysis.IDs==identity,1); nt=numel(analysis.Frames);
modes={'Raw fluorescence','Background','Reference fluorescence'};
datasets={'/raw/channel_0','/background/channel_0','/raw/channel_1'};
original_signal=analysis.Controls.signal.Value;
analysis.Controls.signal.Value=2;
for i=1:numel(modes)
    analysis.Mode.Value=modes{i}; analysis.render();
    line=findobj(analysis.Axes,'Tag','activity_trace');
    expected=h5read(file,datasets{i},[index 1],[1 nt]);
    assert(isequaln(line.YData(:),expected(:)));
end
analysis.Controls.signal.Value=original_signal;
rows=w.Rows; origins=containers.Map(w.Origins.keys,w.Origins.values); next_id=w.NextID;
view.select(w.Rows(find(w.Rows(:,1)==identity & w.Rows(:,2)==w.Frame.Value,1),:),false);
w.Excluded=[identity w.Frame.Value]; view.removeSelection();
assert(~any(w.Rows(:,1)==identity) && ~any(w.Excluded(:,1)==identity));
assert(~any(startsWith(w.Origins.keys,sprintf('%d:',identity))));
assert(w.NextID==next_id && ~w.activityCurrent());
w.Rows=rows; w.Origins=origins; w.Excluded=excluded; view.PreferredID=identity;
observations=w.observations(); w.NextID=next_id+1; w.setRows(observations);
assert(w.NextID==next_id+1); w.NextID=next_id;
fprintf('REFERENCE_ACTIVITY_LINKS_INVALIDATION_SESSION=PASS\n');
end
function restore(w,frame,selection,excluded,mode)
w.Frame.Value=frame; w.View.PreferredID=selection; w.Excluded=excluded;
w.Analysis.Mode.Value=mode; w.render();
end
