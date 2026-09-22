function report = test_processing_operations(app, source, folder)
% Exercise image-processing callbacks and compare saved pixels with each preview.
assert(contains(folder, 'processing-format-audit'), 'Use a disposable processing fixture.');
if ~isfolder(folder), mkdir(folder); end
path = fullfile(folder, 'operation.mat');
copyfile(source, path);
Program.Routines.Processing.load_file('image', path);
original = app.image_data;
assert(~isempty(original), 'Use a materialized fixture for this operation suite.');
state=Program.Handlers.channels.processing_state(app);
assert(state.r.source_idx>0 && state.r.enabled, 'The imported image has no visible source channel.');
dims = size(original); dims(end+1:4) = 1;
scale = app.image_um_scale;
model = Neurons.Image([], 'scale', scale);
for point = [max(1,round(dims(1:3)/2)); 1 1 1]'
    neuron = Neurons.Neuron;
    neuron.position = point'; neuron.annotation = 'AVAL';
    neuron.color_readout = zeros(1,4);
    model.neurons(end+1) = neuron;
end
app.image_neurons = model;
app.mp_params.k = 2;
Program.ProcessingSession.capture(app);
report = struct('source',source,'dims',dims,'class',class(original),'passed',{{}});
operations = {'hori','vert','mirrorz','cc','acc','rotate','crop','ds','zscore','window','debleed'};
for i = 1:numel(operations)
    action = operations{i};
    Program.Routines.Processing.reset();
    app.proc_rot_spinner.Value = 90;
    app.ProcXYFactorEditField.Value = 1;
    app.ProcZSlicesEditField.Value = dims(3);
    app.flip_lr.Value = false; app.flip_ud.Value = false;
    mask = false(dims(1:2));
    y = 2:max(2,dims(1)-1); x = 3:max(3,dims(2)-2);
    mask(y,x) = true;
    app.rotation_stack.cache.Colormap = struct('mask',mask,'angle',0);
    expected_scale = scale;
    switch action
        case 'hori', expected = original(:,end:-1:1,:,:);
        case 'vert', expected = original(end:-1:1,:,:,:);
        case 'mirrorz', expected = original(:,:,end:-1:1,:);
        case 'cc', expected = rot90(original,-1); expected_scale(1:2)=scale([2 1]);
        case 'acc', expected = rot90(original,1); expected_scale(1:2)=scale([2 1]);
        case 'rotate', expected = imrotate(original,90); expected_scale(1:2)=scale([2 1]);
        case 'crop', expected = original(y,x,:,:);
        case 'ds'
            app.ProcXYFactorEditField.Value = 0.5;
            app.ProcZSlicesEditField.Value = max(1,ceil(dims(3)/2));
            xy = max(1,round(dims(1:2)*0.5));
            zs = Methods.ChunkyMethods.proc_target_slices(dims(3),app.ProcZSlicesEditField.Value);
            resized = imresize(original,xy);
            expected = resized(:,:,zs,:);
            expected_scale(1:2) = scale(1:2).*dims([2 1])./xy([2 1]);
            if numel(zs)>1, expected_scale(3)=scale(3)*(dims(3)-1)/(numel(zs)-1); end
        case 'zscore'
            setappdata(app.CELL_ID,'proc_normalize_background_percentile',0);
            setappdata(app.CELL_ID,'proc_normalize_max_percentile',100);
            expected = zeros(size(original),'like',original);
            for c = 1:dims(4)
                channel = double(original(:,:,:,c)); channel = channel-min(channel(:));
                if max(channel(:))>0, channel=channel/max(channel(:)); end
                if ~isfloat(original), channel=round(channel*double(intmax(class(original)))); end
                expected(:,:,:,c) = cast(channel,class(original));
            end
        case 'window'
            Program.GUIHandling.handle_processing_histogram_slider(app,'tl',[25 220],true,true);
            expected = original;
            selected = Program.Handlers.channels.processing_state(app).r.source_idx;
            if selected>0
                channel = original(:,:,:,selected);
                range = Program.Helpers.native_intensity_range(original);
                adjusted = max(0,min(1,((double(channel)-range(1))/diff(range)-25/255)/(195/255)));
                expected(:,:,:,selected) = cast(adjusted*diff(range)+range(1),class(original));
            end
        case 'debleed'
            cache = Methods.ChunkyMethods.spectral_cache_template();
            cache.coefficients = eye(3);
            app.spectral_cache = cache;
            expected = original;
    end
    assert(Program.Helpers.apply_processing_preview_action(app, action), action);
    difference = max(abs(double(app.image_data(:))-double(expected(:))));
    tolerance = double(~isfloat(original));
    if isfloat(original), tolerance=1e-6; end
    assert(isequal(size(app.image_data),size(expected)) && difference<=tolerance, ...
        'Unexpected pixels after %s (maximum difference %g).',action,difference);
    assert(strcmp(class(app.image_data),class(original)),action);
    assert(max(abs(app.image_um_scale-expected_scale))<1e-9,action);
    if strcmp(action,'crop'), assert(numel(app.image_neurons.neurons)==1); end
    preview = app.image_data;
    positions = app.image_neurons.get_positions();
    labels = app.image_neurons.get_annotations();
    assert(Program.Routines.Processing.save(),action);
    saved = load(app.image_file,'data','info');
    ids = load(app.id_file,'neurons');
    assert(isequal(saved.data,preview),['Save changed the preview for ' action]);
    assert(isequal(ids.neurons.get_positions(),positions));
    assert(isequal(ids.neurons.get_annotations(),labels));
    assert(isequal(saved.info.scale,app.image_um_scale));
    assert(~Program.ProcessingSession.dirty(app));
    assert(Program.Routines.Processing.save());
    assert(isequal(app.image_data,preview),['Repeated save changed ' action]);
    Program.Routines.Processing.load_file('image',app.image_file);
    assert(isequal(app.image_data,preview));
    report.passed{end+1}=action;
    fid=fopen(fullfile(folder,'progress.json'),'w');
    fprintf(fid,'%s',jsonencode(report)); fclose(fid);
    fprintf('OPERATION_PASS %s %s\n',source,action);
    % Restore the independent baseline for the next operation.
    copyfile(source,path);
    delete(app.id_file);
    app.image_data=[];
    Program.Routines.Processing.load_file('image',path);
    app.image_neurons=Program.ProcessingSession.copyNeurons(model);
    app.mp_params.k=2;
    Program.ProcessingSession.capture(app);
end

% Display settings must not bake gamma or channel remapping into the pixels.
app.tl_GammaEditField.Value = 0.6;
Program.GUIHandling.handle_processing_gamma_changed(app);
assert(isequal(app.image_data,original));
assert(Program.Routines.Processing.save());
saved=load(path,'data','prefs');
assert(isequal(saved.data,original) && saved.prefs.gamma(1)==0.6);
app.ProcShowMIPCheckBox.Value=true;
Program.GUIHandling.handle_processing_mip_toggled(app);
app.ProcShowMIPCheckBox.Value=false;
Program.GUIHandling.handle_processing_mip_toggled(app);
Program.GUIHandling.apply_percentile_threshold_measurement(app,90);
assert(Program.ProcessingSession.dirty(app));
Program.Routines.Processing.reset();
assert(isequal(app.image_data,original));
report.passed{end+1}='gamma_mip_percentile_discard';
fid=fopen(fullfile(folder,'result.json'),'w');
cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'%s',jsonencode(report));
fprintf('PROCESSING_OPERATIONS=PASS %s\n',source);
end
