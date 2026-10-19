function test_nwb_frame_reader()
%TEST_NWB_FRAME_READER Read single-channel NWB series without a channel axis.
folder=tempname; mkdir(folder);
cleanup=onCleanup(@() rmdir(folder,'s'));
shapes=[5 7 3; 1 7 3; 5 1 3; 5 7 1; 1 1 1];
for fixture=1:size(shapes,1)
    dims=shapes(fixture,:); frames=8;
    expected=reshape(uint16(1:prod(dims)*frames),[dims frames]);
    raw=permute(expected,[3 1 2 4]);
    file=fullfile(folder,sprintf('calcium-%d.nwb',fixture));
    dataPath='/acquisition/CalciumImageSeries/data';
    % MATLAB HDF5 dimensions reverse the stored NWB (T,X,Y,Z) dimensions.
    h5create(file,dataPath,[dims(3) dims(1) dims(2) frames],'Datatype','uint16');
    h5write(file,dataPath,raw);
    source=struct('file',file,'data_path',dataPath,'source_id',sprintf('nwb-%d',fixture), ...
        'ny',dims(1),'nx',dims(2),'nz',dims(3),'nc',1,'nt',frames, ...
        'dtype','uint16','axis_order','TXYZ');
    reader=Tracking.FrameReader(source);
    readerCleanup=onCleanup(@() delete(reader));
    assert(reader.Capacity==5 && strcmp(reader.Backend,'native'));
    for frame=[1 8 4 8]
        actual=reader.read(frame);
        shape=size(actual); shape(end+1:4)=1;
        assert(isequal(shape,[dims 1]));
        assert(isa(actual,'uint16') && isequal(actual,expected(:,:,:,frame)));
        assert(strcmp(reader.Backend,'native'),'An ordinary NWB fixture fell back to Python.');
    end
    assert(reader.Reads==3 && reader.Hits==1 && isequal(reader.Frames,[1 4 8]));

    % Invalid seeks neither enter the transport nor change the existing cache.
    previousFrames=reader.Frames; reads=reader.Reads; hits=reader.Hits;
    for invalid={[],[1 2],NaN,Inf,-1,0,1.5,frames+1}
        expect(@()reader.read(invalid{1}),'Tracking:Frame');
        assert(isequal(reader.Frames,previousFrames) && reader.Reads==reads && reader.Hits==hits);
        assert(strcmp(reader.Backend,'native'));
    end
    for frame=[2 3 5 6 7]
        assert(isequal(reader.read(frame),expected(:,:,:,frame)));
    end
    assert(reader.Reads==8 && isequal(reader.Frames,[2 3 5 6 7]));
    assert(isequal(reader.read(7),expected(:,:,:,7)) && reader.Hits==2);
    assert(isequal(reader.read(1),expected(:,:,:,1)) && reader.Reads==9);
    assert(isequal(reader.Frames,[3 5 6 7 1]) && numel(reader.Pixels)==reader.Capacity);
    clear readerCleanup
end
fprintf('NWB_SINGLE_CHANNEL_NATIVE_AXES_SINGLETONS_CACHE_FRAME_GUARDS=PASS\n');
end

function expect(action,identifier)
try
    action();
catch failure
    assert(strcmp(failure.identifier,identifier),failure.message);
    return
end
error('NeuroPAL:Test:ExpectedError','Expected %s.',identifier);
end
