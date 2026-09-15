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
fprintf('REFERENCE_ACTIVITY_LINKS_INVALIDATION_SESSION=PASS\n');
end
function restore(w,frame,selection,excluded,mode)
w.Frame.Value=frame; w.View.PreferredID=selection; w.Excluded=excluded;
w.Analysis.Mode.Value=mode; w.render();
end
