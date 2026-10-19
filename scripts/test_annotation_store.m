function test_annotation_store()
%TEST_ANNOTATION_STORE Preserve evidence through explicit identity transactions.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
base=struct('annotation_id','','annotation','','annotation_confidence',-1, ...
    'is_annotation_on',NaN,'is_emphasized',false,'deterministic_id','AVA', ...
    'probabilistic_ids',{{'AVA','AVB'}},'probabilistic_probs',[0.7 0.3],'rank',1);
neurons=repmat(base,1,4);
context=struct('source_id','annotation-store-test','specimen_id','specimen-test','sex','XX');
[store,owners]=Annotations.Store.create(neurons,context);
evidence=store.evidence;
assert(~store.constraints_enabled && isempty(Annotations.Store.constraints(store,'crf')));

% Tentative labels remain hypotheses, including multiple claims of one name.
tentative=Annotations.Catalog.parse('AVAL?','XX');
[a,event]=Annotations.Store.command(store,owners{1},tentative,'assign');
assert(event.changed && ~Annotations.Store.confirmed(Annotations.Store.record(a,owners{1})));
a=Annotations.Store.command(a,owners{2},tentative,'assign');
projection=Annotations.Store.project(a);
assert(isempty(projection(1).annotation) && projection(1).lossy);
assert(isequaln(a.evidence,evidence));
assert(isequal(neurons(1).probabilistic_probs,[0.7 0.3]));
with_annotation=Annotations.Store.command(store,owners{1},Annotations.Catalog.parse('ALA','XX'),'assign');
[with_inference,evidence_id]=Annotations.Store.captureEvidence(with_annotation,owners{1}, ...
    struct('classes',{{'ALA','AVA'}},'scores',[0.8 0.2]),struct('model','test-model','bundle','test-v1'));
after_undo=Annotations.Store.undo(with_inference);
restored_record=Annotations.Store.record(after_undo,owners{1});
assert(strcmp(restored_record.kind,'unassigned') && any(strcmp(restored_record.model_evidence_ids,evidence_id)));
unavailable=store; unavailable.records(1).model_evidence_ids{end+1}='unavailable-original-evidence';
unavailable=Annotations.Store.command(unavailable,owners{1},Annotations.Catalog.parse('ALA','XX'),'assign');
assert(any(strcmp(Annotations.Store.missingEvidence(unavailable),'unavailable-original-evidence')));

% Unknown sex uses catalog applicability, and a saved exception is not erased.
unknown_context=struct('source_id','unknown-sex-test');
[unknown,unknown_owners]=Annotations.Store.create(neurons,unknown_context);
unknown=Annotations.Store.command(unknown,unknown_owners{1},Annotations.Catalog.parse('CEMDL',''),'assign');
assert(Annotations.Store.confirmed(Annotations.Store.record(unknown,unknown_owners{1})));
exception_draft=Annotations.Catalog.parse('CEMDL','XX',true);
exception_store=Annotations.Store.command(store,owners{1},exception_draft,'assign', ...
    struct('context_exception_reason','Researcher verified this specimen context exception.'));
saved_exception=Annotations.Store.record(exception_store,owners{1});
saved_exception.valid=true; saved_exception.requires_staging=false;
[unchanged,event]=Annotations.Store.command(exception_store,owners{1},saved_exception,'assign');
assert(~event.changed && strcmp(unchanged.records(1).context_exception_reason,exception_store.records(1).context_exception_reason));
expect(@() Annotations.Store.command(exception_store,owners{1},saved_exception,'assign', ...
    struct('context_exception_reason','')),'Annotations:Context');

% Context changes preserve claims, without silently retaining invalid pins.
sexbase=Annotations.Store.command(store,owners{1},Annotations.Catalog.parse('HSNL','XX'),'assign');
[male,event]=Annotations.Store.recontextualize(sexbase,struct('sex','XO'));
changed=Annotations.Store.record(male,owners{1});
assert(event.changed && strcmp(changed.review,'needs-review') && strcmp(changed.candidates{1},'HSNL'));
assert(~Annotations.Store.confirmed(changed));
expect(@() Annotations.Store.undo(male),'Annotations:UndoConflict');
female=Annotations.Store.recontextualize(male,struct('sex','XX'));
changed=Annotations.Store.record(female,owners{1}); assert(strcmp(changed.review,'needs-review'));
female=Annotations.Store.undo(female);
assert(Annotations.Store.confirmed(Annotations.Store.record(female,owners{1})));

