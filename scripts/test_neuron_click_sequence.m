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
assert(double && ~state.pending);

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
end
fprintf('NEURON_CLICK_SEQUENCE=PASS\n');
end

function local_restore(app, state, tab, z)
setappdata(app.CELL_ID, 'neuron_click_sequence', state);
app.TabGroup.SelectedTab = tab; app.ZSlider.Value = z;
end
