function predictions = runCRFID2AutoID(positions_yxz, colors_rgbw, scale_um_xyz, options)
%RUNCRFID2AUTOID Stage an app request for a packaged CRF Cell-ID 2.0 adapter.

arguments
    positions_yxz double
    colors_rgbw double
    scale_um_xyz double
    options.BundlePath (1,1) string = ""
    options.OutputDir (1,1) string = ""
    options.KeepArtifacts (1,1) logical = false
end

readiness = Methods.MethodBundle.inspect('crf_cellid_2', options.BundlePath);
if ~readiness.ready
    error('Wrapper:CRFID2BundleUnavailable', '%s', readiness.summary);
end
scale = double(scale_um_xyz(:)');
if size(positions_yxz, 2) < 3 || size(colors_rgbw, 1) ~= size(positions_yxz, 1) || ...
        size(colors_rgbw, 2) < 4 || any(~isfinite(positions_yxz(:, 1:3)), 'all') || ...
        any(~isfinite(colors_rgbw(:, 1:4)), 'all') || numel(scale) ~= 3 || ...
        any(~isfinite(scale)) || any(scale <= 0)
    error('Wrapper:CRFID2InvalidInput', ...
        ['CRF-ID 2.0 requires one finite YXZ centroid and RGBW row per neuron, ' ...
         'plus three finite positive scale values.']);
end

output_dir = char(options.OutputDir);
if isempty(strtrim(output_dir))
    output_dir = tempname;
end
if exist(output_dir, 'dir') ~= 7
    mkdir(output_dir);
end
cleanup = onCleanup(@() local_cleanup(output_dir, options.KeepArtifacts));
request_path = fullfile(output_dir, 'crfid2_request.mat');
output_csv = fullfile(output_dir, 'predictions.csv');

request = struct();
request.schema_version = 1;
request.method_id = 'crf_cellid_2';
request.neuron_idx = (1:size(positions_yxz, 1))';
request.positions_yxz = double(positions_yxz(:, 1:3));
request.positions_xyz_um = [ ...
    (positions_yxz(:, 2) - 1) * scale(1), ...
    (positions_yxz(:, 1) - 1) * scale(2), ...
    (positions_yxz(:, 3) - 1) * scale(3)];
request.colors_rgbw = double(colors_rgbw(:, 1:4));
request.scale_um_xyz = scale;
request.bundle_path = readiness.bundle_path;
request.configuration = readiness.manifest.configuration;
save(request_path, '-struct', 'request', '-v7');

adapter_path = Methods.MethodBundle.artifact(readiness, 'adapter');
[adapter_dir, adapter_name] = fileparts(adapter_path);
old_path = path;
path_cleanup = onCleanup(@() local_restore_adapter(old_path, adapter_name));
addpath(adapter_dir, '-begin');
clear(adapter_name);
rehash;
try
    feval(adapter_name, request_path, output_csv, readiness.bundle_path);
catch ME
    error('Wrapper:CRFID2AdapterFailed', ...
        'CRF Cell-ID 2.0 adapter failed: %s', ME.message);
end
if exist(output_csv, 'file') ~= 2
    error('Wrapper:MissingCRFID2Predictions', ...
        'CRF Cell-ID 2.0 adapter did not write %s.', output_csv);
end
predictions = readtable(output_csv, 'TextType', 'string');
predictions = Methods.MethodContract.identity(predictions);
expected_indices = (1:size(positions_yxz, 1))';
if height(predictions) ~= numel(expected_indices) || ...
        ~isequal(sort(double(predictions.neuron_idx)), expected_indices)
    error('Wrapper:IncompleteCRFID2Predictions', ...
        'CRF Cell-ID 2.0 must return exactly one row for every request neuron.');
end
end

function local_restore_adapter(old_path, adapter_name)
clear(adapter_name);
path(old_path);
rehash;
end

function local_cleanup(output_dir, keep_artifacts)
if ~keep_artifacts && exist(output_dir, 'dir') == 7
    try
        rmdir(output_dir, 's');
    catch
    end
end
end
