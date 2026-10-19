function test_annotation_recovery()
%TEST_ANNOTATION_RECOVERY Require explicit choices and stable owner correspondence.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
folder=tempname; mkdir(folder); cleanup=onCleanup(@() rmdir(folder,'s'));
path=fullfile(folder,'image_ID.mat'); image=fixture();
[store,ids]=Annotations.Store.create(image.neurons,struct('source_id','recovery-source','sex','XX'));
for i=1:numel(ids), image.neurons(i).annotation_id=ids{i}; end
store=Annotations.Store.command(store,ids{1},Annotations.Catalog.parse('ALA','XX'),'assign');
apply(image,store);
payload=struct('neurons',image,'annotation_store',store,'version',Program.ProgramInfo.version, ...
    'mp_params',struct('k',2),'sentinel','preserve unrelated metadata');
[payload,fp]=Annotations.Store.save(path,payload,Annotations.Store.fingerprint(path));
apply(image,payload.annotation_store);
payload.annotation_store=Annotations.Store.command(payload.annotation_store,ids{2},Annotations.Catalog.parse('AVAL','XX'),'assign');
payload.neurons=copyImage(image); apply(payload.neurons,payload.annotation_store);
[payload,fp]=Annotations.Store.save(path,payload,fp); apply(image,payload.annotation_store);

% An external legacy edit conflicts with the typed store; neither wins silently.
external=load(path); external.neurons.neurons(1).annotation='AVAR';
builtin('save',path,'-struct','external','-v7.3');
original=Annotations.Store.fingerprint(path); previous=Annotations.Store.fingerprint([path '.lastgood.mat']);
report=Annotations.Recovery.inspect(path,image);
assert(~report.blocked && any(strcmp({report.candidates.id},'current-structured')) && ...
    any(strcmp({report.candidates.id},'current-legacy')));
prepared=Annotations.Recovery.prepare(report,'current-structured',image);
assert(strcmp(Annotations.Store.occupant(prepared.payload.annotation_store,'ALA'),ids{1}));
[saved,~,retained]=Annotations.Recovery.publish(prepared);
assert(numel(retained)==2);
one=Annotations.Store.fingerprint(retained{1}); two=Annotations.Store.fingerprint(retained{2});
assert(strcmp(one.sha256,original.sha256) && strcmp(two.sha256,previous.sha256));
assert(strcmp(saved.sentinel,'preserve unrelated metadata'));
assert(isequal(image.neurons(1).probabilistic_probs,[0.7 0.3]));

% Erased typed state is recoverable only when the writer retained owner UUIDs.
external=load(path); external=rmfield(external,'annotation_store');
external.neurons.annotation_store=struct(); external.neurons.neurons(1).annotation='AVAR';
builtin('save',path,'-struct','external','-v7.3');
erased_original=Annotations.Store.fingerprint(path);
report=Annotations.Recovery.inspect(path,image);
assert(~report.blocked);
prepared=Annotations.Recovery.prepare(report,'current-legacy',image);
assert(strcmp(Annotations.Store.occupant(prepared.payload.annotation_store,'AVAR'),ids{1}));
[saved,~,retained]=Annotations.Recovery.publish(prepared);
copy=Annotations.Store.fingerprint(retained{1}); assert(strcmp(copy.sha256,erased_original.sha256));
assert(strcmp(Annotations.Store.occupant(saved.annotation_store,'AVAR'),ids{1}));

regenerated=fixture();
[fresh,fresh_ids]=Annotations.Store.create(regenerated.neurons,struct('source_id','regenerated-source','sex','XX'));
for i=1:numel(fresh_ids), regenerated.neurons(i).annotation_id=fresh_ids{i}; end
apply(regenerated,fresh);
rejected=Annotations.Recovery.inspect(path,regenerated);
assert(rejected.blocked);
expect(@() Annotations.Recovery.prepare(rejected,'lastgood',regenerated),'Annotations:RecoveryBlocked');

% An unreadable current file can use an explicitly selected valid last-good
% save, but only after retaining its original bytes under a different path.
corrupt_path=fullfile(folder,'corrupt_ID.mat');
backup_path=[corrupt_path '.lastgood.mat'];
[ok,message]=copyfile(path,backup_path); assert(ok,message);
backup_fingerprint=Annotations.Store.fingerprint(backup_path);
good=load(backup_path); Annotations.Store.validate(good.annotation_store);
fid=fopen(corrupt_path,'w'); assert(fid>=0);
fwrite(fid,uint8([0 255 17 0 255 83 0 1]),'uint8'); fclose(fid);
corrupt_fingerprint=Annotations.Store.fingerprint(corrupt_path);
expect(@() Annotations.Store.save(corrupt_path,good,corrupt_fingerprint),'Annotations:RecoverySave');
expect(@() Annotations.Store.save(corrupt_path,good,corrupt_fingerprint, ...
    struct('validated_recovery_original',true)),'Annotations:RecoverySave');
