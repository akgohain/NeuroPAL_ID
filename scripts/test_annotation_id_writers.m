function test_annotation_id_writers()
%TEST_ANNOTATION_ID_WRITERS Protect versioned IDs and roll back paired saves.
repo = fileparts(fileparts(mfilename('fullpath'))); addpath(repo);
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
imageFile = fullfile(folder, 'image.mat');
idFile = fullfile(folder, 'image_ID.mat');
data = reshape(uint8(1:120), [5 6 4]);
info = struct('scale', [1 1 1]); prefs = struct('RGBW', [1 1 1 NaN]);
builtin('save', imageFile, 'data', 'info', 'prefs', '-v7.3');

% Legacy batch publishing retains unrelated fields and detects mid-run changes.
sentinel = 'preserve this legacy variable';
builtin('save', idFile, 'sentinel');
expected = Annotations.IDWriters.legacySnapshot(idFile);
Annotations.IDWriters.publishLegacy(idFile, struct('mp_params', struct('k', 2)), expected);
loaded = load(idFile);
assert(strcmp(loaded.sentinel, sentinel) && loaded.mp_params.k == 2);
expected = Annotations.IDWriters.legacySnapshot(idFile);
changed = true; builtin('save', idFile, 'changed', '-append');
before = Annotations.Store.fingerprint(idFile);
expectError(@() Annotations.IDWriters.publishLegacy(idFile, struct('sentinel', 'erase'), expected), 'Annotations:StaleSave');
assert(isequal(Annotations.Store.fingerprint(idFile), before));

% Each batch entry point refuses a protected source before conversion or model work.
neurons = Neurons.Image([]);
for i = 1:2
    neuron = Neurons.Neuron(); neuron.position = [i i 2];
    neurons.neurons(i) = neuron;
end
[store, owners] = Annotations.Store.create(neurons, struct('sex', 'XX', 'source_id', 'writer-test'));
for i = 1:numel(owners), neurons.neurons(i).annotation_id = owners{i}; end
store = Annotations.Store.command(store, owners{1}, Annotations.Catalog.parse('AVAL', 'XX'));
store = Annotations.Store.command(store, owners{2}, Annotations.Catalog.stageGroup('IL1?', 'XX'));
Program.GUI.ManualIDService.apply(neurons, store);
annotation_store = store;
builtin('save', idFile, 'neurons', 'annotation_store', 'sentinel');
before = Annotations.Store.fingerprint(idFile);
worm = struct('body', 'Head', 'sex', 'XX');
figures = numel(findall(groot, 'Type', 'figure'));
expectError(@() Methods.AutoId.BatchId(imageFile, worm), 'Annotations:LegacyBatchProtected');
expectError(@() Methods.AutoDetect.BatchDetect(imageFile, worm, 2), 'Annotations:LegacyBatchProtected');
expectError(@() Methods.NNDetect.BatchDetect(imageFile, worm, 2), 'Annotations:LegacyBatchProtected');
expectError(@() Methods.CellposeDetect.BatchDetect(imageFile, worm, 2), 'Annotations:LegacyBatchProtected');
assert(numel(findall(groot, 'Type', 'figure')) == figures);
assert(isequal(Annotations.Store.fingerprint(idFile), before));
expectError(@() Annotations.IDWriters.publishLegacy(idFile, struct('neurons', []), expected), 'Annotations:LegacyBatchProtected');

% Embedded stores and lineage-only files receive the same protection.
builtin('save', idFile, 'neurons', 'sentinel');
expectError(@() Annotations.IDWriters.guardBatch(imageFile, 'test'), 'Annotations:LegacyBatchProtected');
builtin('save', idFile, 'sentinel');
marker = [idFile '.annotations.lineage.json'];
fid = fopen(marker, 'w'); fwrite(fid, '{}', 'char'); fclose(fid);
expectError(@() Annotations.IDWriters.guardBatch(imageFile, 'test'), 'Annotations:LegacyBatchProtected');
delete(marker);

