function test_neuron_click_sequence(app)
%TEST_NEURON_CLICK_SEQUENCE Keep rapid clicks on unrelated targets separate.
advance = @Program.Handlers.neurons.advance_click;
[double, first] = advance([], [30 40], 3, 'image', 1, 10, 0.3);
assert(~double && first.pending);
[double, second] = advance(first, [31 41], 3, 'image', 1, 10.2, 0.3);
assert(double && ~second.pending && second.serial ~= first.serial);
[double, third] = advance(second, [31 41], 3, 'image', 1, 10.25, 0.3);
assert(~double && third.pending);

[double, ~] = advance(first, [30 40], 3, 'image', 1, 10.31, 0.3);
assert(~double);

% A native double-click may be slower than our rapid-click fallback.
[double, native] = advance(first, [30 40], 3, 'image', 1, 10.5, 0.3, true);
assert(double && ~native.pending);
[double, ~] = advance(native, [30 40], 3, 'image', 1, 10.51, 0.3, true);
assert(~double, 'A completed double-click must not be replayed.');
[double, ~] = advance([], [30 40], 3, 'image', 1, 10.5, 0.3, true);
assert(~double, 'A native event needs a matching first click.');
[double, ~] = advance(first, [30 40], 3, 'neuron:1', 1, 10.5, 0.3, true);
assert(~double);
[double, ~] = advance(first, [35 40], 3, 'image', 1, 10.5, 0.3, true);
assert(~double);
[double, ~] = advance(first, [30 40], 4, 'image', 1, 10.5, 0.3, true);
assert(~double);
[double, ~] = advance(first, [30 40], 3, 'image', 1, 9, 0.3, true);
assert(~double);
cancelled = first; cancelled.pending = false;
[double, ~] = advance(cancelled, [30 40], 3, 'image', 1, 10.5, 0.3, true);
assert(~double, 'A changed source must cancel even a native double-click.');
[~, marker] = advance([], [30 40], 3, 'neuron:1', 1, 10, 0.3);
[double, ~] = advance(marker, [30 40], 3, 'neuron:1', 1, 10.5, 0.3, true);
assert(double, 'A marker keeps its own select/delete click sequence.');
[double, ~] = advance(first, [30 40], 3, 'neuron:1', 1, 10.2, 0.3);
assert(~double);
[double, ~] = advance(first, [35 40], 3, 'image', 1, 10.2, 0.3);
assert(~double);
[double, ~] = advance(first, [30 40], 4, 'image', 1, 10.2, 0.3);
assert(~double);
[double, ~] = advance(first, [30 40], 3, 'image', 1, 9, 0.3);
assert(~double);
[double, state] = advance(first, [30 40], 3, 'image', 3, 10.2, 0.3);
assert(~double && ~state.pending);
[double, state] = advance([], [30 40], 3, 'image', 2, 10, 0.3);
assert(double && ~state.pending, 'Keep the middle-button add shortcut.');
[double, state] = advance(first, [30 40], 3, 'image', 2, 10.5, 0.3, true);
assert(double && ~state.pending);
[double, state] = advance(first, [30 40], 3, 'image', 3, 10.5, 0.3, true);
assert(~double && ~state.pending);

if nargin > 0
    previous = getappdata(app.CELL_ID, 'neuron_click_sequence');
    tab = app.TabGroup.SelectedTab; z = app.ZSlider.Value;
    cleanup = onCleanup(@() local_restore(app, previous, tab, z));
    hit = struct('IntersectionPoint', [30 40 0], 'Button', 1);
    if isappdata(app.CELL_ID, 'neuron_click_sequence'), rmappdata(app.CELL_ID, 'neuron_click_sequence'); end
    [double, token] = Program.Handlers.neurons.begin_click(app, hit, 'image');
    assert(~double && Program.Handlers.neurons.is_pending_click(app, token));
    app.TabGroup.SelectedTab = app.LogTab;
    assert(~Program.Handlers.neurons.is_pending_click(app, token));
    app.TabGroup.SelectedTab = tab;

    hit.Button = 3;
    Program.Handlers.neurons.begin_click(app, hit, 'image');
    assert(~Program.Handlers.neurons.is_pending_click(app, token));
    hit.Button = 1;
    [~, token] = Program.Handlers.neurons.begin_click(app, hit, 'image');
    state = getappdata(app.CELL_ID, 'neuron_click_sequence');
    state.revision = state.revision + uint64(1);
    setappdata(app.CELL_ID, 'neuron_click_sequence', state);
    assert(~Program.Handlers.neurons.is_pending_click(app, token));

    if ~isempty(app.image_neurons) && ~isempty(app.image_neurons.neurons)
        [double, token] = Program.Handlers.neurons.begin_click(app, hit, 'neuron:1');
        assert(~double && Program.Handlers.neurons.is_pending_click(app, token));
        state = getappdata(app.CELL_ID, 'neuron_click_sequence');
        state.neuron = Neurons.Neuron();
        setappdata(app.CELL_ID, 'neuron_click_sequence', state);
        assert(~Program.Handlers.neurons.is_pending_click(app, token));
    end
    local_add_feedback(app);
end
fprintf('NEURON_CLICK_SEQUENCE=PASS\n');
end

