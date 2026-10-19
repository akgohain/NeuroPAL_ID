function test_main_detect_save(app)
%TEST_MAIN_DETECT_SAVE Share the versioned ID writer and preserve its recovery copy.
if nargin<1, app=Program.app; end
folder=tempname; mkdir(folder);
saved=struct('neurons',app.image_neurons,'id_file',app.id_file, ...
    'snapshot',getappdata(app.CELL_ID,'manual_id_file_snapshot'));
cleanup=onCleanup(@() restore(app,saved,folder));
app.image_neurons=Program.GUI.ManualIDService.copyImage(app.image_neurons);
app.id_file=fullfile(folder,'neurons_ID.mat');
sentinel='previous annotations'; auxiliary=struct('sample','preserved','revision',3);
save(app.id_file,'sentinel','auxiliary');
model=model_values(app.image_neurons);
Program.GUIHandling.save_auto_detect_id_state(app);
first=load(app.id_file);
Annotations.Store.validate(first.annotation_store);
assert(strcmp(first.sentinel,sentinel) && isequal(first.auxiliary,auxiliary));
assert(first.neurons.num_neurons()==app.image_neurons.num_neurons());
assert(first.mp_params.k==app.image_neurons.num_neurons());
assert(isequaln(model_values(first.neurons),model));
oldFingerprint=Annotations.Store.fingerprint(app.id_file);

% A later geometry save keeps the previous authoritative version, not a lone MAT file.
position=app.image_neurons.neurons(1).position;
app.image_neurons.neurons(1).position=position+[.25 0 0];
Program.GUIHandling.save_auto_detect_id_state(app);
current=load(app.id_file);
Annotations.Store.validate(current.annotation_store);
assert(current.annotation_store.generation>first.annotation_store.generation);
assert(isequaln(current.annotation_store.records,first.annotation_store.records));
assert(isequaln(current.annotation_store.evidence,first.annotation_store.evidence));
assert(isequaln(model_values(current.neurons),model));
assert(isequal(current.neurons.neurons(1).position,position+[.25 0 0]));
assert(strcmp(current.sentinel,sentinel) && isequal(current.auxiliary,auxiliary));
backup=[app.id_file '.lastgood.mat'];
assert(isfile(backup)); prior=load(backup);
Annotations.Store.validate(prior.annotation_store);
assert(isequaln(prior.annotation_store,first.annotation_store));
priorFingerprint=Annotations.Store.fingerprint(backup);
assert(strcmp(priorFingerprint.sha256,oldFingerprint.sha256));

% Invalid destinations fail before a partial file, lease or lineage is published.
authoritative=app.id_file; before=Annotations.Store.fingerprint(authoritative);
listing=dir(fullfile(folder,'*')); beforeFiles={listing.name};
app.id_file=folder;
try
    Program.GUIHandling.save_auto_detect_id_state(app);
    error('test:MissingError','A directory is not an ID file.');
catch ME
    assert(any(strcmp(ME.identifier,{'Program:GUIHandling:IDFile','Annotations:SavePath'})),ME.message);
end
listing=dir(fullfile(folder,'*')); assert(isequal(sort(beforeFiles),sort({listing.name})));
assert(isequaln(before,Annotations.Store.fingerprint(authoritative)));
assert(~isfile([folder '.annotations.lineage.json']) && ~isfile([folder '.annotations.lock']));
fprintf('MAIN_DETECT_ATOMIC_ID_SAVE=PASS\n');
end

function values=model_values(image)
values=struct('deterministic_id',{},'probabilistic_ids',{},'probabilistic_probs',{},'rank',{});
for i=1:numel(image.neurons)
    n=image.neurons(i);
    values(i)=struct('deterministic_id',{n.deterministic_id}, ...
        'probabilistic_ids',{n.probabilistic_ids},'probabilistic_probs',{n.probabilistic_probs},'rank',{n.rank});
end
end

function restore(app,saved,folder)
app.image_neurons=saved.neurons; app.id_file=saved.id_file;
setappdata(app.CELL_ID,'manual_id_file_snapshot',saved.snapshot);
if isfolder(folder), rmdir(folder,'s'); end
for path={[folder '.annotations.lineage.json'],[folder '.annotations.lock']}
    if isfile(path{1}), delete(path{1}); end
end
end