% Prepare a valid original pair with a recoverable publication lineage.
payload = struct('neurons', neurons, 'annotation_store', store, 'sentinel', sentinel, ...
    'version', 1, 'mp_params', struct('k', 2));
[payload, expectedID] = Annotations.Store.save(idFile, payload, Annotations.Store.fingerprint(idFile));
Program.GUI.ManualIDService.apply(neurons, payload.annotation_store);
payload.neurons = Program.GUI.ManualIDService.copyImage(neurons);
expectedImage = Annotations.Store.fingerprint(imageFile);
oldLineage = fileread(marker);
for stage = {'before_image_replace', 'after_image_replace', 'after_id_replace'}
    staged = stagedImage(folder, data + uint8(10), info, prefs);
    expectError(@() Annotations.IDWriters.publishPair(imageFile, staged, idFile, payload, ...
        expectedImage, expectedID, struct('fail_at', stage{1})), 'Annotations:InjectedFailure');
    assert(isequal(Annotations.Store.fingerprint(imageFile), expectedImage));
    assert(isequal(Annotations.Store.fingerprint(idFile), expectedID));
    assert(strcmp(fileread(marker), oldLineage));
    assert(~isfile([idFile '.processing.pending.json']));
    assert(isequaln(neurons.annotation_store, payload.annotation_store));
end

% The shared writer lease and fingerprints reject concurrent or stale publishers.
lease = java.io.RandomAccessFile([idFile '.annotations.lock'], 'rw');
leaseCleanup = onCleanup(@() lease.close());
held = lease.getChannel().lock();
staged = stagedImage(folder, data + uint8(20), info, prefs);
expectError(@() Annotations.IDWriters.publishPair(imageFile, staged, idFile, payload, ...
    expectedImage, expectedID), 'Annotations:WriterBusy');
held.release(); clear leaseCleanup;
wrong = expectedID; wrong.sha256 = repmat('0', 1, 64);
expectError(@() Annotations.IDWriters.publishPair(imageFile, staged, idFile, payload, ...
    expectedImage, wrong), 'Annotations:StaleSave');
assert(isequal(Annotations.Store.fingerprint(idFile), expectedID));

% A successful processing publication keeps structured ambiguity and history.
[saved, published] = Annotations.IDWriters.publishPair(imageFile, staged, idFile, payload, expectedImage, expectedID);
loaded = load(imageFile, 'data'); assert(isequal(loaded.data, data + uint8(20)));
[ids, fingerprint, issues] = Annotations.Store.loadValidated(idFile);
assert(isempty(issues) && isequal(fingerprint, published));
assert(saved.annotation_store.generation == expectedID.generation + 1);
assert(isequaln(ids.annotation_store, saved.annotation_store));
assert(isequaln(ids.neurons.annotation_store, ids.annotation_store));
assert(strcmp(ids.sentinel, sentinel) && numel(ids.annotation_store.journal) == 2);
record = Annotations.Store.record(ids.annotation_store, owners{2});
assert(strcmp(record.kind, 'unresolved_set') && numel(record.candidates) == 6);
assert(isempty(ids.neurons.neurons(2).annotation));
assert(isfile([idFile '.lastgood.mat']) && ~isfile([idFile '.processing.pending.json']));

% Processing copies retain authoritative state and read-only recovery context.
neurons.annotation_read_only_reason = 'recovery fixture';
copy = Program.ProcessingSession.copyNeurons(neurons);
assert(isequaln(copy.annotation_store, neurons.annotation_store));
assert(strcmp(copy.annotation_read_only_reason, neurons.annotation_read_only_reason));
assert(~isequal(copy, neurons) && ~isequal(copy.neurons(1), neurons.neurons(1)));
fprintf('ANNOTATION_ID_WRITERS_BATCH_GUARDS_PAIR_ROLLBACK=PASS\n');
end

function path = stagedImage(folder, data, info, prefs)
path = [tempname(folder) '.mat'];
builtin('save', path, 'data', 'info', 'prefs', '-v7.3');
end

function expectError(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), '%s: %s', ME.identifier, ME.message);
    return;
end
error('Expected error %s.', identifier);
end
