function test_import_memory()
%TEST_IMPORT_MEMORY Verify import admission and plane-wise pixel assembly.
previous = getenv('NEUROPAL_IMAGE_MAX_MIB');
environment_cleanup = onCleanup(@() setenv('NEUROPAL_IMAGE_MAX_MIB', previous));
addpath(fullfile(pwd, 'External_Dependencies', 'bfmatlab'));

assert(bfCheckJavaPath(true));

% A reader exposes dimensions before any pixel plane is requested.
reader = javaObject('loci.formats.ImageReader');
reader.setId('fixture&sizeX=9&sizeY=7&sizeZ=3&sizeC=4&sizeT=1&pixelType=uint16.fake');
reader_cleanup = onCleanup(@() reader.close());
setenv('NEUROPAL_IMAGE_MAX_MIB', '0.0001');
try
    DataHandling.Helpers.bioformats_image.read(reader, 'fixture');
    error('Test:MissingError', 'Expected admission rejection.');
catch ME
    assert(strcmp(ME.identifier, 'DataHandling:NeuroPALImage:MaterializationLimit'));
end
setenv('NEUROPAL_IMAGE_MAX_MIB', '512');
actual = DataHandling.Helpers.bioformats_image.read(reader, 'fixture');
assert(isequal(size(actual), [9 7 3 4]));
for c = 1:4
    for z = 1:3
        expected = bfGetPlane(reader, reader.getIndex(z-1, c-1, 0)+1)';
        assert(isequal(actual(:,:,z,c), uint16(expected)));
    end
end
[opened, opened_cleanup, metadata] = DataHandling.Helpers.bioformats_image.open( ...
    'fixture&sizeX=9&sizeY=7&sizeZ=3&sizeC=4&sizeT=1&pixelType=uint16.fake');
assert(isa(metadata, 'java.util.Hashtable'));
assert(isequal(DataHandling.Helpers.bioformats_image.read(opened, 'fixture'), actual));
clear opened_cleanup
assert(isempty(opened.getCurrentFile()));
reader.close();
reader.setId('fixture&sizeX=9&sizeY=7&sizeZ=3&sizeC=4&sizeT=2.fake');
try
    DataHandling.Helpers.bioformats_image.read(reader, 'fixture');
    error('Test:MissingError', 'Expected time-series rejection.');
catch ME
    assert(strcmp(ME.identifier, 'DataHandling:Import:UnsupportedLayout'));
end

% CZI import must honor the image admission setting.
fixture = '/Users/adamg/neuroPAL/artifacts/performance-sweep/czi-app/input.czi';
if isfile(fixture)
    setenv('NEUROPAL_IMAGE_MAX_MIB', '0.01');
    try
        DataHandling.imreadCZI(fixture);
        error('Test:MissingError', 'Expected CZI admission rejection.');
    catch ME
        assert(contains(ME.message, 'loading limit'));
    end
end
fprintf('IMPORT_MEMORY=PASS\n');
end