expect(@() Annotations.Store.save(corrupt_path,good,corrupt_fingerprint, ...
    struct('validated_recovery_original',corrupt_path)),'Annotations:RecoverySave');
expect(@() Annotations.Store.save(corrupt_path,good,corrupt_fingerprint, ...
    struct('validated_recovery_original',backup_path)),'Annotations:RecoverySave');
assert(isequaln(Annotations.Store.fingerprint(corrupt_path),corrupt_fingerprint));
assert(isequaln(Annotations.Store.fingerprint(backup_path),backup_fingerprint));
rejected=Annotations.Recovery.inspect(corrupt_path,regenerated); assert(rejected.blocked);
expect(@() Annotations.Recovery.prepare(rejected,'lastgood',regenerated),'Annotations:RecoveryBlocked');
report=Annotations.Recovery.inspect(corrupt_path,image);
assert(~report.blocked && isequal({report.candidates.id},{'lastgood'}));
prepared=Annotations.Recovery.prepare(report,'lastgood',image);
[saved,~,retained]=Annotations.Recovery.publish(prepared);
assert(numel(retained)==2);
raw_retained=Annotations.Store.fingerprint(retained{1});
assert(strcmp(raw_retained.sha256,corrupt_fingerprint.sha256));
assert(isequaln(Annotations.Store.fingerprint(backup_path),backup_fingerprint));
backup=load(backup_path); Annotations.Store.validate(backup.annotation_store);
[recovered,~,issues]=Annotations.Store.loadValidated(corrupt_path);
assert(isempty(issues) && isequaln(recovered.annotation_store,saved.annotation_store));
assert(all(ismember(ids,{recovered.annotation_store.owners.owner_id})));

% A captured selection cannot publish over a newer writer.
report=Annotations.Recovery.inspect(path,image);
external=load(path); external.sentinel='changed while inspection was open';
builtin('save',path,'-struct','external','-v7.3');
after_external=Annotations.Store.fingerprint(path);
expect(@() Annotations.Recovery.prepare(report,'current-structured',image),'Annotations:StaleRecovery');
assert(isequaln(Annotations.Store.fingerprint(path),after_external));
report=Annotations.Recovery.inspect(path,image);
prepared=Annotations.Recovery.prepare(report,'current-structured',image);
external.sentinel='changed while prepared choice was open';
builtin('save',path,'-struct','external','-v7.3');
after_external=Annotations.Store.fingerprint(path);
before_files=dir(folder);
expect(@() Annotations.Recovery.publish(prepared),'Annotations:StaleRecovery');
after_files=dir(folder);
assert(isequal(sort({before_files.name}),sort({after_files.name})));
assert(isequaln(Annotations.Store.fingerprint(path),after_external));

pending=[path '.processing.pending.json']; fid=fopen(pending,'w'); fwrite(fid,'{}'); fclose(fid);
blocked=Annotations.Recovery.inspect(path,image); assert(blocked.blocked);
expect(@() Annotations.Recovery.prepare(report,'current-structured',image),'Annotations:RecoveryBlocked');
expect(@() Annotations.Recovery.publish(prepared),'Annotations:RecoveryBlocked');
assert(isequaln(Annotations.Store.fingerprint(path),after_external));

fprintf('ANNOTATION_RECOVERY_EXPLICIT_OWNER_CORRESPONDENCE_HISTORY_STALE_PAIR=PASS\n');
end

function image=fixture()
image=Neurons.Image([]);
for i=1:2
    n=Neurons.Neuron; n.position=[10*i 20 3]; n.deterministic_id='AVA';
    n.probabilistic_ids={'AVA','AVB'}; n.probabilistic_probs=[0.7 0.3]; n.rank=i;
    image.neurons(i)=n;
end
end

function apply(image,store)
projection=Annotations.Store.project(store,image.neurons);
for i=1:numel(projection)
    p=projection(i); n=image.neurons(i);
    n.annotation=p.annotation; n.annotation_confidence=p.annotation_confidence;
    n.is_annotation_on=p.is_annotation_on; n.is_emphasized=p.is_emphasized;
    n.annotation_record=p.annotation_record;
end
image.annotation_store=store;
end

function copy=copyImage(image)
copy=Neurons.Image([]); copy.scale=image.scale; copy.annotation_store=image.annotation_store;
for i=1:numel(image.neurons)
    n=Neurons.Neuron; fields=properties(n);
    for j=1:numel(fields), n.(fields{j})=image.neurons(i).(fields{j}); end
    copy.neurons(i)=n;
end
end

function expect(callback,identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier,identifier),'Expected %s, got %s: %s',identifier,ME.identifier,ME.message);
    return;
end
error('Annotations:TestExpectedError','Expected %s.',identifier);
end
