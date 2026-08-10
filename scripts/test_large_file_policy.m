function test_large_file_policy()
%TEST_LARGE_FILE_POLICY Fast deterministic checks for conversion safeguards.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() local_cleanup(root));
old_chunk = getenv('NEUROPAL_IO_CHUNK_MIB');
old_space = getenv('NEUROPAL_IO_TEST_AVAILABLE_BYTES');
environment_cleanup = onCleanup(@() local_restore_environment(old_chunk, old_space));

setenv('NEUROPAL_IO_CHUNK_MIB', '1');
assert(DataHandling.Helpers.large_file.memory_budget_bytes() == 8 * 1024^2);
setenv('NEUROPAL_IO_CHUNK_MIB', '4096');
assert(DataHandling.Helpers.large_file.memory_budget_bytes() == 1024 * 1024^2);
setenv('NEUROPAL_IO_CHUNK_MIB', 'not-a-number');
assert(DataHandling.Helpers.large_file.memory_budget_bytes() == 128 * 1024^2);

source = fullfile(root, 'source.bin');
fid = fopen(source, 'w');
assert(fid >= 0);
file_cleanup = onCleanup(@() fclose(fid));
fwrite(fid, uint8(1:16), 'uint8');
clear file_cleanup
signature = DataHandling.Helpers.large_file.source_signature(source);
assert(signature.bytes == 16);
local_assert_error(@() DataHandling.Helpers.large_file.source_signature( ...
    fullfile(root, 'missing.bin')), 'DataHandling:LargeFile:MissingSource');

output = fullfile(root, 'output.mat');
setenv('NEUROPAL_IO_TEST_AVAILABLE_BYTES', '0');
local_assert_error(@() DataHandling.Helpers.large_file.assert_sufficient_disk_space( ...
    output, 1024), 'DataHandling:LargeFile:InsufficientDiskSpace');
setenv('NEUROPAL_IO_TEST_AVAILABLE_BYTES', num2str(512 * 1024^2, '%.0f'));
DataHandling.Helpers.large_file.assert_sufficient_disk_space(output, 1024);

partial = DataHandling.Helpers.large_file.partial_path(output);
assert(contains(partial, '.output.npal-partial.mat'));
fid = fopen(partial, 'w');
assert(fid >= 0);
fclose(fid);
fid = fopen(output, 'w');
assert(fid >= 0);
fclose(fid);
local_assert_error(@() DataHandling.Helpers.large_file.promote(partial, output), ...
    'DataHandling:LargeFile:FinalExists');

clear environment_cleanup cleanup
local_restore_environment(old_chunk, old_space);
local_cleanup(root);
fprintf('LARGE_FILE_POLICY=PASS\n');
end

function local_restore_environment(chunk_value, space_value)
setenv('NEUROPAL_IO_CHUNK_MIB', chunk_value);
setenv('NEUROPAL_IO_TEST_AVAILABLE_BYTES', space_value);
end

function local_assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), ...
        'Expected %s, received %s.', identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', 'Expected %s.', identifier);
end

function local_cleanup(root)
if exist(root, 'dir') == 7
    rmdir(root, 's');
end
end