% Confirming a member never erases the other researcher's hypothesis.
confirmed=Annotations.Catalog.parse('AVAL','XX');
[b,event]=Annotations.Store.command(a,owners{1},confirmed,'assign',struct('operation_id','confirm-once'));
assert(event.changed && Annotations.Store.confirmed(Annotations.Store.record(b,owners{1})));
other=Annotations.Store.record(b,owners{2});
assert(strcmp(other.certainty,'tentative') && any(strcmp(other.conflicts,'AVAL')));
expect(@() Annotations.Store.command(b,owners{2},confirmed,'assign'),'Annotations:Occupied');
[replayed,event]=Annotations.Store.command(b,owners{1},confirmed,'assign',struct('operation_id','confirm-once'));
assert(isequaln(replayed,b) && event.replayed && ~event.changed);
expect(@() Annotations.Store.command(b,owners{1},confirmed,'assign',struct('expected_revision',0)),'Annotations:StaleDraft');

% A group and AWC functional state survive without inventing a side.
group=Annotations.Catalog.stageGroup('IL1?','XX');
c=Annotations.Store.command(b,owners{3},group,'assign');
r=Annotations.Store.record(c,owners{3});
assert(strcmp(r.kind,'unresolved_set') && numel(r.candidates)==6);
awc=Annotations.Catalog.stageGroup('AWC-ON?','XX');
c=Annotations.Store.command(c,owners{4},awc,'assign');
awc_record=Annotations.Store.record(c,owners{4}); assert(awc_record.attributes.on_off==1);

% Move is one edit, and Undo restores every affected record.
before=c;
[moved,event]=Annotations.Store.command(c,owners{2},confirmed,'move',struct('confirmed',true,'conflict_owner',owners{1}));
assert(event.changed && strcmp(Annotations.Store.occupant(moved,'AVAL'),owners{2}));
cleared=Annotations.Store.record(moved,owners{1}); assert(strcmp(cleared.kind,'unassigned'));
restored=Annotations.Store.undo(moved);
assert(strcmp(Annotations.Store.occupant(restored,'AVAL'),owners{1}));
for i=1:numel(owners)
    old=Annotations.Store.record(before,owners{i}); now=Annotations.Store.record(restored,owners{i});
    assert(strcmp(old.kind,now.kind) && isequal(old.candidates,now.candidates));
end

% Multi-owner swaps validate final occupancy, never an invalid halfway state.
swapbase=Annotations.Store.create(neurons,context);
swapowners={swapbase.owners.owner_id};
swapbase=Annotations.Store.command(swapbase,swapowners{1},Annotations.Catalog.parse('AVAL','XX'),'assign');
swapbase=Annotations.Store.command(swapbase,swapowners{2},Annotations.Catalog.parse('AVAR','XX'),'assign');
swapped=Annotations.Store.command(swapbase,swapowners{1},Annotations.Catalog.parse('AVAR','XX'),'swap',struct('confirmed',true));
assert(strcmp(Annotations.Store.occupant(swapped,'AVAL'),swapowners{2}));
swapped=Annotations.Store.undo(swapped);
assert(strcmp(Annotations.Store.occupant(swapped,'AVAL'),swapowners{1}));
swapped=Annotations.Store.undo(swapped);
assert(isempty(Annotations.Store.occupant(swapped,'AVAR')));
changes(1)=struct('owner_id',swapowners{1},'draft',Annotations.Catalog.parse('AVAR','XX'),'action','assign');
changes(2)=struct('owner_id',swapowners{2},'draft',Annotations.Catalog.parse('AVAL','XX'),'action','assign');
batched=Annotations.Store.batch(swapbase,changes,struct('confirmed',true));
assert(strcmp(Annotations.Store.occupant(batched,'AVAL'),swapowners{2}));
batched=Annotations.Store.undo(batched);
assert(strcmp(Annotations.Store.occupant(batched,'AVAL'),swapowners{1}));

