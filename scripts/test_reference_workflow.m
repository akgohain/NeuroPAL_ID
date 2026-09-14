function test_reference_workflow(app, source, output)
%TEST_REFERENCE_WORKFLOW Exercise reference callbacks on an actual recording.
Program.Routines.open(source);
w = getappdata(app.CELL_ID,'calcium_reference_workflow');
assert(w.Source.nx==512 && w.Source.ny==175 && w.Source.nz==25);
assert(isequal(size(w.Cache),[175 512 25 3]));
w.OutputRoot = output;
w.Frame.Value = 210; w.render();
assert(w.CacheFrame==210);
cached = w.Cache; started = tic;
for z=[1 8 25 13], w.Slice.Value=z; w.render(); end
assert(isequal(w.Cache,cached));
fprintf('REFERENCE_SLICE_SECONDS=%.3f\n',toc(started));
w.Calibration.Value=true;
w.Channel.Value=2;
w.Buttons.detect.ButtonPushedFcn([],[]);
assert(isempty(w.Candidates) && isempty(w.Rows) && ~w.Busy);
fprintf('REFERENCE_BLANK_CHANNEL=PASS\n');
w.Channel.Value=0;
w.Buttons.detect.ButtonPushedFcn([],[]);
assert(size(w.Candidates,1)>0 && isempty(w.Rows) && ~w.Busy);
count=size(w.Candidates,1);
fprintf('REFERENCE_DETECTION_COUNT=%d\n',count);
w.Buttons.accept.ButtonPushedFcn([],[]);
assert(size(w.Rows,1)==count && isempty(w.Candidates));
old=w.Rows(1,3); value=old+.125;
w.Table.CellEditCallback([],struct('Indices',[1 3],'NewData',value));
assert(w.Rows(1,3)==value);
saved=w.save(output);
loaded=Tracking.ReferenceWorkflow.bridge(struct('action','import','source',w.Source, ...
    'file',fullfile(saved.directory,'annotations.h5')));
original=w.Rows; w.setRows(loaded.observations);
assert(isequal(w.Rows,original));
fprintf('REFERENCE_EDIT_SAVE_RELOAD=PASS\n');
w.First.Value=210;w.Last.Value=212;
w.Buttons.track.ButtonPushedFcn([],[]);
assert(size(w.Rows,1)==3*count);
assert(numel(unique(w.Rows(:,1)))==count);
assert(isequal(unique(w.Rows(:,2)),[210;211;212]));
assert(all(w.Rows(:,7)==0));
observations=w.observations();
tracked=observations([observations.t]>210);
assert(all(strcmp({tracked.provenance},'zephir')));
assert(all([tracked.confidence]==0));
w.Busy=true; w.closeSession([],[]);
assert(w.Cancelled && isvalid(app)); w.finish(); w.Cancelled=false;
fprintf('REFERENCE_ZEPHIR_WINDOW=PASS\n');
w.save(output);
w.Frame.Value=210;w.Slice.Value=13;w.render();
fprintf('REFERENCE_WORKFLOW=PASS\n');
end
