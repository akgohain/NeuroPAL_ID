function test_reference_view(w)
%TEST_REFERENCE_VIEW Exercise selection, annotation editing and shared rendering.
assert(~isempty(w.Candidates) && isempty(w.Rows));
candidates = w.Candidates; next_id = w.NextID;
cleanup = onCleanup(@() restore(w,candidates,next_id));
v = w.View; v.DisplayMode.Value='Slice'; v.LabelMode.Value='All'; w.render();
assert(numel(v.NeuronList.Items)==size(candidates,1));
assert(numel(findobj(v.Projection,'Tag','reference_label'))==size(candidates,1));
assert(isequal(w.Slice.Limits,[1 w.Source.nz]));
if ~w.Source.spacing_measured
    assert(isequal(str2double(w.Axes.YTickLabel(:)),w.Axes.YTick(:)));
end
image = getappdata(w.Axes,'main_slice_image');
projection = getappdata(v.Projection,'main_slice_image');
cached = w.Cache;
projection_markers = findobj(v.Projection,'-regexp','Tag','^reference_neurons_');
for z=[1 w.Source.nz 13]
    w.Slice.Value=z; w.render();
    visible = sum(abs(candidates(:,5)-z)<1.5);
    assert(numel(findobj(w.Axes,'Tag','reference_label'))==visible);
    assert(isequal(getappdata(w.Axes,'main_slice_image'),image));
    assert(isequal(getappdata(v.Projection,'main_slice_image'),projection));
    assert(isequal(w.Cache,cached));
    assert(isequal(findobj(v.Projection,'-regexp','Tag','^reference_neurons_'),projection_markers));
end
if w.Source.nc>1
    w.Channel.Value=mod(candidates(1,7)+1,w.Source.nc); w.render();
    assert(numel(findobj(v.Projection,'Tag','reference_label'))==size(candidates,1));
    w.Channel.Value=candidates(1,7); w.render();
end
v.NeuronList.Value=2; v.NeuronList.ValueChangedFcn([],[]);
assert(w.Slice.Value==round(candidates(2,5)) && ~w.Busy);
assert(strcmp(v.Position{1}.Enable,'on'));
assert(isequal(v.Selection,[1 candidates(2,1:2)]));
points = findobj(w.Axes,'-regexp','Tag','^reference_neurons_');
assert(any(all(points.CData==Neurons.Neuron.marker_palette().selected,2)));
v.Position{1}.Value=candidates(2,3)+.125; v.Position{1}.ValueChangedFcn([],[]);
assert(w.Candidates(2,3)==candidates(2,3)+.125);
w.Buttons.remove.ButtonPushedFcn([],[]);
assert(size(w.Candidates,1)==size(candidates,1)-1 && ~w.Busy);
assert(~any(w.Candidates(:,1)==candidates(2,1)));
w.Buttons.accept.ButtonPushedFcn([],[]);
assert(isempty(w.Candidates) && size(w.Rows,1)==size(candidates,1)-1);
assert(strcmp(v.Position{1}.Enable,'on'));
assert(all(v.ListRows(:,8)==0));
rows=w.Rows;
folder=tempname; mkdir(folder); saved=w.save(folder);
loaded=Tracking.ReferenceWorkflow.bridge(struct('action','import','source',w.Source, ...
    'file',fullfile(saved.directory,'annotations.h5')));
w.setRows(loaded.observations); assert(isequal(w.Rows,rows));
w.Cursor=[10 10 0;10 10 0]; w.add();
assert(w.Rows(end,1)==next_id && w.Rows(end,3)==10 && w.Rows(end,4)==10);
v.select(w.Rows(end,:),false); w.Buttons.remove.ButtonPushedFcn([],[]);
assert(isequal(w.Rows,rows));
v.Labels.Value=false; v.Labels.ValueChangedFcn([],[]);
assert(isempty(findobj(v.Projection,'Tag','reference_label')));
assert(~isempty(findobj(v.Projection,'-regexp','Tag','^reference_neurons_')));
fprintf('REFERENCE_VIEW_SELECTION_EDIT_SAVE_RELOAD=PASS\n');
end
function restore(w,candidates,next_id)
w.Rows=zeros(0,7); w.Candidates=candidates; w.NextID=next_id;
w.View.Labels.Value=true; w.View.LabelMode.Value='Selected'; w.Frame.Value=candidates(1,2); w.Channel.Value=candidates(1,7);
w.Slice.Value=round(candidates(1,5)); w.View.Selection=[]; w.render();
end
