function neurons = transform_processing_neurons(app, neurons, action, dims, output_dims)
% Transform neuron centers using the same pixel coordinates as the image.
if isempty(neurons) || isempty(neurons.neurons), return; end
positions = neurons.get_positions();
keep = true(size(positions,1),1);
geometry = true;
switch action
    case 'hori'
        positions(:,2) = dims(2) + 1 - positions(:,2);
    case 'vert'
        positions(:,1) = dims(1) + 1 - positions(:,1);
    case 'mirrorz'
        positions(:,3) = dims(3) + 1 - positions(:,3);
    case {'rotate', 'cc', 'acc'}
        angle = app.proc_rot_spinner.Value;
        if strcmp(action,'cc'), angle = -90; end
        if strcmp(action,'acc'), angle = 90; end
        positions = rotate_centers(positions, dims, output_dims, angle);
    case 'crop'
        crop = app.rotation_stack.cache.Colormap;
        mask = imrotate(crop.mask, -crop.angle);
        rows = find(any(mask,2)); columns = find(any(mask,1));
        if isempty(rows) || isempty(columns)
            error('NeuroPAL:EmptyCrop', 'Draw a crop that includes part of the image.');
        end
        positions = rotate_centers(positions, dims, size(mask), -crop.angle);
        positions(:,1:2) = positions(:,1:2) - [rows(1)-1, columns(1)-1];
        keep = all(positions(:,1:2) >= 0.5 & positions(:,1:2) <= output_dims(1:2)+0.5, 2);
    case 'ds'
        positions(:,1:2) = (positions(:,1:2)-0.5) .* (output_dims(1:2)./dims(1:2)) + 0.5;
        slices = Methods.ChunkyMethods.proc_target_slices(dims(3), output_dims(3));
        if numel(slices) == 1
            keep = abs(positions(:,3)-slices) <= 0.5;
            positions(:,3) = 1;
        else
            positions(:,3) = interp1(slices, 1:numel(slices), positions(:,3), 'linear', 'extrap');
        end
    otherwise
        geometry = false;
end
if ~geometry, return; end
neurons.neurons = neurons.neurons(keep);
positions = positions(keep,:);
for i = 1:numel(neurons.neurons)
    neuron = neurons.neurons(i);
    neuron.position = min(max(positions(i,:), 1), output_dims(1:3));
    neuron.aligned_xyzRGB = [];
    neuron.covariance = nan(1,3,3);
    neuron.is_selected = false;
end
end

function positions = rotate_centers(positions, dims, output_dims, angle)
% Image rows increase downward, so the row/column rotation has this order.
rotation = [cosd(angle), -sind(angle); sind(angle), cosd(angle)];
positions(:,1:2) = (positions(:,1:2)-(dims(1:2)+1)/2) * rotation' + (output_dims(1:2)+1)/2;
end
