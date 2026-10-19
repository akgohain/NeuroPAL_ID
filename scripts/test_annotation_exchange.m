function test_annotation_exchange()
%TEST_ANNOTATION_EXCHANGE Preserve structured identities and report legacy loss.
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(repo);
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
neurons = Neurons.Neuron.empty;
for i = 1:4
    neurons(i) = Neurons.Neuron();
    neurons(i).deterministic_id = 'IL1';
    neurons(i).probabilistic_ids = {'IL1', 'AVA'};
    neurons(i).probabilistic_probs = [0.8 0.2];
end
context = struct('source_id', 'exchange-test-source', 'specimen_id', 'exchange-test-specimen', ...
    'sex', 'XX', 'geometry_revision', 'geometry-1');
[store, owners] = Annotations.Store.create(neurons, context);
store = Annotations.Store.command(store, owners{1}, Annotations.Catalog.parse('AVAL', 'XX'));
draft = Annotations.Catalog.stageGroup('IL1?!', 'XX');
draft.attributes.notes = sprintf('comma, "quote"\nsecond line');
store = Annotations.Store.command(store, owners{2}, draft);
store = Annotations.Store.command(store, owners{3}, Annotations.Catalog.parse('CEMDL', 'XX', true), ...
    'assign', struct('context_exception_reason', 'Explicit engineering test exception.'));
store = Annotations.Store.command(store, owners{4}, Annotations.Catalog.parse('ARTIFACT', 'XX'));
evidence = store.evidence;

path = fullfile(folder, 'identities.mat');
report = Annotations.Exchange.export(path, store);
assert(report.full_fidelity && report.integrity_verified && report.evidence_complete);
assert(~report.original_model_evidence_verified && ~isempty(report.unverified_legacy_evidence_ids));
assert(ismember(owners{2}, report.legacy_lossy_owner_ids));
[restored, readReport] = Annotations.Exchange.read(path);
assert(isequaln(restored, store) && readReport.integrity_verified && readReport.catalog_compatible);
assert(isequaln(restored.evidence, evidence) && numel(restored.journal) == 4);
record = Annotations.Store.record(restored, owners{2});
assert(strcmp(record.kind, 'unresolved_set') && numel(record.candidates) == 6);
assert(strcmp(record.certainty, 'tentative') && record.attributes.emphasized);
assert(isequal(record.attributes.notes, draft.attributes.notes));
record = Annotations.Store.record(restored, owners{3});
assert(~isempty(record.context_exception_reason));

% Owner IDs determine projections, even if an export caller reorders rows.
order = [3 1 4 2];
rows = struct('annotation_id', owners(order));
Annotations.Exchange.export(fullfile(folder, 'reordered.mat'), store, rows);
loaded = load(fullfile(folder, 'reordered.mat'), 'identity_exchange');
assert(isequal({loaded.identity_exchange.payload.legacy_projection.annotation_id}, owners(order)));
assert(strcmp(loaded.identity_exchange.payload.legacy_projection(2).annotation, 'AVAL'));
assert(isempty(loaded.identity_exchange.payload.legacy_projection(4).annotation));

% The summary quotes JSON, commas, quotes, and line breaks; it declares omissions.
csv = fullfile(folder, 'identities.csv');
summary = Annotations.Exchange.export(csv, store);
assert(~summary.full_fidelity && ~isempty(summary.omitted_fields));
table = readtable(csv, 'TextType', 'string', 'VariableNamingRule', 'preserve');
assert(height(table) == 4 && all(table.format == "NeuroPAL.IdentitySummary/1"));
index = find(table.owner_id == string(owners{2}));
assert(isequal(cellstr(string(jsondecode(table.candidates_json(index)))), recordCandidates(store, owners{2})'));
assert(table.notes(index) == string(draft.attributes.notes));
assert(contains(table.omitted_fields_json(index), 'annotation history'));

% Content corruption, missing evidence, and external references are never hidden.
loaded = load(path, 'identity_exchange');
loaded.identity_exchange.payload.annotation_store.records(1).attributes.notes = 'tampered';
identity_exchange = loaded.identity_exchange;
corrupt = fullfile(folder, 'corrupt.mat'); save(corrupt, 'identity_exchange');
expectError(@() Annotations.Exchange.read(corrupt), 'Annotations:ExchangeIntegrity');
loaded = load(path, 'identity_exchange');
identity_exchange = loaded.identity_exchange;
identity_exchange.payload.annotation_store.records(1).attributes.on_off = Inf;
save(corrupt, 'identity_exchange');
expectError(@() Annotations.Exchange.read(corrupt), 'Annotations:ExchangeIntegrity');

missing = store;
missing.records(1).model_evidence_ids{end+1} = 'missing-evidence';
report = Annotations.Exchange.export(fullfile(folder, 'missing-evidence.mat'), missing);
assert(~report.evidence_complete && ismember('missing-evidence', report.missing_evidence_ids));
external = store;
external.evidence(1).values.response_file = '/unavailable/model-response.json';
external.evidence(1).sha256 = hashValues(external.evidence(1).values);
report = Annotations.Exchange.export(fullfile(folder, 'external-evidence.mat'), external);
assert(~report.evidence_complete && ~isempty(report.external_evidence_references));

% Unsupported export types and failed destinations do not touch live state.
expectError(@() Annotations.Exchange.export(fullfile(folder, 'identities.txt'), store), 'Annotations:ExchangeFormat');
expectError(@() Annotations.Exchange.export(fullfile(folder, 'absent', 'identities.mat'), store), 'Annotations:ExchangeFolder');
assert(isequaln(Annotations.Exchange.read(path), store));
fprintf('ANNOTATION_EXCHANGE_FULL_ROUNDTRIP_LEGACY_LOSS_INTEGRITY=PASS\n');
end

function candidates = recordCandidates(store, owner)
record = Annotations.Store.record(store, owner); candidates = record.candidates;
end

function hash = hashValues(value)
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(jsonencode(value)), 'int8'));
hash = lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
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
