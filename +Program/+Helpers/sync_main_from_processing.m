function synced = sync_main_from_processing(app)
synced = false;

if isempty(app.image_data) || isempty(app.proc_image)
    return
end

state = Program.Handlers.channels.processing_state(app);
main_dropdowns = { ...
    'RDropDown', ...
    'GDropDown', ...
    'BDropDown', ...
    'WDropDown', ...
    'DICDropDown', ...
    'GFPDropDown'};
main_checks = { ...
    'RCheckBox', ...
    'GCheckBox', ...
    'BCheckBox', ...
    'WCheckBox', ...
    'DICCheckBox', ...
    'GFPCheckBox'};
rows = {state.r, state.g, state.b, state.white, state.dic, state.gfp};

for k = 1:numel(rows)
    idx = rows{k}.source_idx;
    if ~isempty(idx) && idx > 0
        app.(main_dropdowns{k}).Value = num2str(idx);
    end
    app.(main_checks{k}).Value = rows{k}.enabled;
end

gammas = zeros(1, length(Program.GUIHandling.pos_prefixes));
for n = 1:length(Program.GUIHandling.pos_prefixes)
    gammas(n) = app.(sprintf('%s_GammaEditField', Program.GUIHandling.pos_prefixes{n})).Value;
end
app.image_gamma = gammas(:);
app.image_prefs.gamma = app.image_gamma;

z_value = min(max(round(app.proc_zSlider.Value), app.ZSlider.Limits(1)), app.ZSlider.Limits(2));
app.ZSlider.Value = z_value;

Program.Routines.ID.render();
synced = true;
end
