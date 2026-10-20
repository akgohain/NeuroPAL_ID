function report=test_manual_id_contract_ui(app)
%TEST_MANUAL_ID_CONTRACT_UI Exercise owned drafts and explicit annotation commands.
if nargin<1, app=Program.app; end
assert(~isempty(app.image_neurons) && numel(app.image_neurons.neurons)>=2);
folder=tempname; mkdir(folder);
saved=struct('neurons',app.image_neurons,'id_file',app.id_file, ...
    'selected',app.selected_neuron,'tab',app.TabGroup.SelectedTab, ...
    'auto',app.AutoNameCheckBox.Value,'state',Program.GUI.ManualIDController.state(app), ...
    'after',getappdata(app.CELL_ID,'manual_id_after_commit'), ...
    'snapshot',getappdata(app.CELL_ID,'manual_id_file_snapshot'));
cleanup=onCleanup(@() restore(app,saved,folder));
copy=Program.GUI.ManualIDService.copyImage(app.image_neurons);
copy.annotation_store=struct();
for i=1:numel(copy.neurons)
    copy.neurons(i).annotation=''; copy.neurons(i).annotation_confidence=-1;
    copy.neurons(i).annotation_id=''; copy.neurons(i).annotation_record=struct();
end
app.image_neurons=copy; app.id_file=fullfile(folder,'contract_ID.mat');
app.AutoNameCheckBox.Value=false; app.TabGroup.SelectedTab=app.NeuroPALIDTab;
setappdata(app.CELL_ID,'manual_id_after_commit',@(~,~,~) []);
Program.GUI.ManualIDController.invalidate(app);
app.selected_neuron=1; Program.GUI.ManualIDController.select(app,1);
ui=Program.GUI.ManualIDController.ui(app);
assert(isa(ui.input,'matlab.ui.control.EditField'));
editor=ui.input.Parent;
assert(strcmp(editor.Tag,'ManualIDEditor') && isequal(app.UserIDButton.Parent,editor));
assert(numel(editor.Children)==2 && isequal(editor.Children,[ui.input;app.UserIDButton]));
assert(ui.input.Layout.Column==1 && app.UserIDButton.Layout.Column==2);
assert(contains(Program.GUI.ManualIDController.reviewMessage(struct('issue','','conflicts',{{'IL1L'}})),'IL1L'));
assert(contains(Program.GUI.ManualIDController.reviewMessage(struct('issue','Context conflict.','conflicts',{{}})),'Context conflict'));
evidence=copy.annotation_store.evidence;

% Family typing never picks an individual, even when native text commits on blur.
ui.input.ValueChangingFcn(ui.input,struct('Value','IL1?! '));
ui.input.Value='IL1?! '; ui.input.ValueChangedFcn(ui.input,[]);
state=Program.GUI.ManualIDController.state(app);
assert(state.active==0 && sum(strcmp({state.rows.kind},'individual'))==6);
watch=getappdata(app.CELL_ID,'manual_id_popup_resize_timer');
assert(~isempty(watch) && isvalid(watch.timer) && strcmp(watch.timer.Running,'on'));
record=Program.GUI.ManualIDService.record(app,1);
assert(~exist(app.id_file,'file') && strcmp(record.kind,'unassigned'));
Program.GUI.ManualIDController.accept(app,find(strcmp({state.rows.kind},'keep'),1));
draft=Program.GUI.ManualIDController.capture(app);
assert(draft.valid && strcmp(draft.kind,'unresolved_set') && numel(draft.candidates)==6);
assert(strcmp(draft.certainty,'tentative') && draft.attributes.emphasized);
assert(~exist(app.id_file,'file'));
assert(isempty(getappdata(app.CELL_ID,'manual_id_popup_resize_timer')));

