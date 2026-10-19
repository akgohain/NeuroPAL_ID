function test_model_setup_failures()
%TEST_MODEL_SETUP_FAILURES Reject missing models before staging or mutation.

folder = tempname; mkdir(folder);
folder_cleanup = onCleanup(@() rmdir(folder, 's'));
missing = fullfile(folder, 'missing');
output = fullfile(folder, 'output');
volume = zeros(2,2,2,4,'uint8');
cases = {
    @() Wrapper.runMoECentroids(volume,[1 1 1],'BundlePath',missing,'OutputDir',output), 'Wrapper:MoEBundleUnavailable';
    @() Wrapper.runSpotiflowCentroids(volume,[1 1 1],'BundlePath',missing,'OutputDir',output), 'Wrapper:SpotiflowBundleUnavailable';
    @() Wrapper.runCRFID2AutoID([1 1 1],ones(1,4),[1 1 1],'BundlePath',missing,'OutputDir',output), 'Wrapper:CRFID2BundleUnavailable';
    @() Wrapper.runYoloCentroids(volume,[1 1 1],'WeightsPath',missing,'OutputDir',output), 'Wrapper:MissingYoloWeights';
    @() Wrapper.runCellposeCentroids(volume,[1 1 1],'ModelPath',missing,'OutputDir',output), 'Wrapper:MissingCellposeModel';
    @() Wrapper.runTransformerAutoIDFromVolume(volume,[1 1 1],[1 1 1],'CheckpointPath',missing,'OutputDir',output), 'Wrapper:MissingTransformerCheckpoint'
};
for i = 1:size(cases,1)
    expect(cases{i,1}, cases{i,2});
    assert(~isfolder(output), 'Missing models must not stage an image.');
    Program.HeavyJob.assertIdle();
end

% A directory must contain the exact checkpoint selected by the Python loader.
run_dir = fullfile(folder, 'run'); mkdir(run_dir);
repo = fullfile(folder, 'repo'); mkdir(repo);
write(fullfile(repo, 'run_app_volume_inference.py'), '# fixture');
write(fullfile(repo, 'run_inference.py'), '# fixture');
input = fullfile(folder, 'input.nwb'); write(input, 'fixture');
for alternate = [false true]
    if alternate, write(fullfile(run_dir, 'last_model.pt'), 'fixture'); end
    expect(@() Wrapper.runTransformerAutoIDFromVolume(volume,[1 1 1],[1 1 1], ...
        'RepoDir',repo,'CheckpointPath',run_dir,'OutputDir',output), 'Wrapper:MissingTransformerWeights');
    expect(@() Wrapper.runTransformerAutoID(input,'RepoDir',repo,'CheckpointPath',run_dir), ...
        'Wrapper:MissingTransformerWeights');
    assert(~isfolder(output));
    Program.HeavyJob.assertIdle();
end
weights = fullfile(run_dir, 'best_model.pt');
write(weights, '');
expect(@() Methods.ModelSetup.transformer(repo,run_dir), 'Wrapper:MissingTransformerWeights');
write(weights, 'fixture');
expect(@() Methods.ModelSetup.transformer(repo,run_dir), 'Wrapper:MissingTransformerConfig');
config = fullfile(run_dir, 'train_config.json'); write(config, 'invalid');
expect(@() Methods.ModelSetup.transformer(repo,run_dir), 'Wrapper:InvalidTransformerConfig');
write(config, '{}');
Methods.ModelSetup.transformer(repo,run_dir);
Methods.ModelSetup.transformer(repo,fullfile(run_dir,'last_model.pt'));
expect(@() Methods.ModelSetup.transformer(missing,run_dir), 'Wrapper:MissingTransformerRepo');

% Each bundle reports the absent artifact instead of entering its adapter.
for method = {'detection_moe', 'spotiflow_supervised', 'crf_cellid_2'}
    manifest = struct('schema_version',1,'method_id',method{1},'display_name','Fixture', ...
        'configuration',struct(),'artifacts',struct('role','weights','path','missing.pt','required',true));
    write(fullfile(folder,'method_bundle.json'),jsonencode(manifest));
    readiness = Methods.MethodBundle.inspect(method{1},folder);
    assert(~readiness.ready && contains(readiness.summary,'missing.pt'));
end
write(fullfile(folder,'method_bundle.json'),'{');
assert(~Methods.MethodBundle.inspect('detection_moe',folder).ready);

