function [applied, validation_msg] = apply_processing_rotation_to_neurons( ...
    app, rotate_actions, rotate_angle, original_dims, validate_only)
% Apply the active processing rotation actions to neuron coordinates.
% This keeps image and neuron geometry in sync when neuron-aware processing
% rotation is enabled.

if nargin < 1 || isempty(app)
    app = Program.app;
end
if nargin < 5 || isempty(validate_only)
    validate_only = false;
end

validation_msg = '';
applied = false;

if isempty(app) || ~isprop(app, 'image_neurons') || isempty(app.image_neurons)
    if validate_only
        validation_msg = 'Neuron geometry is not available for rotation validation.';
        return
    end
    applied = true;
    return
end

if nargin < 2 || isempty(rotate_actions)
    applied = true;
    return
end

if nargin < 3 || isempty(rotate_angle)
    rotate_angle = 0;
end

if nargin < 4 || isempty(original_dims)
    original_dims = size(app.image_data);
end

rotate_actions = cellstr(lower(string(rotate_actions)));
rotate_actions = rotate_actions(~cellfun('isempty', rotate_actions));
if isempty(rotate_actions)
    applied = true;
    return
end

if validate_only
    [applied, validation_msg] = validate_rotation_request(app, rotate_actions, rotate_angle);
    return
end

if isempty(app.image_neurons.neurons)
    applied = true;
    return
end

dims = double(original_dims(:).');
if numel(dims) < 2
    dims(end+1:2) = 1;
end
if numel(dims) < 3
    dims(end+1:3) = 1;
end
dims = dims(1:3);
if any(~isfinite(dims)) || any(dims <= 0)
    applied = true;
    return
end

try
    rotate_angle = Program.GUIHandling.canonical_rotation_angle(rotate_angle);
    rot_proxy = zeros(round(dims(1)), round(dims(2)), round(dims(3)));

    for n = 1:numel(rotate_actions)
        switch rotate_actions{n}
            case 'hori'
                rot_proxy = app.image_neurons.rotate_X_180(rot_proxy);
            case 'vert'
                rot_proxy = app.image_neurons.rotate_Y_180(rot_proxy);
            case 'rotate'
                switch rotate_angle
                    case 90
                        [rot_proxy, ~] = app.image_neurons.rotate_Z_90(rot_proxy, [1 1 1]);
                    case 180
                        rot_proxy = app.image_neurons.rotate_X_180(rot_proxy);
                        rot_proxy = app.image_neurons.rotate_Y_180(rot_proxy);
                    case 270
                        [rot_proxy, ~] = app.image_neurons.rotate_Z_270(rot_proxy, [1 1 1]);
                    otherwise
                        % Arbitrary-angle rotations are handled upstream.
                        return
                end
        end
    end

    if isprop(app.image_neurons, 'scale') && isprop(app, 'image_um_scale')
        neuron_scale = double(app.image_um_scale(:).');
        if numel(neuron_scale) < 3
            neuron_scale(end+1:3) = 1;
        end
        app.image_neurons.scale = neuron_scale(1:3);
    end

    applied = true;
catch
    applied = false;
end
end

function [tf, msg] = validate_rotation_request(app, rotate_actions, rotate_angle)
    tf = true;
    msg = '';

    if ~isobject(app.image_neurons)
        tf = false;
        msg = 'Neuron geometry object is not available.';
        return
    end

    if isa(app.image_neurons, 'handle')
        try
            if ~isvalid(app.image_neurons)
                tf = false;
                msg = 'Neuron geometry object is not valid.';
                return
            end
        catch
            tf = false;
            msg = 'Neuron geometry object is not valid.';
            return
        end
    end

    if ~isprop(app.image_neurons, 'neurons')
        tf = false;
        msg = 'Neuron object does not expose neuron coordinates.';
        return
    end

    valid_actions = {'hori', 'vert', 'rotate'};
    invalid = setdiff(rotate_actions, valid_actions);
    if ~isempty(invalid)
        tf = false;
        msg = sprintf('Unsupported neuron rotation action: %s.', strjoin(invalid, ', '));
        return
    end

    if any(strcmpi(rotate_actions, 'hori')) && ...
            ~ismethod(app.image_neurons, 'rotate_X_180')
        tf = false;
        msg = 'Neuron object does not support horizontal flip.';
        return
    end

    if any(strcmpi(rotate_actions, 'vert')) && ...
            ~ismethod(app.image_neurons, 'rotate_Y_180')
        tf = false;
        msg = 'Neuron object does not support vertical flip.';
        return
    end

    if any(strcmpi(rotate_actions, 'rotate'))
        rotate_angle = Program.GUIHandling.canonical_rotation_angle(rotate_angle);
        if ~ismember(rotate_angle, [90, 180, 270])
            tf = false;
            msg = 'Neuron geometry rotation is limited to 90, 180, and 270 degrees.';
            return
        end

        switch rotate_angle
            case 90
                if ~ismethod(app.image_neurons, 'rotate_Z_90')
                    tf = false;
                    msg = 'Neuron object does not support 90 degree rotation.';
                    return
                end
            case 180
                if ~ismethod(app.image_neurons, 'rotate_X_180') || ...
                        ~ismethod(app.image_neurons, 'rotate_Y_180')
                    tf = false;
                    msg = 'Neuron object does not support 180 degree rotation.';
                    return
                end
            case 270
                if ~ismethod(app.image_neurons, 'rotate_Z_270')
                    tf = false;
                    msg = 'Neuron object does not support 270 degree rotation.';
                    return
                end
        end
    end
end
