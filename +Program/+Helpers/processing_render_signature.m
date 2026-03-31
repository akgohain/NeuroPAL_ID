function signature = processing_render_signature(app)
% Build a deterministic signature for the current processing render state.

if nargin < 1 || isempty(app)
    app = Program.app;
end

state = Program.Handlers.channels.processing_state(app);
rows = arrayfun(@local_row_signature, state.rows, 'UniformOutput', false);

payload = struct( ...
    'mode', char(string(app.VolumeDropDown.Value)), ...
    'dims', local_volume_dims(app), ...
    'threshold_pct', double(app.ProcNoiseThresholdField.Value), ...
    'flags', app.flags, ...
    'rows', {rows});

signature = jsonencode(payload);
end

function row = local_row_signature(row)
row = struct( ...
    'row', row.row, ...
    'role', char(string(row.role_key)), ...
    'enabled', logical(row.enabled), ...
    'source_idx', double(row.source_idx), ...
    'gamma', double(row.settings.gamma), ...
    'low_high_in', double(row.settings.low_high_in), ...
    'low_high_out', double(row.settings.low_high_out));
end

function dims = local_volume_dims(app)
switch char(string(app.VolumeDropDown.Value))
    case 'Colormap'
        dims = size(app.proc_image, 'data');
    case 'Video'
        dims = [app.video_info.ny, app.video_info.nx, app.video_info.nz, app.video_info.nc, app.video_info.nt];
    otherwise
        dims = [];
end
end
