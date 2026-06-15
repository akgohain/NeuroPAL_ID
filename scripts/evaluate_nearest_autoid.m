function evaluate_nearest_autoid(nwb_path, truth_csv, output_csv, varargin)
%EVALUATE_NEAREST_AUTOID Run legacy atlas auto-ID without leaking labels.

opts = struct();
opts.Transform = "none";
opts.Sex = "";
if mod(numel(varargin), 2) ~= 0
    error('Options must be name/value pairs.');
end
for arg_i = 1:2:numel(varargin)
    opts.(char(varargin{arg_i})) = string(varargin{arg_i + 1});
end

repo_root = fileparts(fileparts(mfilename('fullpath')));
cd(repo_root);
addpath(genpath(repo_root));

[data, info, ~, worm] = DataHandling.NeuroPALImage.open(nwb_path);
if strlength(opts.Sex) > 0
    worm.sex = char(opts.Sex);
end
truth = readtable(truth_csv, 'TextType', 'string');
truth = truth(truth.recognized == 1, :);

positions = [truth.x, truth.y, truth.z];
switch lower(opts.Transform)
    case "none"
    case "swapxy"
        positions(:, [1, 2]) = positions(:, [2, 1]);
    case "flipx"
        positions(:, 1) = size(data, 1) + 1 - positions(:, 1);
    case "flipy"
        positions(:, 2) = size(data, 2) + 1 - positions(:, 2);
    case "swapxy_flipx"
        positions(:, [1, 2]) = positions(:, [2, 1]);
        positions(:, 1) = size(data, 1) + 1 - positions(:, 1);
    case "swapxy_flipy"
        positions(:, [1, 2]) = positions(:, [2, 1]);
        positions(:, 2) = size(data, 2) + 1 - positions(:, 2);
    otherwise
        error('Unknown Transform: %s', opts.Transform);
end
n = size(positions, 1);
channel_count = size(data, 4);
rgbw = 1:min(4, channel_count);
colors = nan(n, 4);
for i = 1:n
    x = min(max(round(positions(i, 1)), 1), size(data, 1));
    y = min(max(round(positions(i, 2)), 1), size(data, 2));
    z = min(max(round(positions(i, 3)), 1), size(data, 3));
    sample = squeeze(data(x, y, z, rgbw));
    colors(i, 1:numel(sample)) = double(sample(:)).';
end

sp = struct();
sp.positions = positions;
sp.color = colors;
sp.color_readout = colors;
sp.baseline = nan(n, 4);
sp.covariances = repmat(reshape(eye(3), [1, 3, 3]), [n, 1, 1]);
sp.annotation = repmat({''}, n, 1);
sp.annotation_confidence = zeros(n, 1);
sp.is_annotation_on = nan(n, 1);
sp.is_emphasized = false(n, 1);

neurons = Neurons.Image(sp, 'scale', info.scale);
Methods.AutoId.instance().id(char(nwb_path), neurons, worm);

predicted = string(neurons.get_deterministic_ids());
out = table((0:n-1).', truth.roi_idx, truth.label, predicted(:), ...
    'VariableNames', {'eval_idx', 'roi_idx', 'truth_label', 'predicted_id'});

output_dir = fileparts(output_csv);
if strlength(string(output_dir)) > 0 && ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
writetable(out, output_csv);
fprintf('nearest_rows=%d out=%s\n', height(out), output_csv);
end
