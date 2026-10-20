function test_manual_id_source_transition(app)
% A fresh image cannot retain another source's visible ID or assignment gesture.
original=app.image_file;
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()restore(app,original,folder));
first=fullfile(folder,'first.mat'); second=fullfile(folder,'second.mat');
make_volume(app,first,'AVAL'); make_volume(app,second,'RIMR');
Program.Routines.open(first);
app.TabGroup.SelectedTab=app.NeuroPALIDTab;
app.selectManualID(1);
ui=Program.GUI.ManualIDController.ui(app);
assert(strcmp(ui.input.Value,'AVAL') && strcmp(app.UserIDButton.Text,'Update ID'));
gesture=Program.GUI.ManualIDController.captureGesture(app,'mouse');

% Processing can clear the selected index before the next source is opened.
app.selected_neuron=[];
Program.Routines.open(second);
Program.GUIHandling.update_main_id_workflow_state(app);
assert(isempty(app.selected_neuron));
assert(isempty(ui.input.Value) && isempty(app.IDEditField.Value));
assert(strcmp(ui.input.Enable,'off') && strcmp(app.IDEditField.Enable,'off'));
assert(strcmp(app.UserIDButton.Enable,'off') && strcmp(app.UserIDButton.Text,'Assign'));
assert(strcmp(ui.panel.Visible,'off'));
state=Program.GUI.ManualIDController.state(app);
assert(isempty(state.key) && isempty(fieldnames(state.context)));
assert(isempty(state.text) && isempty(state.baseline) && ~state.dirty);
before=Program.GUI.ManualIDService.ensure(app);
file_before=Annotations.Store.fingerprint(app.id_file);

% Queued native text and an old button gesture cannot target this source.
ui.input.ValueChangingFcn(ui.input,struct('Value','AVAR?'));
result=Program.GUI.ManualIDController.assign(app,[],[],'assign',gesture);
assert(~result.changed && isempty(ui.input.Value));
assert(isequaln(before,app.image_neurons.annotation_store));
assert(isequaln(file_before,Annotations.Store.fingerprint(app.id_file)));

% Workflow refreshes do not treat an invalid list index as an editable owner.
for index={0,-1,NaN,1.5,2,[1 2]}
    app.selected_neuron=index{1};
    Program.GUIHandling.update_main_id_workflow_state(app);
    assert(strcmp(ui.input.Enable,'off') && strcmp(app.UserIDButton.Enable,'off'));
end
app.selected_neuron=[];

% Selecting a new owner re-enables only that owner's current annotation.
app.selectManualID(1);
Program.GUIHandling.update_main_id_workflow_state(app);
assert(strcmp(ui.input.Value,'RIMR') && strcmp(ui.input.Enable,'on'));
assert(strcmp(app.UserIDButton.Enable,'on') && strcmp(app.UserIDButton.Text,'Update ID'));
result=Program.GUI.ManualIDController.assign(app,1,[],'assign',gesture);
assert(~result.changed && strcmp(ui.input.Value,'RIMR'));
assert(isequaln(before,app.image_neurons.annotation_store));
assert(isequaln(file_before,Annotations.Store.fingerprint(app.id_file)));

% Read-only annotations remain inspectable without re-enabling assignment.
app.image_neurons.annotation_read_only_reason='Fixture is read-only.';
Program.GUI.ManualIDController.select(app,1);
Program.GUIHandling.update_main_id_workflow_state(app);
assert(strcmp(ui.input.Value,'RIMR') && strcmp(ui.input.Enable,'off'));
assert(strcmp(app.UserIDButton.Enable,'off'));
Program.GUI.ManualIDController.release(app);
assert(strcmp(ui.input.Enable,'off') && strcmp(app.UserIDButton.Enable,'off'));
app.image_neurons.annotation_read_only_reason='';
fprintf('MANUAL_ID_SOURCE_TRANSITION_BLANK_DISABLED_OWNED=PASS\n');
end

function make_volume(app,file,id)
data=zeros(21,23,5,4,'uint16'); data(8,9,3,:)=1000;
info=app.image_info; info.scale=[.4 .5 1.2];
prefs=app.image_prefs; prefs.RGBW=[1 2 3 4];
prefs.DIC=NaN; prefs.GFP=NaN; prefs.is_Z_flip=false;
worm=struct('body','Head','age','Adult','sex','XX','strain','','notes','');
version=Program.ProgramInfo.version;
neurons=Neurons.Image([],'Head','scale',info.scale);
neuron=Neurons.Neuron(); neuron.position=[8 9 3];
neuron.annotation=id; neuron.annotation_confidence=1; neuron.color_readout=[1 1 1 1];
neurons.neurons=neuron; mp_params=app.mp_params;
save(file,'data','info','prefs','worm','version','-v7.3');
[path,name]=fileparts(file);
save(fullfile(path,[name '_ID.mat']),'neurons','version','mp_params');
end

function restore(app,file,folder)
Program.Routines.open(file);
if isfolder(folder), rmdir(folder,'s'); end
end
