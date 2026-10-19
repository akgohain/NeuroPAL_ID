function test_neuropal_id_integrity_fallback()
%TEST_NEUROPAL_ID_INTEGRITY_FALLBACK Inspect pixels without blessing damaged IDs.
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
path = fullfile(folder, 'integrity.mat'); idFile = fullfile(folder, 'integrity_ID.mat');
version = Program.ProgramInfo.version;
data = zeros(8, 10, 3, 4, 'uint8');
info = struct('scale', [.4 .4 1.5]);
prefs = struct('RGBW', 1:4, 'DIC', NaN, 'GFP', NaN, 'gamma', ones(4, 1), ...
    'rotate', struct('horizontal', false, 'vertical', false));
worm = struct('sex', 'XX', 'body', 'Head', 'age', 'Adult', 'strain', '', 'notes', '');
builtin('save', path, 'version', 'data', 'info', 'prefs', 'worm', '-v7.3');
neurons = Neurons.Image([], 'scale', info.scale);
labels = {'AVAL', 'IL1', 'AWCL-GARBAGE', 'NOTANEURON'};
for i = 1:numel(labels)
    neuron = Neurons.Neuron();
    neuron.position = [i+1 3 2];
    neuron.annotation_id = sprintf('preserved-owner-%d', i);
    neuron.annotation = labels{i}; neuron.annotation_confidence = 1;
    neuron.deterministic_id = 'IL1';
    neuron.is_annotation_on = false;
    neurons.neurons(i) = neuron;
end
% The source contains deliberately invalid top-level and embedded stores.
neurons.annotation_store = struct('schema_version', 2, 'revision', 'damaged');
annotation_store = neurons.annotation_store;
builtin('save', idFile, 'version', 'neurons', 'annotation_store', '-v7.3');
before = Annotations.Store.fingerprint(idFile);
imageBefore = Annotations.Store.fingerprint(path);
[loaded, ~, ~, ~, ~, restored] = DataHandling.NeuroPALImage.open(path);
assert(isequal(data, loaded) && numel(restored.neurons) == numel(labels));
assert(~isempty(restored.annotation_read_only_reason));
assert(strcmp(restored.annotation_store.context.recovery_mode, 'compatibility-only'));
assert(isequal({restored.neurons.annotation_id}, {neurons.neurons.annotation_id}));
assert(~any(arrayfun(@Annotations.Store.confirmed, restored.annotation_store.records)));
assert(~restored.annotation_store.constraints_enabled);
assert(all(strcmp({restored.annotation_store.records.review}, 'needs-review')));
provenance = [restored.annotation_store.records.provenance];
assert(all(strcmp({provenance.source}, 'read-only-compatibility-projection')));
assert(strcmp(restored.annotation_store.records(1).kind, 'individual'));
assert(strcmp(restored.annotation_store.records(2).kind, 'unresolved_set'));
assert(all(strcmp({restored.annotation_store.records(3:4).kind}, 'legacy_issue')));
assert(all(cellfun(@isempty, {restored.neurons.deterministic_id})));
assert(isequal(Annotations.Store.fingerprint(idFile), before));
assert(isequal(Annotations.Store.fingerprint(path), imageBefore));
Annotations.Store.validate(restored.annotation_store);

% A valid schema with corrupt evidence also reaches the read-only recovery view.
clean = Neurons.Image([]); clean.neurons(1) = Neurons.Neuron();
clean.neurons(1).position = [2 3 2]; clean.neurons(1).annotation = 'AVAL';
clean.neurons(1).annotation_confidence = 1;
[annotation_store, owners] = Annotations.Store.create(clean, struct('sex', 'XX'));
clean.neurons(1).annotation_id = owners{1};
Program.GUI.ManualIDService.apply(clean, annotation_store);
annotation_store.evidence(1).values.rank = 123;
neurons = clean;
builtin('save', idFile, 'version', 'neurons', 'annotation_store', '-v7.3');
before = Annotations.Store.fingerprint(idFile);
[~, ~, ~, ~, ~, restored] = DataHandling.NeuroPALImage.open(path);
assert(~isempty(restored.annotation_read_only_reason));
assert(contains(restored.annotation_store.context.recovery_error_identifier, 'EvidenceIntegrity'));
assert(~any(arrayfun(@Annotations.Store.confirmed, restored.annotation_store.records)));
assert(isequal(Annotations.Store.fingerprint(idFile), before));

% If no compatibility object can be read, pixels still open with an empty view.
fid = fopen(idFile, 'wb'); fwrite(fid, uint8('not a MAT file')); fclose(fid);
before = Annotations.Store.fingerprint(idFile);
[loaded, ~, ~, ~, ~, restored] = DataHandling.NeuroPALImage.open(path);
assert(isequal(loaded, data) && isempty(restored.neurons));
assert(~isempty(restored.annotation_read_only_reason));
assert(strcmp(restored.annotation_store.context.recovery_mode, 'compatibility-only'));
assert(isequal(Annotations.Store.fingerprint(idFile), before));
fprintf('NEUROPAL_ID_INTEGRITY_READONLY_FALLBACK=PASS\n');
end