% Drafts follow stable owners rather than list rows or current text focus.
app.selected_neuron=2; Program.GUI.ManualIDController.select(app,2);
state=Program.GUI.ManualIDController.state(app); assert(isempty(state.text));
Program.GUI.ManualIDController.edited(app,'AVA');
state=Program.GUI.ManualIDController.state(app);
group=find(strcmp({state.rows.kind},'group') & strcmp({state.rows.token},'AVA'),1);
Program.GUI.ManualIDController.noteFocus(app,'list');
Program.GUI.ManualIDController.clicked(app,struct('InteractionInformation',struct('Item',group)));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.expanded,'AVA') && strcmp(state.focusRole,'input'));
event=struct('Key','downarrow','Modifier',{{}});
state=Program.GUI.ManualIDController.state(app);
assert(state.active==0 && sum(strcmp({state.rows.kind},'individual'))==2);
assert(Program.GUI.ManualIDController.handleKey(app,event));
Program.GUI.ManualIDController.handleKey(app,event);
event.Key='return'; Program.GUI.ManualIDController.handleKey(app,event);
assert(~exist(app.id_file,'file'));
draft=Program.GUI.ManualIDController.capture(app); assert(draft.valid && strcmp(draft.kind,'individual'));
event.Key='downarrow'; event.Modifier={'control'};
Program.GUI.ManualIDController.handleKey(app,event,ui.input);
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusRole,'actions') && state.focusAction==1 && strcmp(state.focusOwner,state.key));
% Queued native text notifications update the draft without undoing Ctrl+Down.
generation=state.generation; owner=state.key;
ui.input.ValueChangingFcn(ui.input,struct('Value',state.text));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusRole,'actions') && state.focusAction==1 && state.generation==generation);
ui.input.ValueChangingFcn(ui.input,struct('Value','IL1L?'));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.text,'IL1L?') && state.generation==generation+1 && strcmp(state.key,owner));
assert(strcmp(state.focusRole,'actions') && state.focusAction==1 && state.open && strcmp(ui.panel.Visible,'on'));
event.Key='return'; event.Modifier={};
allNames=state.allNames;
assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app); assert(state.allNames==allNames);
assert(~exist(app.id_file,'file'));
% Footer buttons retain native activation and have an explicit local Tab route.
event.Key='tab'; Program.GUI.ManualIDController.handleKey(app,event);
state=Program.GUI.ManualIDController.state(app); assert(state.focusAction==2);
event.Modifier={'shift'}; Program.GUI.ManualIDController.handleKey(app,event);
state=Program.GUI.ManualIDController.state(app); assert(state.focusAction==1);
event.Modifier={}; Program.GUI.ManualIDController.handleKey(app,event);
Program.GUI.ManualIDController.handleKey(app,event);
state=Program.GUI.ManualIDController.state(app); assert(state.focusAction==3);
Program.GUI.ManualIDController.handleKey(app,event);
state=Program.GUI.ManualIDController.state(app); assert(strcmp(state.focusRole,'input'));
event.Key='downarrow'; event.Modifier={'control'};
Program.GUI.ManualIDController.handleKey(app,event);
event.Key='tab'; event.Modifier={'shift'};
Program.GUI.ManualIDController.handleKey(app,event);
state=Program.GUI.ManualIDController.state(app); assert(strcmp(state.focusRole,'input'));
event.Key='downarrow'; event.Modifier={'control'};
Program.GUI.ManualIDController.handleKey(app,event);
event.Key='tab'; event.Modifier={}; Program.GUI.ManualIDController.handleKey(app,event);
Program.GUI.ManualIDController.close(app);
event.Modifier={'shift'}; assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app);
assert(~state.open && strcmp(state.focusRole,'input'));

