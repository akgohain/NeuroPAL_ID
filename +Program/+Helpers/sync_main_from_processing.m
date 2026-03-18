function synced = sync_main_from_processing(app)
synced = false;

if isempty(app.image_data) || isempty(app.proc_image)
    return
end

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
queries = {'r', 'g', 'b', 'white', 'dic', 'gfp'};

for k = 1:numel(queries)
    idx = Program.Handlers.channels.get_channel_idx(queries{k});
    if ~isempty(idx) && idx > 0
        app.(main_dropdowns{k}).Value = num2str(idx);
    end

    row = local_query_to_row(queries{k});
    if ~isempty(row)
        cb_handle = sprintf(Program.Handlers.channels.handles{'pp_cb'}, row);
        app.(main_checks{k}).Value = app.(cb_handle).Value;
    end
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

function row = local_query_to_row(query)
switch lower(string(query))
    case "r"
        row = 1;
    case "g"
        row = 2;
    case "b"
        row = 3;
    otherwise
        row = Program.Helpers.decode_references(char(lower(string(query))));
        if ~isempty(row)
            row = row(1);
        end
end
end
