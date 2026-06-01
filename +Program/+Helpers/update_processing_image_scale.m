function scale = update_processing_image_scale(app, actions, original_dims)
% Keep physical display scale coherent when processing changes volume size.

if nargin < 1 || isempty(app)
    app = Program.app;
end

scale = app.image_um_scale;
if isempty(scale)
    scale = [1 1 1];
end
scale = double(scale(:).');
if numel(scale) < 3
    scale(end+1:3) = 1;
end
scale(~isfinite(scale) | scale <= 0) = 1;

if nargin < 2 || isempty(actions) || nargin < 3 || isempty(original_dims)
    app.image_um_scale = scale;
    scale = local_store_scale(app, scale);
    return
end

actions = cellstr(lower(string(actions)));
actions = actions(~cellfun('isempty', actions));
dims = double(original_dims(:).');
if numel(dims) < 3
    dims(end+1:3) = 1;
end

for n = 1:numel(actions)
    action = actions{n};
    try
        next_dims = Methods.ChunkyMethods.calc_pp_size(app, action, dims);
    catch
        next_dims = dims;
    end
    next_dims = double(next_dims(:).');
    if numel(next_dims) < 3
        next_dims(end+1:3) = 1;
    end

    switch action
        case 'ds'
            scale(1) = local_preserve_extent_scale(scale(1), dims(2), next_dims(2));
            scale(2) = local_preserve_extent_scale(scale(2), dims(1), next_dims(1));
            scale(3) = local_preserve_extent_scale(scale(3), dims(3), next_dims(3));

        case {'cc', 'acc'}
            scale(1:2) = scale([2 1]);
    end

    dims = next_dims;
end

app.image_um_scale = scale;
scale = local_store_scale(app, scale);
end

function new_scale = local_preserve_extent_scale(old_scale, old_n, new_n)
if old_n > 1 && new_n > 1
    new_scale = old_scale * (old_n - 1) / (new_n - 1);
else
    new_scale = old_scale;
end
end

function scale = local_store_scale(app, scale)
try
    if isstruct(app.image_info)
        app.image_info.scale = scale;
    end
catch
end
end