% Reversing native Tab outside the editor reenters its captured owner boundary.
event.Modifier={};
event.Key='tab'; assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusRole,'assign') && strcmp(state.pendingGesture.owner_key,state.key));
assert(isempty(getappdata(app.CELL_ID,'manual_id_focus_timer')));
assert(~Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusRole,'other') && strcmp(state.focusBoundary,'assign') && state.focusOffset==1);
assert(~Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app); assert(state.focusOffset==2);
event.Modifier={'shift'}; assert(~Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app); assert(state.focusOffset==1);
assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusRole,'assign') && strcmp(state.focusOwner,state.key) && state.focusOffset==0);
event.Modifier={'shift'}; assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app); assert(strcmp(state.focusRole,'input'));
assert(~Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusBoundary,'input') && state.focusOffset==-1);
event.Modifier={}; assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app); assert(strcmp(state.focusRole,'input'));
assert(~exist(app.id_file,'file'));
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
% A superseded focus callback cannot clear or execute the latest request.
superseded=timer; latest=timer;
setappdata(app.CELL_ID,'manual_id_focus_timer',latest);
state=Program.GUI.ManualIDController.state(app);
Program.GUI.ManualIDController.finishFocus(app,ui.input,state.key,state.generation,'input',superseded);
assert(~isvalid(superseded) && isvalid(latest));
assert(isequal(getappdata(app.CELL_ID,'manual_id_focus_timer'),latest));
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
% Cleanup remains safe when a one-shot focus request has already completed.
finished=timer; delete(finished);
setappdata(app.CELL_ID,'manual_id_focus_timer',finished);
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
assert(isempty(getappdata(app.CELL_ID,'manual_id_focus_timer')));
event.Key='escape'; event.Modifier={};
Program.GUI.ManualIDController.handleKey(app,event,ui.input);
Program.GUI.ManualIDController.handleKey(app,event,ui.input);
state=Program.GUI.ManualIDController.state(app); assert(isempty(state.text) && ~state.dirty);
% A key pressed outside tracked editor focus still captures a native command owner.
Program.GUI.ManualIDController.noteFocus(app,'other');
state=Program.GUI.ManualIDController.state(app);
previousKey=state.previousKey; previousRelease=state.previousRelease;
state.previousKey=[]; state.previousRelease=[]; Program.GUI.ManualIDController.put(app,state);
event.Key='space'; Program.GUI.ManualIDController.windowKey(app,app.CELL_ID,event);
keyboard=Program.GUI.ManualIDController.consumeGesture(app,[]);
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(keyboard.origin,'keyboard') && strcmp(keyboard.owner_key,state.key));
assert(keyboard.generation==state.generation && keyboard.index==2 && ~exist(app.id_file,'file'));
Program.GUI.ManualIDController.windowRelease(app,app.CELL_ID,event);
state=Program.GUI.ManualIDController.state(app);
state.previousKey=previousKey; state.previousRelease=previousRelease;
Program.GUI.ManualIDController.put(app,state);
app.selected_neuron=1; Program.GUI.ManualIDController.select(app,1);
draft=Program.GUI.ManualIDController.capture(app);
assert(draft.valid && strcmp(draft.kind,'unresolved_set'));
stale=Program.GUI.ManualIDController.assign(app,1,[],'assign',keyboard);
assert(~stale.changed && ~exist(app.id_file,'file'));
Program.GUI.ManualIDController.beginMouseGesture(app,'normal');
gesture=Program.GUI.ManualIDController.consumeGesture(app,[]);
result=Program.GUI.ManualIDController.assign(app,1,[],'assign',gesture);
assert(result.changed && exist(app.id_file,'file')==2);
disk=load(app.id_file,'annotation_store');
record=Annotations.Store.record(disk.annotation_store,copy.neurons(1).annotation_id);
assert(strcmp(record.kind,'unresolved_set') && numel(record.candidates)==6);
assert(isempty(copy.neurons(1).annotation));

% A native double-click reuses its first press even after auto-advance or a delay.
app.selected_neuron=2; Program.GUI.ManualIDController.select(app,2);
revision=copy.annotation_store.revision;
reset_latch(app);
Program.GUI.ManualIDController.beginMouseGesture(app,'open');
duplicate=Program.GUI.ManualIDController.consumeGesture(app,[]);
assert(strcmp(duplicate.operation_id,gesture.operation_id));
replayed=Program.GUI.ManualIDController.assign(app,2,[],'assign',duplicate);
assert(~replayed.changed && replayed.replayed && copy.annotation_store.revision==revision);
record2=Program.GUI.ManualIDService.record(app,2); assert(strcmp(record2.kind,'unassigned'));
Program.GUI.ManualIDController.beginKeyGesture(app,'return');
held=Program.GUI.ManualIDController.consumeGesture(app,[]);
Program.GUI.ManualIDController.beginKeyGesture(app,'return');
repeat=Program.GUI.ManualIDController.consumeGesture(app,[]);
assert(strcmp(held.operation_id,repeat.operation_id));
Program.GUI.ManualIDController.windowRelease(app,app.CELL_ID,struct('Key','return'));
Program.GUI.ManualIDController.beginKeyGesture(app,'return');
released=Program.GUI.ManualIDController.consumeGesture(app,[]);
assert(~strcmp(held.operation_id,released.operation_id));
Program.GUI.ManualIDController.windowRelease(app,app.CELL_ID,struct('Key','return'));
app.selected_neuron=1;

