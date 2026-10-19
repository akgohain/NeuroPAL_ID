function test_annotation_service(app)
%TEST_ANNOTATION_SERVICE Keep durable ID edits separate from live model state.
if nargin<1, app=Program.app; end
assert(~isempty(app) && isvalid(app),'Start the app before running the service test.');
folder=tempname; mkdir(folder);
saved=struct('image_neurons',app.image_neurons,'image_file',app.image_file, ...
    'id_file',app.id_file,'worm',app.worm,'selected_neuron',app.selected_neuron, ...
    'mp_params',app.mp_params, ...
    'snapshot',getappdata(app.CELL_ID,'manual_id_file_snapshot'), ...
    'controller',getappdata(app.CELL_ID,'manual_id_controller'));
cleanup=onCleanup(@() restore(app,saved,folder));
image=Neurons.Image([]); image.scale=[0.4 0.4 1.5];
for i=1:3
    neuron=Neurons.Neuron; neuron.position=[10*i 20+i 3];
    neuron.deterministic_id='AVA'; neuron.probabilistic_ids={'AVA','AVB'};
    neuron.probabilistic_probs=[0.7 0.3]; neuron.rank=i;
    image.neurons(i)=neuron;
end
app.image_neurons=image; app.image_file=fullfile(folder,'volume.mat');
app.id_file=fullfile(folder,'volume_ID.mat'); app.worm.sex='XX'; app.selected_neuron=1;
store=Program.GUI.ManualIDService.ensure(app); owners={image.neurons.annotation_id};
evidence=store.evidence; model=image.neurons(1).probabilistic_probs;
context=Program.GUI.ManualIDService.context(app,1);
result=Program.GUI.ManualIDService.assign(app,1,Annotations.Catalog.parse('AVAL?','XX'), ...
    'assign',struct('context',context,'operation_id','service-tentative'));
assert(result.changed && isequal(image.neurons(1).probabilistic_probs,model));
assert(strcmp(image.neurons(1).deterministic_id,'AVA') && isempty(image.neurons(1).annotation));
record=Annotations.Store.record(image.annotation_store,owners{1});
assert(strcmp(record.certainty,'tentative') && strcmp(record.candidates{1},'AVAL'));
[loaded,~,issues]=Annotations.Store.loadValidated(app.id_file);
assert(isempty(issues) && isequaln(loaded.annotation_store,image.annotation_store));
assert(isequaln(loaded.annotation_store.evidence,evidence));
assert(strcmp(loaded.neurons.neurons(1).annotation_id,owners{1}));

% Reordering detection rows changes display order, never annotation ownership.
image.neurons=image.neurons([2 1 3]); app.selected_neuron=2;
record=Program.GUI.ManualIDService.record(app,2);
assert(strcmp(record.owner_id,owners{1}) && strcmp(record.candidates{1},'AVAL'));
stale=Program.GUI.ManualIDService.context(app,2);
image.neurons(2).position(1)=image.neurons(2).position(1)+1;
expect(@() Program.GUI.ManualIDService.assign(app,2,Annotations.Catalog.parse('ALA','XX'), ...
    'assign',struct('context',stale)),'Annotations:StaleDraft');
record=Annotations.Store.record(image.annotation_store,owners{1}); assert(strcmp(record.certainty,'tentative'));

% An external writer invalidates the captured publication; the draft survives.
app.selected_neuron=1; context=Program.GUI.ManualIDService.context(app,1);
live=image.annotation_store;
controller=saved.controller;
if isempty(controller), controller=struct(); end
controller.text='AVAR?'; controller.dirty=true;
setappdata(app.CELL_ID,'manual_id_controller',controller);
draft_before=getappdata(app.CELL_ID,'manual_id_controller');
external_note='newer external save';
save(app.id_file,'external_note','-append');
expect(@() Program.GUI.ManualIDService.assign(app,1,Annotations.Catalog.parse('AVAR?','XX'), ...
    'assign',struct('context',context,'operation_id','failed-service-save')),'Annotations:StaleSave');
assert(isequaln(image.annotation_store,live));
assert(isequaln(getappdata(app.CELL_ID,'manual_id_controller'),draft_before));
assert(strcmp(image.neurons(1).annotation_id,owners{2}) && isempty(image.neurons(1).annotation));
assert(isequal(image.neurons(1).probabilistic_probs,[0.7 0.3]));
assert(app.selected_neuron==1);

fprintf('ANNOTATION_SERVICE_EVIDENCE_STALE_CONTEXT_SAVE_FAILURE_OWNER_REORDER=PASS\n');
end

function restore(app,saved,folder)
if isvalid(app)
    app.image_neurons=saved.image_neurons; app.image_file=saved.image_file;
    app.id_file=saved.id_file; app.worm=saved.worm;
    app.selected_neuron=saved.selected_neuron; app.mp_params=saved.mp_params;
    setappdata(app.CELL_ID,'manual_id_file_snapshot',saved.snapshot);
    setappdata(app.CELL_ID,'manual_id_controller',saved.controller);
end
if exist(folder,'dir')==7, rmdir(folder,'s'); end
end

function expect(callback,identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier,identifier),'Expected %s, got %s: %s',identifier,ME.identifier,ME.message);
    return;
end
error('Annotations:TestExpectedError','Expected %s.',identifier);
end
