function test_annotation_job_context()
%TEST_ANNOTATION_JOB_CONTEXT Freeze owners and constraints without blocking unrelated ID work.
image=Neurons.Image([]);
for i=1:2
    n=Neurons.Neuron;
    n.position=[2 3 1]; n.deterministic_id='AVA';
    n.probabilistic_ids={'AVA','AVB'}; n.probabilistic_probs=[.7 .3]; n.rank=i;
    image.neurons(i)=n;
end
[store,owners]=Annotations.Store.create(image.neurons,struct('sex','XX','source_id','job-context-fixture'));
for i=1:numel(owners), image.neurons(i).annotation_id=owners{i}; end
Program.GUI.ManualIDService.apply(image,store);
app=struct('image_file','job-context.mat','image_data',zeros(4,5,3,4,'uint8'), ...
    'image_um_scale',[.4 .4 1.5],'image_prefs',struct('RGBW',1:4), ...
    'worm',struct('body','Head','sex','XX'),'image_neurons',image);
watched=Program.Helpers.main_job_context(app,true);
unwatched=Program.Helpers.main_job_context(app,true,false);
assert(watched.watch_annotations && ~unwatched.watch_annotations);
Program.Helpers.assert_main_job_context(app,watched);
Program.Helpers.assert_main_job_context(app,unwatched);

% A tentative record may have no legacy projection but still changes human work.
changed=Annotations.Store.command(store,owners{1},Annotations.Catalog.parse('AVAL?','XX'),'assign');
Program.GUI.ManualIDService.apply(image,changed);
reject(@() Program.Helpers.assert_main_job_context(app,watched));
Program.Helpers.assert_main_job_context(app,unwatched);
assert(isempty(image.neurons(1).annotation));
assert(isequal(image.neurons(1).probabilistic_probs,[.7 .3]));

% Positions can be identical: stable owner order must still identify the input.
original=image.neurons; image.neurons=image.neurons([2 1]);
reject(@() Program.Helpers.assert_main_job_context(app,unwatched));
image.neurons=original;
owner=image.neurons(1).annotation_id; image.neurons(1).annotation_id='replacement-owner';
reject(@() Program.Helpers.assert_main_job_context(app,unwatched));
image.neurons(1).annotation_id=owner;
position=image.neurons(1).position; image.neurons(1).position=position+[.25 0 0];
reject(@() Program.Helpers.assert_main_job_context(app,unwatched));
image.neurons(1).position=position;
Program.Helpers.assert_main_job_context(app,unwatched);

% A constraint snapshot is frozen even when unconstrained annotation edits are allowed.
confirmed=Annotations.Store.command(changed,owners{1},Annotations.Catalog.parse('ALA','XX'),'assign');
pinned=Annotations.Store.selectConstraints(confirmed,true,owners(1));
Program.GUI.ManualIDService.apply(image,pinned);
constrained=Program.Helpers.main_job_context(app,true,false);
Program.Helpers.assert_main_job_context(app,constrained);
unrelated=Annotations.Store.command(pinned,owners{2},Annotations.Catalog.parse('AVAL?','XX'),'assign');
Program.GUI.ManualIDService.apply(image,unrelated);
Program.Helpers.assert_main_job_context(app,constrained);
Program.GUI.ManualIDService.apply(image,pinned);
off=Annotations.Store.selectConstraints(pinned,false,{});
Program.GUI.ManualIDService.apply(image,off);
reject(@() Program.Helpers.assert_main_job_context(app,constrained));
Program.GUI.ManualIDService.apply(image,pinned);
repinned=Annotations.Store.command(pinned,owners{1},Annotations.Catalog.parse('AVAR','XX'),'assign');
Program.GUI.ManualIDService.apply(image,repinned);
reject(@() Program.Helpers.assert_main_job_context(app,constrained));

% Source fields remain immutable for both context policies.
Program.GUI.ManualIDService.apply(image,changed);
different=app; different.image_file='other.mat';
reject(@() Program.Helpers.assert_main_job_context(different,unwatched));
different=app; different.image_um_scale=[.4 .4 2];
reject(@() Program.Helpers.assert_main_job_context(different,unwatched));
different=app; different.image_prefs.RGBW=[2 1 3 4];
reject(@() Program.Helpers.assert_main_job_context(different,unwatched));
fprintf('ANNOTATION_JOB_CONTEXT_OWNERS_POLICY_CONSTRAINTS=PASS\n');
end

function reject(callback)
try
    callback(); error('test:MissingError','Changed job input was accepted.');
catch ME
    assert(strcmp(ME.identifier,'Program:HeavyJob:SourceChanged'),ME.message);
end
end