% A deliberate member choice preserves uncertainty and emphasis.
reset_latch(app); Program.GUI.ManualIDController.select(app,1);
Program.GUI.ManualIDController.edited(app,'IL1L?!');
state=Program.GUI.ManualIDController.state(app);
row=find(strcmp({state.rows.token},'IL1L') & strcmp({state.rows.kind},'individual'),1);
Program.GUI.ManualIDController.accept(app,row);
draft=Program.GUI.ManualIDController.capture(app);
assert(draft.valid && isequal(draft.candidates,{'IL1L'}) && strcmp(draft.certainty,'tentative'));
result=Program.GUI.ManualIDInput.commit(app,[],1); assert(result.changed);
assert(isequaln(evidence,copy.annotation_store.evidence));
assert(~app.is_saving_ID);
reset_latch(app); Program.GUI.ManualIDController.undo(app);
record=Program.GUI.ManualIDService.record(app,1);
assert(strcmp(record.kind,'unresolved_set') && numel(record.candidates)==6);
reset_latch(app); Program.GUI.ManualIDController.edited(app,'il1l',false);
result=Program.GUI.ManualIDInput.commit(app,[],1); assert(result.changed);
assert(strcmp(copy.neurons(1).annotation,'IL1L'));
disk=load(app.id_file,'neurons'); assert(strcmp(disk.neurons.neurons(1).annotation,'IL1L'));
assert(isequaln(evidence,copy.annotation_store.evidence));
reset_latch(app); Program.GUI.ManualIDController.undo(app);

% A stale context is retained for correction and cannot mutate the owner.
Program.GUI.ManualIDController.edited(app,'IL1R');
state=Program.GUI.ManualIDController.state(app); state.context.annotation_revision=-100;
Program.GUI.ManualIDController.put(app,state); reset_latch(app);
before=copy.annotation_store.revision;
result=Program.GUI.ManualIDInput.commit(app,[],1);
assert(~result.changed && copy.annotation_store.revision==before && Program.GUI.ManualIDController.dirty(app));

% Native Value changes are captured without relying on blur or the hidden bridge.
app.selected_neuron=2; Program.GUI.ManualIDController.select(app,2);
app.IDEditField.Value='IL1R'; ui.input.Value='AVAR?';
Program.GUI.ManualIDController.beginMouseGesture(app,'normal');
result=Program.GUI.ManualIDInput.commit(app,[],2,[]); assert(result.changed);
record=Program.GUI.ManualIDService.record(app,2);
assert(isequal(record.candidates,{'AVAR'}) && strcmp(record.certainty,'tentative'));
Program.GUI.ManualIDController.select(app,2);
Program.GUI.ManualIDController.edited(app,'AVAL?');
Program.GUI.ManualIDController.noteFocus(app,'input');
event=struct('Key','tab','Modifier',{{}});
assert(Program.GUI.ManualIDController.handleKey(app,event));
state=Program.GUI.ManualIDController.state(app); assert(strcmp(state.focusRole,'assign'));
% A late final character after Tab keeps Assign focused and its popup closed.
generation=state.generation; owner=state.key; before=copy.annotation_store.revision;
ui.input.ValueChangingFcn(ui.input,struct('Value',state.text));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.focusRole,'assign') && state.generation==generation && ~state.open);
ui.input.ValueChangingFcn(ui.input,struct('Value','AVAL?!'));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.text,'AVAL?!') && state.generation==generation+1 && strcmp(state.key,owner));
assert(strcmp(state.focusRole,'assign') && ~state.open && strcmp(ui.panel.Visible,'off'));
assert(copy.annotation_store.revision==before);
event.Key='return'; assert(Program.GUI.ManualIDController.handleKey(app,event));
record=Program.GUI.ManualIDService.record(app,2);
assert(isequal(record.candidates,{'AVAL'}) && strcmp(record.certainty,'tentative') && record.attributes.emphasized);
revision=copy.annotation_store.revision;
gesture=Program.GUI.ManualIDController.state(app); gesture=gesture.keyGesture;
replayed=Program.GUI.ManualIDController.assign(app,2,[],'assign',gesture);
assert(~replayed.changed && replayed.replayed && copy.annotation_store.revision==revision);
Program.GUI.ManualIDController.windowRelease(app,app.CELL_ID,struct('Key','return'));
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
Program.GUI.ManualIDController.select(app,2);
Program.GUI.ManualIDController.beginMouseGesture(app,'normal');
ui.input.Value='AVAR';
before=copy.annotation_store.revision;
result=Program.GUI.ManualIDInput.commit(app,[],2,[]);
assert(~result.changed && copy.annotation_store.revision==before);
state=Program.GUI.ManualIDController.state(app); assert(strcmp(state.text,'AVAR') && state.dirty);
state.busy=true; Program.GUI.ManualIDController.put(app,state);
app.is_saving_ID=true; Program.GUI.ManualIDInput.setEnabled(app,'off');
ui.input.ValueChangingFcn(ui.input,struct('Value','IL1L'));
current=Program.GUI.ManualIDController.state(app);
assert(strcmp(current.text,'AVAR') && copy.annotation_store.revision==before);
Program.GUI.ManualIDController.release(app);
assert(strcmp(ui.input.Enable,'on') && ~app.is_saving_ID);

