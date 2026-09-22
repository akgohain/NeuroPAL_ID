function [positions, labels] = read_nwb_centers(file)
%READ_NWB_CENTERS Read NeuroPAL segmentation centers without loading image arrays.
paths = {'/processing/NeuroPAL/NeuroPALSegmentation/NeuroPALNeurons', ...
    '/processing/NeuroPAL/NeuroPALNeurons', ...
    '/processing/NeuroPAL/VolumeSegmentation', ...
    '/processing/NeuroPAL/ImageSegmentation/PlaneSegmentation'};
base = '';
for index = 1:numel(paths)
    try
        info = h5info(file, paths{index});
        if any(strcmp({info.Datasets.Name}, 'voxel_mask'))
            base = paths{index}; break
        end
    catch
    end
end
if isempty(base)
    error('DataHandling:NWBImport:Segmentation', 'No supported NeuroPAL segmentation was found in this NWB.');
end
mask = h5read(file, [base '/voxel_mask']);
if isstruct(mask) && all(isfield(mask, {'x', 'y', 'z'}))
    xyz = double([mask.x(:), mask.y(:), mask.z(:)]);
    weights = ones(size(xyz, 1), 1);
    if isfield(mask, 'weight'), weights = double(mask.weight(:)); end
elseif isnumeric(mask) && size(mask, 1) >= 3 && size(mask, 1) <= 4
    xyz = double(mask(1:3, :)');
    weights = ones(size(xyz, 1), 1);
    if size(mask, 1) == 4, weights = double(mask(4, :)'); end
else
    error('DataHandling:NWBImport:Mask', 'Unsupported NeuroPAL voxel-mask format.');
end
if any(~isfinite(xyz), 'all') || any(xyz < 0, 'all') || any(~isfinite(weights) | weights < 0)
    error('DataHandling:NWBImport:Mask', 'The NWB contains invalid voxel coordinates or weights.');
end
ends = (1:size(xyz, 1))';
if any(strcmp({info.Datasets.Name}, 'voxel_mask_index'))
    ends = double(h5read(file, [base '/voxel_mask_index'])); ends = ends(:);
end
if isempty(ends) || any(diff([0; ends]) <= 0) || ends(end) ~= size(xyz, 1)
    error('DataHandling:NWBImport:Mask', 'Invalid voxel-mask row indices.');
end
positions = zeros(numel(ends), 3);
first = 1;
for row = 1:numel(ends)
    selected = first:ends(row); first = ends(row)+1;
    if sum(weights(selected)) <= 0
        error('DataHandling:NWBImport:Mask', 'A neuron has no positive voxel weights.');
    end
    center = sum(xyz(selected, :) .* weights(selected), 1) / sum(weights(selected));
    positions(row, :) = center([2 1 3]) + 1;
end
labels = repmat({''}, size(positions, 1), 1);
if any(strcmp({info.Datasets.Name}, 'ID_labels'))
    values = cellstr(string(h5read(file, [base '/ID_labels'])));
    if any(strcmp({info.Datasets.Name}, 'ID_labels_index'))
        indices = double(h5read(file, [base '/ID_labels_index'])); indices = indices(:);
        if numel(indices) ~= numel(ends) || any(diff([0; indices]) < 0) || indices(end) > numel(values)
            error('DataHandling:NWBImport:Labels', 'Invalid neuron-label row indices.');
        end
        first = 1;
        for row = 1:numel(indices)
            labels{row} = strjoin(values(first:indices(row)), ''); first = indices(row)+1;
        end
    elseif numel(values) == numel(ends)
        labels = values;
    else
        error('DataHandling:NWBImport:Labels', 'Neuron labels do not match the segmentation.');
    end
end
end