% Restore keeps newer evidence and history, and never reoccupies retired owners.
exported=swapbase;
current=Annotations.Store.command(swapbase,swapowners{2},struct(),'clear',struct('confirmed',true));
[current,new_evidence]=Annotations.Store.captureEvidence(current,swapowners{1}, ...
    struct('label','new model suggestion'),struct('inference_id','run-new','bundle_id','bundle-v2'));
[imported,event]=Annotations.Store.restore(current,exported, ...
    struct('confirmed',true,'owner_ids',{{swapowners{1}}}));
assert(event.changed && isempty(Annotations.Store.occupant(imported,'AVAR')));
assert(any(strcmp({imported.evidence.evidence_id},new_evidence)) && ~isempty(imported.imported_histories));
assert(numel(imported.journal)==numel(current.journal)+1);
collision=exported; collision.evidence(1).origin='different content under same evidence UUID';
expect(@() Annotations.Store.restore(current,collision,struct('confirmed',true)),'Annotations:EvidenceCollision');

% Model policy is opt-in and unsupported group pins stop dispatch.
selected=Annotations.Store.selectConstraints(swapbase,true,{swapowners{1}});
pins=Annotations.Store.constraints(selected,'crf'); assert(numel(pins)==1);
[unchanged,event]=Annotations.Store.command(selected,swapowners{1},Annotations.Catalog.parse('AVAL','XX'),'assign');
assert(~event.changed && strcmp(unchanged.records(1).constraint_policy,'hard'));
replaced=Annotations.Store.command(selected,swapowners{1},Annotations.Catalog.parse('ALA','XX'),'replace');
assert(strcmp(replaced.records(1).constraint_policy,'off'));
groupbase=Annotations.Store.command(store,owners{1},Annotations.Catalog.stageGroup('AVA','XX'),'assign');
groupbase.constraints_enabled=true; groupbase.records(1).constraint_policy='hard';
expect(@() Annotations.Store.constraints(groupbase,'crf'),'Annotations:UnsupportedConstraint');

% Malformed legacy fields and duplicate human bindings remain visible issues.
legacy=neurons; legacy(1).annotation='AWCL-GARBAGE';
legacy(2).annotation='AVAL'; legacy(2).annotation_confidence=1;
legacy(3).annotation='AVAL'; legacy(3).annotation_confidence=1;
legacy(4).annotation='ARTIFACT'; legacy(4).annotation_confidence=1;
migrated=Annotations.Store.create(legacy,context);
assert(strcmp(migrated.records(1).kind,'legacy_issue'));
assert(strcmp(migrated.records(2).review,'needs-review') && strcmp(migrated.records(3).review,'needs-review'));
assert(isempty(Annotations.Store.occupant(migrated,'AVAL')));
p=Annotations.Store.project(migrated); assert(strcmp(p(4).annotation,'ARTIFACT'));

% Atomic publication preserves unrelated variables and rejects stale writers.
folder=tempname; mkdir(folder); cleanup=onCleanup(@() rmdir(folder,'s'));
path=fullfile(folder,'sample_ID.mat');
payload=struct('annotation_store',swapbase,'sentinel',struct('kept',true));
counter_path=fullfile(folder,'invalid_counters.mat'); counter_payload=payload;
counter_payload.annotation_store.generation='invalid generation';
counter_payload.annotation_store.revision=NaN;
builtin('save',counter_path,'-struct','counter_payload','-v7.3');
counter=Annotations.Store.fingerprint(counter_path);
assert(counter.exists && ~isempty(counter.sha256) && isa(counter.generation,'double') && ...
    counter.generation==0 && counter.revision==0);