% Modified Enter has no annotation action; standard Tab finalizes native paste.
modifiers={'control','command'}; pasted={'AVAR?','IL2L?'};
for shortcut=1:numel(modifiers)
    Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
    Program.GUI.ManualIDController.select(app,2);
    Program.GUI.ManualIDController.renderText(app,'AVAL');
    Program.GUI.ManualIDController.edited(app,'AVAL');
    Program.GUI.ManualIDController.noteFocus(app,'input');
    state=Program.GUI.ManualIDController.state(app);
    state.pendingGesture=[]; state.keyGesture=[]; state.heldAssignmentKey='';
    Program.GUI.ManualIDController.put(app,state);
    Program.GUI.ManualIDController.highlight(app,find(strcmp({state.rows.token},'AVAL'),1));
    if shortcut==2, Program.GUI.ManualIDController.close(app); end
    before=Annotations.Store.fingerprint(app.id_file); revision=copy.annotation_store.revision;
    state=Program.GUI.ManualIDController.state(app);
    owner=state.key; selected=app.selected_neuron; z=app.ZSlider.Value;
    event=struct('Key','return','Modifier',{{modifiers{shortcut}}});
    Program.GUI.ManualIDController.windowKey(app,app.CELL_ID,event);
    current=Program.GUI.ManualIDController.state(app);
    assert(strcmp(current.focusRole,'input') && current.open==state.open && current.active==state.active);
    assert(strcmp(current.text,state.text) && current.generation==state.generation);
    assert(isempty(current.pendingGesture) && isempty(current.keyGesture) && isempty(current.heldAssignmentKey));
    assert(isequaln(before,Annotations.Store.fingerprint(app.id_file)));
    % No key release is needed to recover from the ignored input chord.
    event.Key='tab'; event.Modifier={};
    Program.GUI.ManualIDController.windowKey(app,app.CELL_ID,event);
    state=Program.GUI.ManualIDController.state(app); focusIntent=state.pendingGesture;
    assert(strcmp(state.focusRole,'assign') && strcmp(state.focusOwner,owner) && ~state.open);
    assert(strcmp(focusIntent.origin,'keyboard-focus') && isempty(state.heldAssignmentKey));
    ui.input.Value=pasted{shortcut}; ui.input.ValueChangedFcn(ui.input,[]);
    state=Program.GUI.ManualIDController.state(app);
    assert(strcmp(state.text,pasted{shortcut}) && strcmp(state.focusRole,'assign') && ~state.open);
    assert(state.pendingGesture.generation==state.generation && state.keyGesture.generation==state.generation);
    assert(strcmp(state.pendingGesture.operation_id,focusIntent.operation_id));
    assert(strcmp(state.key,owner) && copy.annotation_store.revision==revision);
    assert(isequaln(before,Annotations.Store.fingerprint(app.id_file)));
    % Native Return can supply only ButtonPushedData, without a WindowKeyPress.
    result=Program.GUI.ManualIDInput.commit(app,[],selected,matlab.ui.eventdata.ButtonPushedData());
    record=Program.GUI.ManualIDService.record(app,selected);
    assert(result.changed && copy.annotation_store.revision==revision+1 && strcmp(record.certainty,'tentative'));
    assert(isequal(record.candidates,{pasted{shortcut}(1:end-1)}));
    assert(app.selected_neuron==selected && app.ZSlider.Value==z);
    assert(isequaln(evidence,copy.annotation_store.evidence));
    % A duplicate native event stays with that operation after auto-advance.
    app.selected_neuron=1; Program.GUI.ManualIDController.select(app,1);
    Program.GUI.ManualIDController.edited(app,'IL2R?',false);
    Program.GUI.ManualIDController.noteFocus(app,'assign');
    after=Annotations.Store.fingerprint(app.id_file); next=Program.GUI.ManualIDService.record(app,1);
    result=Program.GUI.ManualIDInput.commit(app,[],1,matlab.ui.eventdata.ButtonPushedData());
    assert(~result.changed && result.replayed && copy.annotation_store.revision==revision+1);
    assert(app.selected_neuron==1 && isequaln(next,Program.GUI.ManualIDService.record(app,1)));
    assert(isequaln(after,Annotations.Store.fingerprint(app.id_file)));