function local_restore(app, state, tab, z)
setappdata(app.CELL_ID, 'neuron_click_sequence', state);
app.TabGroup.SelectedTab = tab; app.ZSlider.Value = z;
end

function local_add_feedback(app)
% Exercise the installed image callback on a disposable annotated volume.
original = app.image_file;
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() local_restore_image(original,folder));
file = fullfile(folder,'add-feedback.mat');
data = zeros(31,47,7,4,'uint16'); data(5,5,3,:) = 1000;
info = app.image_info; info.scale = [.3 .7 1.5];
prefs = app.image_prefs; prefs.RGBW = [1 2 3 4];
prefs.DIC = NaN; prefs.GFP = NaN; prefs.is_Z_flip = false;
worm = struct('body','Head','age','Adult','sex','XX','strain','','notes','');
version = Program.ProgramInfo.version;
neurons = Neurons.Image([],'Head','scale',info.scale);
neuron = Neurons.Neuron(); neuron.position = [5 5 3];
neuron.annotation = 'AVAL'; neuron.annotation_confidence = 1;
neuron.color_readout = [1 1 1 1];
neuron.deterministic_id = 'AVAL'; neuron.probabilistic_ids = {'AVAL','AVAR'};
neuron.probabilistic_probs = [.6 .4]; neuron.rank = 1;
neurons.neurons = neuron; mp_params = app.mp_params;
save(file,'data','info','prefs','worm','version','-v7.3');
save(fullfile(folder,'add-feedback_ID.mat'),'neurons','version','mp_params');
Program.Routines.open(file);
app.TabGroup.SelectedTab = app.NeuroPALIDTab;
app.ZSlider.Value = 3;
Program.Routines.ID.get_slice(app.ZSlider,app.image_view,app.XY);
before = Program.GUI.ManualIDService.ensure(app);
old_positions = app.image_neurons.get_positions();
image = getappdata(app.XY,'main_slice_image');
callback = image.ButtonDownFcn;
hit = struct('IntersectionPoint',[29 21 0],'Button',3);
local_click(callback,image,hit);
assert(app.image_neurons.num_neurons()==1);
hit.Button = 1; local_click(callback,image,hit);
assert(app.image_neurons.num_neurons()==1);
local_click(callback,image,hit);
assert(app.image_neurons.num_neurons()==2);
assert(app.selected_neuron==2 && app.image_neurons.neurons(2).is_selected);
palette = Neurons.Neuron.marker_palette();
assert(isequal(app.image_neurons.neurons(2).get_marker_color(),palette.selected));
ui = Program.GUI.ManualIDController.ui(app);
state = Program.GUI.ManualIDController.state(app);
assert(strcmp(ui.input.Enable,'on') && strcmp(app.UserIDButton.Enable,'on'));
assert(isempty(ui.input.Value) && ~state.dirty);
after = Program.GUI.ManualIDService.ensure(app);
assert(strcmp(state.context.owner_id,after.records(2).owner_id));
assert(strcmp(after.records(2).kind,'unassigned'));
assert(isequaln(before.records,after.records(1)));
assert(isequaln(before.evidence,after.evidence(1:numel(before.evidence))));
positions = app.image_neurons.get_positions();
assert(isequaln(old_positions,positions(1,:)));
assert(isequal(positions(2,:),[flip(hit.IntersectionPoint(1:2))+app.mouse_offset 3]));
saved = load(app.id_file,'neurons','annotation_store');
assert(saved.neurons.num_neurons()==2);
assert(isequaln(saved.annotation_store,after));
assert(isequal(saved.neurons.get_positions(),positions));
assert(isequal(app.image_data,data));

% The legacy middle-button shortcut gives the same selected, saved result.
hit.IntersectionPoint = [39 25 0]; hit.Button = 2;
image = getappdata(app.XY,'main_slice_image');
local_click(image.ButtonDownFcn,image,hit);
assert(app.image_neurons.num_neurons()==3);
assert(app.selected_neuron==3 && app.image_neurons.neurons(3).is_selected);
assert(isequal(app.image_neurons.neurons(3).get_marker_color(),palette.selected));
assert(~app.image_neurons.neurons(2).is_selected);
state = Program.GUI.ManualIDController.state(app);
final = Program.GUI.ManualIDService.ensure(app);
assert(strcmp(state.context.owner_id,final.records(3).owner_id));
assert(strcmp(final.records(3).kind,'unassigned'));
assert(isequaln(after.records,final.records(1:2)));
assert(isequaln(after.evidence,final.evidence(1:numel(after.evidence))));
final_positions = app.image_neurons.get_positions();
assert(isequal(final_positions(1:2,:),positions));
assert(isequal(final_positions(3,:),[flip(hit.IntersectionPoint(1:2))+app.mouse_offset 3]));
saved = load(app.id_file,'neurons','annotation_store');
assert(saved.neurons.num_neurons()==3);
assert(isequaln(saved.annotation_store,final));
assert(isequal(saved.neurons.get_positions(),final_positions));
assert(isequal(app.image_data,data));
fprintf('MAIN_NEW_NEURON_SELECTED_OWNED_SAVED=PASS\n');
end

function local_click(callback,source,hit)
if iscell(callback), callback{1}(source,hit,callback{2:end});
else, callback(source,hit); end
end

function local_restore_image(file,folder)
Program.Routines.open(file);
if isfolder(folder), rmdir(folder,'s'); end
end
