function result = process_mat_transaction(source_path, requested_path, metadata, transform, source_z, progress, varargin)
%PROCESS_MAT_TRANSACTION Process slices into a new, complete MAT output.

if nargin < 6
    progress = [];
end
p = inputParser;
addParameter(p, 'CancelFcn', @() false);
addParameter(p, 'CheckFcn', @() []);
parse(p, varargin{:});
if ~isstruct(metadata) || isfield(metadata, 'data')
    error('DataHandling:Processing:InvalidMetadata', 'Processing metadata must exclude image pixels.');
end

source = DataHandling.Helpers.npal_mat.open_source(source_path);
validateattributes(source_z, {'numeric'}, ...
    {'vector', 'finite', 'positive', 'integer', '<=', source.dims(3)});
signature = DataHandling.Helpers.large_file.source_signature(source_path);
budget = DataHandling.Helpers.large_file.memory_budget_bytes();
source_bytes = prod(double(source.dims([1 2 4]))) * ...
    DataHandling.Helpers.large_file.bytes_per_element(source.source_class);
local_check_budget(source_bytes, budget);
target_path = local_available_path(char(requested_path));
[folder, name, ext] = fileparts(target_path);
if isempty(folder)
    folder = pwd;
end
[~, token] = fileparts(tempname(folder));
partial = fullfile(folder, ['.' name '.' token '.npal-partial' ext]);
cleanup = onCleanup(@() local_remove_partial(partial));

local_check(progress, p.Results);
sample = source.reader.data(:, :, source_z(1), :);
sample = local_normalize_slice(transform(sample));
local_check(progress, p.Results);
out_dims = [size(sample, 1), size(sample, 2), numel(source_z), size(sample, 4)];
output_class = class(sample);
output_bytes = numel(sample) * DataHandling.Helpers.large_file.bytes_per_element(output_class);
local_check_budget(output_bytes, budget);
DataHandling.Helpers.large_file.assert_sufficient_disk_space( ...
    target_path, prod(double(out_dims)) * DataHandling.Helpers.large_file.bytes_per_element(output_class));
save(partial, '-struct', 'metadata', '-v7.3');
target = matfile(partial, 'Writable', true);
target.data(out_dims(1), out_dims(2), out_dims(3), out_dims(4)) = cast(0, output_class);
target.data(:, :, 1, :) = sample;
local_progress(progress, 1, numel(source_z));

for z = 2:numel(source_z)
    local_check(progress, p.Results);
    slice = source.reader.data(:, :, source_z(z), :);
    slice = local_normalize_slice(transform(slice));
    if ~strcmp(class(slice), output_class) || ...
            ~isequal([size(slice, 1), size(slice, 2), size(slice, 4)], out_dims([1 2 4]))
        error('DataHandling:Processing:InconsistentSlice', ...
            'Processing changed the output shape or type between slices.');
    end
    target.data(:, :, z, :) = slice;
    local_progress(progress, z, numel(source_z));
end

local_check(progress, p.Results);
actual_dims = size(target, 'data');
actual_dims(end+1:4) = 1;
if ~isequal(actual_dims, out_dims) || ~isequaln(target.data(:, :, 1, :), sample)
    error('DataHandling:Processing:VerificationFailed', 'Processed MAT verification failed.');
end
stored = whos(target, 'data');
if ~strcmp(stored.class, output_class)
    error('DataHandling:Processing:VerificationFailed', 'Processed pixel type does not match the requested output.');
end
clear target
local_check(progress, p.Results);
if ~isequal(signature, DataHandling.Helpers.large_file.source_signature(source_path))
    error('DataHandling:Processing:SourceChanged', 'The source MAT file changed during processing.');
end
DataHandling.Helpers.large_file.promote(partial, target_path);
clear cleanup
result = struct('path', target_path, 'dims', out_dims, 'source_class', output_class);
end

function path = local_available_path(requested)
path = requested;
[folder, name, ext] = fileparts(requested);
counter = 2;
while exist(path, 'file') ~= 0
    path = fullfile(folder, sprintf('%s_%03d%s', name, counter, ext));
    counter = counter + 1;
end
end

function slice = local_normalize_slice(slice)
validateattributes(slice, {'numeric', 'logical'}, {'nonempty', 'real', 'nonsparse'});
dims = size(slice);
if numel(dims) == 3
    slice = reshape(slice, dims(1), dims(2), 1, dims(3));
end
if ndims(slice) > 4 || size(slice, 3) ~= 1
    error('DataHandling:Processing:InvalidSlice', 'Processing must return one XY slice across channels.');
end
end

function local_check_budget(bytes, budget)
if bytes * 2.5 > budget
    error('DataHandling:Processing:SliceTooLarge', ...
        'One processing slice exceeds the working-memory budget. Create a smaller source or increase NEUROPAL_IO_CHUNK_MIB.');
end
end

function local_check(progress, options)
drawnow limitrate;
cancelled = options.CancelFcn();
if isobject(progress) && isvalid(progress) && isprop(progress, 'CancelRequested')
    cancelled = cancelled || progress.CancelRequested;
end
if cancelled
    error('DataHandling:Processing:Cancelled', 'Processing cancelled; no output was published.');
end
options.CheckFcn();
end

function local_progress(progress, index, count)
if isobject(progress) && isvalid(progress)
    progress.Message = sprintf('Processing slice %d/%d...', index, count);
    progress.Value = index / count;
end
end

function local_remove_partial(path)
if isfile(path)
    delete(path);
end
end
