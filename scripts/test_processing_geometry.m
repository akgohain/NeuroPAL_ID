function test_processing_geometry(app)
% Compare transformed centers with transformed image landmarks.
data=zeros(9,13,5,4,'uint8');
point=[3,9,3]; data(point(1),point(2),point(3),1)=255;
neurons=Neurons.Image([]); n=Neurons.Neuron; n.position=point; n.annotation='AVAL';
n.color_readout=zeros(1,4); neurons.neurons=n;
for action={'hori','vert','mirrorz','cc','acc','rotate','crop','ds'}
    app.proc_rot_spinner.Value=90;
    app.ProcXYFactorEditField.Value=0.5;
    app.ProcZSlicesEditField.Value=5;
    mask=false(9,13); mask(2:8,4:12)=true;
    app.rotation_stack.cache.Colormap=struct('mask',mask,'angle',0);
    image=Methods.ChunkyMethods.apply_vol(app,action{1},data);
    dims=size(image); dims(end+1:4)=1;
    model=Program.ProcessingSession.copyNeurons(neurons);
    model=Program.Helpers.transform_processing_neurons(app,model,action{1},size(data),dims);
    [~,peak]=max(reshape(image(:,:,:,1),[],1));
    [y,x,z]=ind2sub(dims(1:3),peak);
    assert(max(abs(model.neurons(1).position-[y x z]))<=0.5,action{1});
    assert(strcmp(model.neurons(1).annotation,'AVAL'));
end
% A crop excludes only centers outside the retained region.
mask=false(9,13); mask(1:4,1:4)=true;
app.rotation_stack.cache.Colormap=struct('mask',mask,'angle',0);
model=Program.Helpers.transform_processing_neurons(app,neurons,'crop',size(data),[4 4 5 4]);
assert(isempty(model.neurons));
original_scale=app.image_um_scale;
app.image_um_scale=[0.3 0.3 1.5];
app.proc_rot_spinner.Value=45;
scale=Program.Helpers.update_processing_image_scale(app,{'rotate'},size(data),false);
assert(max(abs(scale-[0.3 0.3 1.5]))<1e-12);
app.image_um_scale=original_scale;
fprintf('PROCESSING_GEOMETRY=PASS\n');
end
