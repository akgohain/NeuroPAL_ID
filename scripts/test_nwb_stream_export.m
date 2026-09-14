function test_nwb_stream_export()
%TEST_NWB_STREAM_EXPORT Verify bounded output writes and transactional failures.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
dims = [4 5 3 2 7];
input = reshape(uint16(1:prod(dims)), dims);
reads = 0;
source = struct('path', '/acquisition/Fixture/data', 'dims', dims, ...
    'read_plane', @read_fixture);
output = fullfile(root, 'movie.nwb');
nwb = make_nwb(source);
assert(isempty(nwb.acquisition.get('Fixture').data.internal.data));
DataHandling.Helpers.nwb_stream_export.write(nwb, output, {source});
assert(isequal(h5read(output, source.path), input));
assert(reads == 1 + prod(dims(3:5)));
assert(isempty(dir(fullfile(root, '.*.npal-partial*'))));
notes = string(h5read(output, '/general/notes'));
assert(contains(notes, '"source_dtype":"uint16"'));

% Previously bound datasets must be copied into a new destination on merge.
copy_output = fullfile(root, 'copied.nwb');
reopened = nwbRead(output);
DataHandling.Helpers.nwb_stream_export.write(reopened, copy_output, {});
assert(isequal(h5read(copy_output, source.path), input));
assert(isequal(h5read(copy_output, '/processing/Annotations/Values/value'), uint16([10; 20; 30])));

% Refuse existing destinations before reading or changing the source/output.
before = reads;
assert_error(@() DataHandling.Helpers.nwb_stream_export.write( ...
    make_nwb(source), output, {source}), 'DataHandling:NWBExport:FinalExists');
assert(reads == before);
assert(isequal(h5read(output, source.path), input));

% Cancellation and read failures must never publish a partial movie.
reads = 0;
cancelled_output = fullfile(root, 'cancelled.nwb');
assert_error(@() DataHandling.Helpers.nwb_stream_export.write( ...
    make_nwb(source), cancelled_output, {source}, [], 'CancelFcn', @cancel_after_reads), ...
    'DataHandling:NWBExport:Cancelled');
assert(~isfile(cancelled_output));
assert(isempty(dir(fullfile(root, '.*.npal-partial*'))));
bad_source = source;
bad_source.read_plane = @(t, z, c) nan(dims(1:2));
assert_error(@() DataHandling.Helpers.nwb_stream_export.write( ...
    make_nwb(bad_source), fullfile(root, 'invalid.nwb'), {bad_source}), ...
    'DataHandling:NWBExport:InvalidPlane');
assert(~isfile(fullfile(root, 'invalid.nwb')));
assert(isempty(dir(fullfile(root, '.*.npal-partial*'))));

% One global floating-point scale is used across all planes and timepoints.
float_input = single(input) / 100;
float_source = source;
float_source.read_plane = @(t, z, c) float_input(:, :, z, c, t);
float_output = fullfile(root, 'float.nwb');
DataHandling.Helpers.nwb_stream_export.write(make_nwb(float_source), float_output, {float_source});
low = double(min(float_input, [], 'all'));
high = double(max(float_input, [], 'all'));
expected = uint16(round((double(float_input) - low) / (high - low) * 65535));
assert(isequal(h5read(float_output, source.path), expected));
notes = string(h5read(float_output, '/general/notes'));
record = jsondecode(extractAfter(notes, 'NeuroPAL_ID pixel export: '));
assert(record.source_min == low);
assert(record.source_max == high);

% A uint8 image preserves pixel values and singleton axes under uint16 schema.
image = reshape(uint8(1:20), 4, 5);
image_source = DataHandling.Helpers.nwb_stream_export.image_source(image);
image_source.path = source.path;
image_output = fullfile(root, 'image.nwb');
DataHandling.Helpers.nwb_stream_export.write(make_nwb(image_source), image_output, {image_source});
assert(isequal(h5read(image_output, source.path), uint16(image)));
info = h5info(image_output, source.path);
assert(isequal(info.Dataspace.Size, [4 5 1 1]));

% Integer overflow is an error, not a saturating conversion.
bad_source.read_plane = @(t, z, c) repmat(uint32(70000), dims(1:2));
assert_error(@() DataHandling.Helpers.nwb_stream_export.write( ...
    make_nwb(bad_source), fullfile(root, 'overflow.nwb'), {bad_source}), ...
    'DataHandling:NWBExport:OutOfRange');
assert(~isfile(fullfile(root, 'overflow.nwb')));
assert_error(@() DataHandling.Helpers.nwb_stream_export.image_source( ...
    zeros(2, 2, 2, 2, 2, 'uint8')), 'DataHandling:NWBExport:ImageDimensions');

% A source modified externally during streaming must not produce an output.
source_stamp = fullfile(root, 'source-stamp.bin');
fid = fopen(source_stamp, 'w');
fwrite(fid, uint8(1));
fclose(fid);
source_modified = false;
changed_source = source;
changed_source.source_file = source_stamp;
changed_source.source_signature = DataHandling.Helpers.large_file.source_signature(source_stamp);
changed_source.read_plane = @read_changed_fixture;
changed_output = fullfile(root, 'changed.nwb');
assert_error(@() DataHandling.Helpers.nwb_stream_export.write( ...
    make_nwb(changed_source), changed_output, {changed_source}), ...
    'DataHandling:NWBExport:SourceChanged');
assert(~isfile(changed_output));
assert(isempty(dir(fullfile(root, '.*.npal-partial*'))));
fprintf('NWB_STREAM_EXPORT=PASS\n');

    function plane = read_fixture(t, z, c)
        % Input is requested only after the hidden NWB output exists.
        assert(~isempty(dir(fullfile(root, '.*.npal-partial*'))));
        reads = reads + 1;
        plane = input(:, :, z, c, t);
    end

    function cancelled = cancel_after_reads()
        cancelled = reads >= 5;
    end

    function plane = read_changed_fixture(t, z, c)
        plane = read_fixture(t, z, c);
        if ~source_modified
            fid = fopen(source_stamp, 'a');
            fwrite(fid, uint8(2));
            fclose(fid);
            source_modified = true;
        end
    end
end

function nwb = make_nwb(source)
nwb = NwbFile('session_description', 'NWB streaming export fixture', ...
    'identifier', 'stream-test', 'session_start_time', datetime(2026, 1, 1, 'TimeZone', 'UTC'));
pipe = DataHandling.Helpers.nwb_stream_export.make_pipe(source.dims);
series = types.core.TimeSeries('data', pipe, 'data_unit', 'a.u.', ...
    'starting_time', 0, 'starting_time_rate', 1);
nwb.acquisition.set('Fixture', series);
column_pipe = types.untyped.DataPipe('data', uint16([10; 20; 30]), ...
    'maxSize', 3, 'axis', 1, 'chunkSize', 3);
column = types.hdmf_common.VectorData('description', 'Annotation values', 'data', column_pipe);
table = types.hdmf_common.DynamicTable('description', 'Annotations fixture', ...
    'colnames', {'value'}, 'id', types.hdmf_common.ElementIdentifiers('data', int64((0:2)')), ...
    'value', column);
module = types.core.ProcessingModule('description', 'Annotation fixture');
module.dynamictable.set('Values', table);
nwb.processing.set('Annotations', module);
end

function assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), 'Expected %s; received %s.', identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', 'Expected %s.', identifier);
end
