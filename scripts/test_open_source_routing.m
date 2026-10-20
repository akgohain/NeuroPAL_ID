function test_open_source_routing()
%TEST_OPEN_SOURCE_ROUTING Keep paired NeuroPAL and calcium sources selectable.
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder,'s'));
image = fullfile(folder,'image.nwb');
recording = fullfile(folder,'recording.nwb');
paired = fullfile(folder,'paired.nwb');
single_frame = fullfile(folder,'single-frame.nwb');
create_image(image); create_recording(recording,4);
create_image(paired); create_recording(paired,5);
create_recording(single_frame,4,1);

info = DataHandling.OpenSource.inspect(image);
assert(info.image && ~info.recording && ~Tracking.ReferenceWorkflow.supports(image));
assert(strcmp(DataHandling.OpenSource.resolve(image,'auto',@unexpected_choice),'image'));
info = DataHandling.OpenSource.inspect(recording);
assert(~info.image && info.recording && Tracking.ReferenceWorkflow.supports(recording));
assert(strcmp(DataHandling.OpenSource.resolve(recording,'auto',@unexpected_choice),'recording'));
assert(strcmp(DataHandling.OpenSource.resolve(single_frame,'auto',@unexpected_choice),'recording'));

info = DataHandling.OpenSource.inspect(paired);
assert(info.image && info.recording && Tracking.ReferenceWorkflow.supports(paired));
assert(strcmp(DataHandling.OpenSource.resolve(paired,'auto',@() 'NeuroPAL volume'),'image'));
assert(strcmp(DataHandling.OpenSource.resolve(paired,'auto',@() 'Calcium recording'),'recording'));
assert(strcmp(DataHandling.OpenSource.resolve(paired,'auto',@() 'Cancel'),'cancel'));
assert(strcmp(DataHandling.OpenSource.resolve(paired,'image',@unexpected_choice),'image'));
assert(strcmp(DataHandling.OpenSource.resolve(paired,'recording',@unexpected_choice),'recording'));
assert_error(@() DataHandling.OpenSource.resolve(paired), 'DataHandling:OpenSource:ChoiceRequired');
assert_error(@() DataHandling.OpenSource.resolve(paired,'auto',@() 'Other'), 'DataHandling:OpenSource:Choice');
assert_error(@() DataHandling.OpenSource.resolve(image,'recording'), 'DataHandling:OpenSource:NoRecording');
assert_error(@() DataHandling.OpenSource.resolve(recording,'image'), 'DataHandling:OpenSource:NoImage');
assert_error(@() DataHandling.OpenSource.resolve(paired,'unknown'), 'DataHandling:OpenSource:Route');

% Unrelated acquisitions and incomplete series cannot steal an image open.
h5create(image,'/acquisition/Unrelated/description',1);
h5writeatt(image,'/acquisition/Unrelated','neurodata_type','MultiChannelVolumeSeries');
assert(strcmp(DataHandling.OpenSource.resolve(image,'auto',@unexpected_choice),'image'));
assert(~Tracking.ReferenceWorkflow.supports(image));
h5create(image,'/acquisition/BadSeries/data',[3 4 2]);
h5writeatt(image,'/acquisition/BadSeries','neurodata_type','MultiChannelVolumeSeries');
assert(~Tracking.ReferenceWorkflow.supports(image));

% The Bedant H5 convention still opens the recording without a source dialog.
h5 = fullfile(folder,'recording.h5');
h5create(h5,'/data',[7 4 3 2 5],'Datatype','uint8');
assert(strcmp(DataHandling.OpenSource.resolve(h5,'auto',@unexpected_choice),'recording'));
assert(Tracking.ReferenceWorkflow.supports(h5));
static_h5 = fullfile(folder,'image.h5'); h5create(static_h5,'/data',[7 4 3 2]);
assert(strcmp(DataHandling.OpenSource.resolve(static_h5,'auto',@unexpected_choice),'image'));
for ext = {'.czi','.nd2','.tif','.mat'}
    path = fullfile(folder,['static' ext{1}]);
    assert(strcmp(DataHandling.OpenSource.resolve(path,'auto',@unexpected_choice),'image'));
    assert(~Tracking.ReferenceWorkflow.supports(path));
end

fprintf('OPEN_SOURCE_ROUTING=PASS\n');
end

function create_image(file)
h5create(file,'/acquisition/NeuroPALImageRaw/data',[7 6 5 4],'Datatype','uint16');
h5writeatt(file,'/acquisition/NeuroPALImageRaw','neurodata_type','MultiChannelVolume');
end

function create_recording(file, rank, frames)
if nargin < 3, frames = 3; end
dims = [frames 7 6 5];
if rank == 5, dims(5) = 2; end
h5create(file,'/acquisition/CalciumImageSeries/data',dims,'Datatype','uint16');
h5writeatt(file,'/acquisition/CalciumImageSeries','neurodata_type','MultiChannelVolumeSeries');
end

function answer = unexpected_choice()
error('DataHandling:OpenSource:UnexpectedDialog','An unambiguous source must not ask for a choice.');
answer = ''; %#ok<UNRCH>
end

function assert_error(action, identifier)
try
    action();
catch failure
    assert(strcmp(failure.identifier,identifier),'Unexpected error: %s',failure.identifier);
    return;
end
error('DataHandling:OpenSource:MissingError','Expected %s.',identifier);
end
