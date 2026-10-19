function test_processing_recovery(app)
% Exercise failed saves, lazy previews, and switching to an unannotated image.
assert(contains(app.image_file,'processing-audit'), 'Use a disposable processing fixture.');
source_path=app.image_file;
snapshot=Program.ProcessingSession.get(app);
original=load(source_path,'data');
original_ids=load(app.id_file,'neurons');
original_positions=reshape([original_ids.neurons.neurons.position],3,[])';

% Reject a changed ID destination before publishing either half of the pair.
broken=snapshot;
broken.id_file=fullfile(tempname,'missing','ids.mat');
setappdata(app.CELL_ID,'processing_session',broken);
app.image_data(1)=app.image_data(1)+1;
setappdata(app.CELL_ID,'proc_runtime_dirty',true);
image_fingerprint=Annotations.Store.fingerprint(source_path);
id_fingerprint=Annotations.Store.fingerprint(snapshot.id_file);
failed=false;
try
    Program.Helpers.write_processing_colormap_to_file(app);
catch ME
    assert(strcmp(ME.identifier,'Annotations:StaleSave'),ME.message);
    failed=true;
end
assert(failed);
assert(isequaln(Annotations.Store.fingerprint(source_path),image_fingerprint));
assert(isequaln(Annotations.Store.fingerprint(snapshot.id_file),id_fingerprint));
assert(~isfile([broken.id_file '.processing.pending.json']));
recovered=load(source_path,'data');
assert(isequal(recovered.data,original.data));
recovered_ids=load(snapshot.id_file,'neurons');
assert(isequal(reshape([recovered_ids.neurons.neurons.position],3,[])',original_positions));
assert(Program.ProcessingSession.dirty(app));
app.image_data=original.data;
setappdata(app.CELL_ID,'processing_session',snapshot);
Program.Routines.Processing.reset();

% Stream a mirror without materializing the volume or replacing the source.
app.image_data=[];
app.proc_image=matfile(source_path);
Program.ProcessingSession.capture(app);
assert(Program.Helpers.apply_processing_preview_action(app,'mirrorz'));
assert(isempty(app.image_data));
derivative=app.image_file;
assert(~strcmp(derivative,source_path));
preview=load(derivative,'data');
assert(isequal(preview.data,flip(original.data,3)));
points=reshape([app.image_neurons.neurons.position],3,[])';
expected=original_positions;
expected(:,3)=size(original.data,3)+1-expected(:,3);
assert(max(abs(points-expected),[],'all')<1e-9);
assert(Program.Routines.Processing.save());
[folder,name]=fileparts(derivative);
paired=load(fullfile(folder,[name '_ID.mat']),'neurons');
assert(isequal(reshape([paired.neurons.neurons.position],3,[])',points));
unchanged=load(source_path,'data');
assert(isequal(unchanged.data,original.data));

% A different image without an ID sidecar must not inherit these neurons.
other_path=fullfile(folder,'unannotated_switch.mat');
copyfile(source_path,other_path);
Program.Routines.Processing.load_file('image',other_path);
assert(isempty(app.image_neurons.neurons));
assert(app.mp_params.k==0);
assert(isequal(app.image_neurons.scale,app.image_um_scale));
Program.Routines.Processing.load_file('image',source_path);
assert(numel(app.image_neurons.neurons)==size(original_positions,1));
assert(isequal(reshape([app.image_neurons.neurons.position],3,[])',original_positions));
delete(other_path);
fprintf('PROCESSING_RECOVERY=PASS\n');
end
