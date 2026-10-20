function test_artifact_removal()
% Check projection layouts, channel validation and native-pixel normalization.
for nc=1:4
    data=reshape(uint16(1:9*11*4*nc),9,11,4,nc);
    projection=Methods.Preprocess.manual_artifact_projection(data,'YXZC');
    assert(isequal(size(projection),[9 11 3]) && isa(projection,'uint16'));
    expected=max(data,[],3);
    for c=1:min(nc,3), assert(isequal(projection(:,:,c),expected(:,:,1,c))); end
    if nc==1, assert(isequal(projection(:,:,1),projection(:,:,3))); end
    if nc==2, assert(~any(projection(:,:,3),'all')); end
    direct=Methods.Preprocess.manual_artifact_projection(reshape(expected,9,11,nc),'YXC');
    assert(isequal(projection,direct));
    mapping=nan(1,4); mapping(1:nc)=1:nc;
    app=struct('image_data',data,'image_prefs',struct('RGBW',mapping),'image_file','fixture.mat', ...
        'VolumeDropDown',struct('Value','Colormap'));
    context=Program.ArtifactRemoval.prepare(app,'manual');
    assert(isequal(context.channels,1:nc));
    if nc<3
        assert_error(@()Program.ArtifactRemoval.prepare(app,'automatic'),'NeuroPAL:ArtifactRGB');
    else
        context=Program.ArtifactRemoval.prepare(app,'automatic');
        assert(isequal(context.rgb,1:3));
    end
    changed=app; changed.image_data(1)=0;
    assert_error(@()Program.ArtifactRemoval.checkContext(changed,context),'NeuroPAL:ArtifactSourceChanged');
    changed=app; changed.VolumeDropDown.Value='Video';
    assert_error(@()Program.ArtifactRemoval.checkContext(changed,context),'NeuroPAL:ArtifactSourceChanged');
end
assert_error(@()Methods.Preprocess.manual_artifact_projection([]),'NeuroPAL:ArtifactImage');
assert_error(@()Methods.Preprocess.manual_artifact_projection(zeros(4,4,2,3),'YXC'),'NeuroPAL:ArtifactLayout');
assert_error(@()Methods.Preprocess.manual_artifact_projection(zeros(4,4,1,5)),'NeuroPAL:ArtifactChannels');
for nc=1:2
    assert_error(@()Methods.Preprocess.automatic_artifact_mask(ones(9,11,4,nc)), 'NeuroPAL:ArtifactRGB');
end
data=reshape(uint16(mod((1:21*23*5*4)*37,4093)),21,23,5,4);
mask=Methods.Preprocess.automatic_artifact_mask(data,[4 2 1]);
readout=Methods.ColorReadout(data,[4 2 1]); readout=readout.prepare();
normalized=zeros(21,23,5,3,'single');
for c=1:3
    selected=[4 2 1];
    normalized(:,:,:,c)=(single(data(:,:,:,selected(c)))-single(readout.Average(c)))/single(readout.Deviation(c));
end
[filtered,expected]=Methods.Preprocess.filter_gut_lysosomes(normalized);
assert(isequal(size(filtered),size(normalized)) && isequal(mask,expected) && islogical(mask));
assert(isequal(Methods.Preprocess.automatic_artifact_mask(data(:,:,:,1:3)), ...
    Methods.Preprocess.automatic_artifact_mask(data,1:3)));
assert(~any(Methods.Preprocess.automatic_artifact_mask(ones(9,11,4,3)),'all'));
assert(~any(Methods.Preprocess.automatic_artifact_mask(zeros(9,11,4,3)),'all'));
small=zeros(21,23,5,3,'uint16'); small(10,11,3,2)=1000;
small_mask=Methods.Preprocess.automatic_artifact_mask(small);
assert(any(small_mask,'all') && small_mask(10,11,3));
assert_error(@()Methods.Preprocess.automatic_artifact_mask(data,[1 1 2]),'NeuroPAL:ArtifactRGB');
assert_error(@()Methods.Preprocess.automatic_artifact_mask(data(:,:,1,:)),'NeuroPAL:ArtifactDepth');
bad=double(data); bad(1)=Inf;
assert_error(@()Methods.Preprocess.automatic_artifact_mask(bad),'NeuroPAL:ArtifactIntensity');
fprintf('ARTIFACT_LAYOUTS_CHANNELS_NATIVE_NORMALIZATION=PASS\n');
end

function assert_error(action,identifier)
try
    action(); error('test:MissingError','Expected %s.',identifier);
catch ME
    assert(strcmp(ME.identifier,identifier),'Expected %s; got %s: %s',identifier,ME.identifier,ME.message);
end
end
