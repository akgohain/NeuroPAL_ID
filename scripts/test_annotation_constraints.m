function test_annotation_constraints()
%TEST_ANNOTATION_CONSTRAINTS Reject selected identities absent from the atlas.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
image=Neurons.Image([]);
for i=1:2
    neuron=Neurons.Neuron;
    neuron.position=[i 2 1];
    image.neurons(i)=neuron;
end
[store,owners]=Annotations.Store.create(image.neurons,struct('sex','XX','source_id','constraint-fixture'));
for i=1:numel(owners), image.neurons(i).annotation_id=owners{i}; end
store=Annotations.Store.command(store,owners{1},Annotations.Catalog.parse('CANL','XX'),'assign');
store=Annotations.Store.command(store,owners{2},Annotations.Catalog.parse('ALA','XX'),'assign');
selected=Annotations.Store.selectConstraints(store,true,owners);
image.annotation_store=selected;
expect(@() Annotations.constraints(image,'crf',{'ALA'}),'Annotations:UnsupportedConstraint');
assert(isequaln(image.annotation_store,selected));
assert(isequal(Annotations.constraints(image,'crf',{'CANL','ALA'}),{'CANL';'ALA'}));
expect(@() Annotations.constraints(image,'crf',{}),'Annotations:UnsupportedConstraint');

% A saved identity does not become a constraint without the explicit policy.
image.annotation_store=Annotations.Store.selectConstraints(selected,false,{});
assert(isequal(Annotations.constraints(image,'crf',{'ALA'}),{'';''}));
assert(all(strcmp({image.annotation_store.records.constraint_policy},'off')));

% Selecting a subset replaces the previous complete selection. In particular,
% the unsupported CANL pin must not survive selecting only the supported ALA.
subset=Annotations.Store.selectConstraints(selected,true,owners(2));
assert(subset.revision==selected.revision+1);
assert(subset.records(1).revision==selected.records(1).revision+1);
assert(subset.records(2).revision==selected.records(2).revision);
assert(isequal({subset.records.constraint_policy},{'off','hard'}));
image.annotation_store=subset;
assert(isequal(Annotations.constraints(image,'crf',{'ALA'}),{'';'ALA'}));
assert(isequaln(Annotations.Store.selectConstraints(subset,true,owners(2)),subset));

% An empty selection clears all pins even while the policy remains enabled.
empty=Annotations.Store.selectConstraints(subset,true,{});
assert(empty.constraints_enabled && all(strcmp({empty.records.constraint_policy},'off')));
image.annotation_store=empty;
assert(isequal(Annotations.constraints(image,'crf',{}),{'';''}));
fprintf('ANNOTATION_CONSTRAINT_ATLAS_VOCABULARY=PASS\n');
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