end

% Only a pending same-context focus intent can absorb a final native value.
for origin={'mouse','keyboard','stale-focus'}
    Program.GUI.ManualIDController.select(app,2);
    Program.GUI.ManualIDController.edited(app,'AVAL?');
    if strcmp(origin{1},'mouse'), Program.GUI.ManualIDController.beginMouseGesture(app,'normal');
    elseif strcmp(origin{1},'keyboard'), Program.GUI.ManualIDController.beginKeyGesture(app,'space');
    else
        Program.GUI.ManualIDController.deferFocus(app,app.UserIDButton,'assign');
        state=Program.GUI.ManualIDController.state(app);
        state.pendingGesture.context.geometry_revision='stale';
        Program.GUI.ManualIDController.put(app,state);
    end
    state=Program.GUI.ManualIDController.state(app); command=state.pendingGesture;
    before=Annotations.Store.fingerprint(app.id_file);
    ui.input.Value='IL2R?'; ui.input.ValueChangedFcn(ui.input,[]);
    state=Program.GUI.ManualIDController.state(app);
    assert(state.pendingGesture.generation==command.generation && state.generation>command.generation);
    result=Program.GUI.ManualIDInput.commit(app,[],2,matlab.ui.eventdata.ButtonPushedData());
    assert(~result.changed && isequaln(before,Annotations.Store.fingerprint(app.id_file)));
    Program.GUI.ManualIDController.windowRelease(app,app.CELL_ID,struct('Key','space'));
end

% A repeated final value retains an explicitly staged unresolved family.
Program.GUI.ManualIDController.select(app,2);
Program.GUI.ManualIDController.edited(app,'IL1?');
state=Program.GUI.ManualIDController.state(app);
Program.GUI.ManualIDController.accept(app,find(strcmp({state.rows.kind},'keep'),1));
state=Program.GUI.ManualIDController.state(app); staged=state.staged;
Program.GUI.ManualIDController.deferFocus(app,app.UserIDButton,'assign');
ui.input.Value=state.text; ui.input.ValueChangedFcn(ui.input,[]);
state=Program.GUI.ManualIDController.state(app);
assert(isequaln(state.staged,staged) && strcmp(state.focusRole,'assign') && ~state.open);
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);

test_transaction_focus(app,ui);

% The search path reads the small catalog and annotations, never the volume.
app.selected_neuron=1;
Program.GUI.ManualIDController.select(app,1);
tic; Program.GUI.ManualIDController.suggestions(app,'IL1','',false); first=toc;
elapsed=zeros(1,100); queries={'IL1','AVA','AS','left','CAN','RME','AQR','ZZZ'};
for i=1:100
    tic; rows=Program.GUI.ManualIDController.suggestions(app,queries{mod(i-1,numel(queries))+1},'',false); elapsed(i)=toc;
    if strcmp(queries{mod(i-1,numel(queries))+1},'IL1')
        assert(sum(strcmp({rows.kind},'individual'))==6);
    end
end
ordered=sort(elapsed);
report=struct('queries',100,'first_seconds',first,'p95_seconds',ordered(95), ...
    'max_seconds',max(elapsed),'catalog_version',Annotations.Catalog.version());
