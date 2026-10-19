function test_manual_id_input(app)
%TEST_MANUAL_ID_INPUT Keep editing, atlas lookup and image shortcuts independent.
if nargin<1, app=Program.app; end
ui=Program.GUI.ManualIDController.ui(app);
assert(isa(ui.input,'matlab.ui.control.EditField'));
assert(strcmp(app.UserLabel.Text,'ID:') && strcmp(app.IDEditField.Visible,'off'));
assert(isempty(findall(app.GridLayout24_2,'Type','uibutton','Text','Choose ID ▾')));
saved=struct('state',Program.GUI.ManualIDController.state(app), ...
    'value',app.IDEditField.Value,'enable',app.IDEditField.Enable, ...
    'sex',app.SexDropDown.Value,'worm',app.worm,'selected',app.selected_neuron, ...
    'auto',app.AutoNameCheckBox.Value,'button',app.UserIDButton.Text);
saved.state.drafts=copy_map(saved.state.drafts);
cleanup=onCleanup(@() restore(app,saved));
if isempty(app.selected_neuron), app.selected_neuron=1; end
Program.GUI.ManualIDController.select(app,app.selected_neuron);
before=Annotations.Store.fingerprint(app.id_file);
Program.GUI.ManualIDController.edited(app,'il1l?! ');
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.text,'il1l?! ') && state.dirty && state.active==0);
draft=Program.GUI.ManualIDController.capture(app);
assert(draft.valid && strcmp(draft.certainty,'tentative') && draft.attributes.emphasized);
assert(isequaln(before,Annotations.Store.fingerprint(app.id_file)));
assert(~Program.Helpers.main_shortcut_allowed(app,ui.input));
assert(~Program.Helpers.main_shortcut_allowed(app,ui.list));
assert(~Program.Helpers.main_shortcut_allowed(app,app.UserIDButton));

% Context changes refresh the catalog rather than preserving a filtered model list.
app.SexDropDown.Value='XO'; app.worm.sex='XO';
rows=Program.GUI.ManualIDController.suggestions(app,'CEM','',false);
assert(all(ismember({'CEMDL','CEMDR','CEMVL','CEMVR'},{rows.token})));
app.SexDropDown.Value='XX'; app.worm.sex='XX';
rows=Program.GUI.ManualIDController.suggestions(app,'CEM','',false);
assert(~any(strcmp({rows.token},'CEMDL')));
rows=Program.GUI.ManualIDController.suggestions(app,'CEMDL','',true);
assert(any(strcmp({rows.token},'CEMDL')));
rows=Program.GUI.ManualIDController.suggestions(app,'AS01','',false);
assert(~isempty(rows) && strcmp(rows(1).token,'AS1'));

Program.GUI.ManualIDInput.setEnabled(app,'off'); assert(strcmp(ui.input.Enable,'off'));
Program.GUI.ManualIDInput.setEnabled(app,'on'); assert(strcmp(ui.input.Enable,'on'));
app.AutoNameCheckBox.Value=~saved.auto;
app.AutoNameCheckBox.ValueChangedFcn(app.AutoNameCheckBox,[]);
prefs=Program.GUIPreferences.instance(); stored=load(prefs.prefs_file);
assert(prefs.is_auto_name==~saved.auto && stored.GUI_prefs.is_auto_name==~saved.auto);
Program.GUIHandling.send_focus(app.IDEditField);
assert(isequaln(before,Annotations.Store.fingerprint(app.id_file)));
fprintf('INLINE_MANUAL_ID_ATLAS_VALUE_FOCUS_PREFERENCES=PASS\n');
end

function copy=copy_map(map)
copy=containers.Map('KeyType','char','ValueType','any');
keys=map.keys;
for i=1:numel(keys), copy(keys{i})=map(keys{i}); end
end

function restore(app,saved)
Program.GUI.ManualIDController.close(app);
app.SexDropDown.Value=saved.sex; app.worm=saved.worm;
app.selected_neuron=saved.selected; app.UserIDButton.Text=saved.button;
Program.GUI.ManualIDController.put(app,saved.state);
Program.GUI.ManualIDInput.setValue(app,saved.value);
Program.GUI.ManualIDInput.setEnabled(app,saved.enable);
app.AutoNameCheckBox.Value=saved.auto; Program.GUI.ManualIDInput.saveAutoName(app);
end