% Explicit Cellpose paths never silently fall back to another local model.
old_model = getenv('NEUROPAL_CELLPOSE_MODEL');
model_cleanup = onCleanup(@() setenv('NEUROPAL_CELLPOSE_MODEL',old_model));
setenv('NEUROPAL_CELLPOSE_MODEL',weights);
expect(@() Methods.ModelSetup.cellpose(missing),'Wrapper:MissingCellposeModel');
assert(strcmp(Methods.ModelSetup.cellpose(''),weights));
setenv('NEUROPAL_CELLPOSE_MODEL',missing);
expect(@() Methods.ModelSetup.cellpose(''),'Wrapper:MissingCellposeModel');
old_download = getenv('NEUROPAL_CELLPOSE_ALLOW_DOWNLOAD');
download_cleanup = onCleanup(@() setenv('NEUROPAL_CELLPOSE_ALLOW_DOWNLOAD',old_download));
setenv('NEUROPAL_CELLPOSE_ALLOW_DOWNLOAD','0');
expect(@() Methods.ModelSetup.cellpose('cyto'),'Wrapper:MissingCellposeModel');
Methods.ModelSetup.detection('cellpose',struct('mode','stub','model_path',missing));

% Failed auto-ID must leave both manual and model IDs unchanged.
neurons = Neurons.Image([], 'Head');
neuron = Neurons.Neuron(); neuron.annotation = 'AVAL';
neuron.deterministic_id = 'AVAR'; neuron.probabilistic_ids = {'AVAR'};
neuron.probabilistic_probs = 0.9; neurons.neurons(1) = neuron;
app = struct('image_neurons',neurons,'selected_neuron',1);
snapshot = Methods.TransformerAutoId.captureModelIDs(neurons);
expect(@() Methods.TransformerAutoId.run(app,'CheckpointPath',missing), 'Wrapper:MissingTransformerCheckpoint');
expect(@() Methods.CRFCellID2.run(app,'BundlePath',missing), 'Wrapper:CRFID2BundleUnavailable');
assert(strcmp(neurons.neurons(1).annotation,'AVAL'));
assert(isequaln(snapshot,Methods.TransformerAutoId.captureModelIDs(neurons)));
assert(app.selected_neuron == 1);

% Detection preflight runs before the overwrite prompt and selection changes.
fig = uifigure('Visible','off');
figure_cleanup = onCleanup(@() delete(fig));
app.CELL_ID = fig; app.image_data = volume;
for method = {'cellpose','yolo','spotiflow_supervised','detection_moe'}
    setappdata(fig,'main_detect_params',struct('model_path',missing,'weights_path',missing,'bundle_path',missing));
    switch method{1}
        case 'cellpose', identifier = 'Wrapper:MissingCellposeModel';
        case 'yolo', identifier = 'Wrapper:MissingYoloWeights';
        case 'spotiflow_supervised', identifier = 'Wrapper:SpotiflowBundleUnavailable';
        otherwise, identifier = 'Wrapper:MoEBundleUnavailable';
    end
    expect(@() Program.GUIHandling.run_modern_auto_detector(app,method{1}),identifier);
    assert(isequaln(snapshot,Methods.TransformerAutoId.captureModelIDs(neurons)));
    assert(strcmp(neurons.neurons(1).annotation,'AVAL') && app.selected_neuron == 1);
    Program.HeavyJob.assertIdle();
end

% Check the legacy model loader without loading the large distributed network.
old_path = path; old_folder = pwd;
path_cleanup = onCleanup(@() restore(old_path,old_folder));
root = fileparts(fileparts(mfilename('fullpath'))); addpath(root);
cd(folder);
write('NN_model.mat','');
expect(@() Methods.NNDetect(),'Methods:NNDetect:MissingModel');
write('NN_model.mat','invalid');
expect(@() Methods.NNDetect(),'Methods:NNDetect:InvalidModel');
version = 1; save('NN_model.mat','version');
expect(@() Methods.NNDetect(),'Methods:NNDetect:InvalidModel');
model=struct('Layers',1); save('NN_model.mat','version','model');
expect(@() Methods.NNDetect(),'Methods:NNDetect:InvalidModel');
expect(@() Methods.NNDetect.validateModel(model),'Methods:NNDetect:InvalidModel');
message=Program.GUIHandling.method_error_message(MException( ...
    'Methods:NNDetect:MissingDependency','The Keras output layer is unavailable.'));
assert(contains(message,'Converter for TensorFlow Models') && contains(message,'MATLAB path') && contains(message,'Matching Pursuit'));
clear path_cleanup
Program.HeavyJob.assertIdle();
fprintf('MODEL_SETUP_FAILURES=PASS\n');
end

function expect(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier,identifier), 'Expected %s, received %s: %s', identifier,ME.identifier,ME.message);
    message = Program.GUIHandling.method_error_message(ME);
    assert(contains(message,'Settings') || contains(message,'MATLAB path') || contains(message,'NEUROPAL_GAT_REPO'));
    assert(~contains(message,'Error in '), 'Setup alerts must not expose stack frames.');
    return
end
error('NeuroPAL:Test:ExpectedError','Expected %s.',identifier);
end

function write(file, text)
fid = fopen(file,'w'); assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid,text,'char');
end

function restore(old_path, old_folder)
cd(old_folder); path(old_path);
end