fprintf('MANUAL_ID_OWNED_DRAFT_EXPLICIT_ASSIGN_UNRESOLVED_UNDO=PASS\n');
fprintf('MANUAL_ID_SEARCH_P95_SECONDS=%.6f\n',report.p95_seconds);
end

function test_transaction_focus(app,ui)
% Saving must not evict native focus to a neighboring run button.
key='manual_id_transaction_focus_test';
saved=struct('callback',getappdata(app.CELL_ID,'manual_id_after_commit'), ...
    'present',isappdata(app.CELL_ID,key),'counter',getappdata(app.CELL_ID,key));
cleanup=onCleanup(@() restore_transaction_probe(app,saved));
setappdata(app.CELL_ID,key,0);
setappdata(app.CELL_ID,'manual_id_after_commit',@(~,~,~) observe_transaction_focus(app));
app.selected_neuron=2; Program.GUI.ManualIDController.select(app,2);
Program.GUI.ManualIDController.edited(app,'AIBL?');
Program.GUI.ManualIDController.noteFocus(app,'assign');
result=Program.GUI.ManualIDController.assign(app,2);
assert(result.changed && ~isfield(result,'display_error') && getappdata(app.CELL_ID,key)==1);
assert(strcmp(app.UserIDButton.Enable,'on') && strcmp(ui.input.Enable,'on'));
Program.GUI.ManualIDController.undo(app);
assert(getappdata(app.CELL_ID,key)==2 && strcmp(app.UserIDButton.Enable,'on') && strcmp(ui.input.Enable,'on'));

% Finishing after the selection closes cannot enable an ownerless editor.
app.selected_neuron=[]; Program.GUI.ManualIDController.release(app);
assert(strcmp(app.UserIDButton.Enable,'off') && strcmp(ui.input.Enable,'off'));
app.selected_neuron=2; Program.GUI.ManualIDController.select(app,2);
Program.GUI.ManualIDController.release(app);
assert(strcmp(app.UserIDButton.Enable,'on') && strcmp(ui.input.Enable,'on'));
end

function observe_transaction_focus(app)
state=Program.GUI.ManualIDController.state(app); ui=Program.GUI.ManualIDController.ui(app);
assert(state.busy && app.is_saving_ID);
assert(strcmp(app.UserIDButton.Enable,'on') && strcmp(ui.input.Enable,'off'));
before=Annotations.Store.fingerprint(app.id_file);
repeated=Program.GUI.ManualIDController.assign(app,app.selected_neuron);
Program.GUI.ManualIDController.undo(app);
assert(~repeated.changed && isequaln(before,Annotations.Store.fingerprint(app.id_file)));
state=Program.GUI.ManualIDController.state(app); assert(state.busy);
key='manual_id_transaction_focus_test';
setappdata(app.CELL_ID,key,getappdata(app.CELL_ID,key)+1);
end

function restore_transaction_probe(app,saved)
if ~isvalid(app) || ~isvalid(app.CELL_ID), return; end
setappdata(app.CELL_ID,'manual_id_after_commit',saved.callback);
key='manual_id_transaction_focus_test';
if saved.present, setappdata(app.CELL_ID,key,saved.counter);
elseif isappdata(app.CELL_ID,key), rmappdata(app.CELL_ID,key); end
end

function reset_latch(app)
state=Program.GUI.ManualIDController.state(app); state.lastCommitTime=-Inf;
Program.GUI.ManualIDController.put(app,state);
end

function restore(app,saved,folder)
Program.GUI.ManualIDController.close(app);
Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
app.image_neurons=saved.neurons; app.id_file=saved.id_file;
app.selected_neuron=saved.selected; app.TabGroup.SelectedTab=saved.tab;
app.AutoNameCheckBox.Value=saved.auto; app.is_saving_ID=false;
setappdata(app.CELL_ID,'manual_id_controller',saved.state);
setappdata(app.CELL_ID,'manual_id_after_commit',saved.after);
setappdata(app.CELL_ID,'manual_id_file_snapshot',saved.snapshot);
if ~isempty(saved.selected), Program.GUI.ManualIDController.select(app,saved.selected); end
if exist(folder,'dir'), rmdir(folder,'s'); end
end