expect(@() Annotations.Store.validate(counter_payload.annotation_store),'Annotations:Schema');
counter_payload.annotation_store.generation=NaN; counter_payload.annotation_store.revision={'invalid revision'};
builtin('save',counter_path,'-struct','counter_payload','-v7.3');
counter_next=Annotations.Store.fingerprint(counter_path);
assert(counter_next.generation==0 && counter_next.revision==0 && ~strcmp(counter.sha256,counter_next.sha256));
counter_payload.annotation_store.generation=int32(4); counter_payload.annotation_store.revision=3;
builtin('save',counter_path,'-struct','counter_payload','-v7.3');
counter=Annotations.Store.fingerprint(counter_path);
assert(isa(counter.generation,'double') && counter.generation==4 && counter.revision==3);
directory_target=fullfile(folder,'not_an_ID_file'); mkdir(directory_target);
before_files=dir(folder); before_names=sort({before_files.name});
expect(@() Annotations.Store.save(directory_target,payload,Annotations.Store.fingerprint(directory_target)),'Annotations:SavePath');
after_files=dir(folder); assert(isequal(sort({after_files.name}),before_names));
assert(exist([directory_target '.annotations.lock'],'file')~=2 && ...
    exist([directory_target '.annotations.lineage.json'],'file')~=2);
expect(@() Annotations.Store.save('',payload,Annotations.Store.fingerprint('')),'Annotations:SavePath');
initial=Annotations.Store.fingerprint(path);
[saved,fingerprint]=Annotations.Store.save(path,payload,initial);
loaded=load(path); assert(loaded.sentinel.kept && isequaln(loaded.annotation_store,saved.annotation_store));
first=fingerprint;
payload.annotation_store=Annotations.Store.command(saved.annotation_store,swapowners{3},Annotations.Catalog.parse('ALA','XX'),'assign');
expect(@() Annotations.Store.save(path,payload,fingerprint,struct('fail_at','before_replace')),'Annotations:InjectedFailure');
assert(isequaln(Annotations.Store.fingerprint(path),first));
[~,fingerprint]=Annotations.Store.save(path,payload,first);
assert(fingerprint.generation==first.generation+1 && exist([path '.lastgood.mat'],'file')==2);
expect(@() Annotations.Store.save(path,payload,first),'Annotations:StaleSave');
assert(isequaln(Annotations.Store.fingerprint(path),fingerprint));
post_payload=load(path);
post_payload.annotation_store=Annotations.Store.command(post_payload.annotation_store,swapowners{4}, ...
    Annotations.Catalog.parse('AVBR','XX'),'assign');
before_publication=fingerprint;
expect(@() Annotations.Store.save(path,post_payload,before_publication,struct('fail_at','after_replace')),'Annotations:PublishedSave');
published=load(path); fingerprint=Annotations.Store.fingerprint(path);
assert(fingerprint.generation==before_publication.generation+1);
assert(strcmp(Annotations.Store.occupant(published.annotation_store,'AVBR'),swapowners{4}));
writer=java.io.RandomAccessFile([path '.annotations.lock'],'rw');
writer_cleanup=onCleanup(@() writer.close()); lock=writer.getChannel().tryLock();
assert(~isempty(lock));
expect(@() Annotations.Store.save(path,payload,fingerprint),'Annotations:WriterBusy');
assert(isequaln(Annotations.Store.fingerprint(path),fingerprint));
clear writer_cleanup;
[loaded,~,issues]=Annotations.Store.loadValidated(path); assert(isempty(issues));
assert(isequaln(loaded.annotation_store.evidence,swapbase.evidence));
pending=[path '.processing.pending.json']; fid=fopen(pending,'w'); fwrite(fid,'{}'); fclose(fid);
issues=Annotations.Store.verifyLineage(path,loaded);
assert(any(strcmp({issues.code},'processing-save-pending'))); delete(pending);
tampered=loaded.annotation_store; tampered.evidence(1).values.probabilistic_probs=[1 0];
expect(@() Annotations.Store.validate(tampered),'Annotations:EvidenceIntegrity');
legacy_writer=struct('sentinel','older writer removed the extended schema');
builtin('save',path,'-struct','legacy_writer','-v7.3');
[~,~,issues]=Annotations.Store.loadValidated(path);
assert(any(strcmp({issues.code},'versioned-store-erased')));

fprintf('ANNOTATION_STORE_TRANSACTIONS_EVIDENCE_OCCUPANCY_ATOMIC_SAVE=PASS\n');
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
