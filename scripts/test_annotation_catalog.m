function test_annotation_catalog()
%TEST_ANNOTATION_CATALOG Keep individual, group, and model identities distinct.
repo = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo, 'Data', 'NeuroPAL'));
herm = Annotations.Catalog.names('XX');
male = Annotations.Catalog.names('XO');
allNames = Annotations.Catalog.names('unknown');
assert(numel(herm) == 302 && numel(male) == 387 && numel(allNames) == 395);
expectedHerm = Neurons.Hermaphrodite.getNeurons();
expectedMale = Neurons.Male.getNeurons();
assert(isequal(sort(herm), sort(cellstr(string(expectedHerm(:))))));
assert(isequal(sort(male), sort(cellstr(string(expectedMale(:))))));
assert(isequal(allNames, Annotations.Catalog.names('')));
assert(isequal(allNames, Annotations.Catalog.names('XX', true)));
assert(isequal(herm, Annotations.Catalog.names('hermaphrodite')));
assert(isequal(male, Annotations.Catalog.names('Male')));
assert(~any(ismember({'HSNL', 'HSNR', 'VC1'}, male)));
assert(~any(ismember({'CEMDL', 'R1AL', 'CA1'}, herm)));

% Membership comes from a catalog, including asymmetric and numbered sets.
groups = {'AVA', 'IL1', 'RME', 'SAB', 'ADL', 'OLL', 'AS', 'R1'};
expected = {{'AVAL'; 'AVAR'}, ...
    {'IL1DL'; 'IL1DR'; 'IL1L'; 'IL1R'; 'IL1VL'; 'IL1VR'}, ...
    {'RMED'; 'RMEL'; 'RMER'; 'RMEV'}, ...
    {'SABD'; 'SABVL'; 'SABVR'}, {'ADLL'; 'ADLR'}, {'OLLL'; 'OLLR'}, ...
    arrayfun(@(i) sprintf('AS%d', i), (1:11)', 'UniformOutput', false), ...
    {'R1AL'; 'R1AR'; 'R1BL'; 'R1BR'}};
for i = 1:numel(groups)
    assert(isequal(Annotations.Catalog.members(groups{i}, ''), expected{i}));
end
assert(isempty(Annotations.Catalog.members('R1', 'XX')));
assert(isequal(Annotations.Catalog.members('R1', 'XX', true), expected{end}));
assert(isequal(Annotations.Catalog.members('CA', 'XO'), ...
    arrayfun(@(i) sprintf('CA%d', i), (1:9)', 'UniformOutput', false)));
assert(~any(ismember({'ASEL', 'ASER', 'ASGL'}, Annotations.Catalog.members('AS', 'XO'))));
for token = {'AQR', 'AVL', 'PQR', 'PVR', 'RIR', 'SDQL', 'SDQR'}
    row = Annotations.Catalog.lookup(token{1}, 'XX');
    assert(strcmp(row.kind, 'individual') && isequal(row.candidates, token));
end
for token = {'AQL', 'AVR', 'SABDL', 'IL1V', 'R1C'}
    row = Annotations.Catalog.lookup(token{1}, '');
    assert(strcmp(row.kind, 'unknown'));
end
left = Annotations.Catalog.lookup('IL1DL', 'XX');
assert(strcmp(left.description, 'dorsal left'));
assert(strcmp(left.metadata.laterality, 'L') && strcmp(left.metadata.dorsoventral, 'D'));
single = Annotations.Catalog.lookup('AQR', 'XX');
assert(strcmp(single.metadata.laterality, 'none'));
ray = Annotations.Catalog.lookup('R1AL', 'XO');
assert(strcmp(ray.metadata.subtype, 'A') && strcmp(ray.metadata.laterality, 'L'));
assert(strcmp(Annotations.Catalog.bilateralPartner('AVAL', 'XX'), 'AVAR'));
assert(strcmp(Annotations.Catalog.bilateralPartner('IL1DL', 'XX'), 'IL1DR'));
assert(strcmp(Annotations.Catalog.bilateralPartner('SABVL', 'XX'), 'SABVR'));
assert(strcmp(Annotations.Catalog.bilateralPartner('R1AL', 'XO'), 'R1AR'));
assert(strcmp(Annotations.Catalog.bilateralPartner('SDQL', 'XX'), 'SDQR'));
for token = {'AQR', 'AVL', 'SABD', 'RMED', 'AS1'}
    assert(isempty(Annotations.Catalog.bilateralPartner(token{1}, '')));
end
assert(isempty(Annotations.Catalog.bilateralPartner('R1AL', 'XX')));

% Parsing produces a draft; a class query requires an explicit unresolved action.
draft = Annotations.Catalog.parse('  aval  ', 'XX');
assert(draft.valid && strcmp(draft.kind, 'individual'));
assert(strcmp(draft.token, 'AVAL') && strcmp(draft.review, 'unreviewed'));
assert(strcmp(draft.certainty, 'confident') && isequal(draft.candidates, {'AVAL'}));
draft = Annotations.Catalog.parse('AVAL?!', 'XX');
assert(draft.valid && strcmp(draft.certainty, 'tentative') && draft.attributes.emphasized);
assert(strcmp(Annotations.Catalog.format(draft), 'AVAL?!'));
draft = Annotations.Catalog.parse('AS01', 'XX');
assert(draft.valid && strcmp(draft.token, 'AS1'));
for token = {'AVA', 'AVA?', 'AVA?!', 'IL1', 'RME', 'SAB', 'AS', 'R1'}
    draft = Annotations.Catalog.parse(token{1}, '');
    assert(~draft.valid && strcmp(draft.status, 'ambiguous') && draft.requires_staging);
    staged = Annotations.Catalog.stageGroup(token{1}, '');
    assert(staged.valid && strcmp(staged.kind, 'unresolved_set') && ~staged.requires_staging);
    assert(numel(staged.candidates) > 1 && strcmp(Annotations.Catalog.format(staged), token{1}));
end
draft = Annotations.Catalog.stageGroup('AVA?!', 'XX');
assert(strcmp(draft.certainty, 'tentative') && draft.attributes.emphasized);
draft = Annotations.Catalog.stageGroup('AVAL', 'XX');
assert(draft.valid && strcmp(draft.kind, 'individual'));

% Wrong sex is actionable and cannot be confused with an unknown name.
draft = Annotations.Catalog.parse('CEMDL', 'XX');
assert(~draft.valid && strcmp(draft.status, 'context') && draft.context_exception_required);
draft = Annotations.Catalog.parse('CEMDL', 'XX', true);
assert(draft.valid && draft.context_exception_required && isequal(draft.candidates, {'CEMDL'}));
draft = Annotations.Catalog.parse('CEMDL', 'unknown');
assert(draft.valid && ~draft.context_exception_required);
draft = Annotations.Catalog.stageGroup('R1?', 'XX');
assert(~draft.valid && strcmp(draft.status, 'context'));
draft = Annotations.Catalog.stageGroup('R1?', 'XX', true);
assert(draft.valid && draft.context_exception_required && numel(draft.candidates) == 4);

% Functional state is independent of side and invalid suffixes never truncate.
for token = {'AWCL-ON', 'AWCR-OFF?!'}
    draft = Annotations.Catalog.parse(token{1}, 'XX');
    assert(draft.valid && ~isnan(draft.attributes.on_off));
    assert(strcmp(Annotations.Catalog.format(draft), token{1}));
end
draft = Annotations.Catalog.stageGroup('AWC-ON?', 'XX');
assert(draft.valid && draft.attributes.on_off && strcmp(draft.certainty, 'tentative'));
for token = {'AWCL-GARBAGE', 'AWCL-ON-OFF', 'AVAL!?', 'AVAL??', 'AVAL!!', ...
        '?', '!', 'AWCL -ON', 'AVAL-ON?', 'ARTIFACT-ON', 'AS001'}
    draft = Annotations.Catalog.parse(token{1}, 'XX');
    assert(~draft.valid, token{1});
end
draft = Annotations.Catalog.parse('', 'XX');
assert(~draft.valid && strcmp(draft.status, 'empty'));
draft = Annotations.Catalog.parse('AV', 'XX');
assert(~draft.valid && strcmp(draft.status, 'incomplete'));
draft = Annotations.Catalog.parse('NOTANEURON', 'XX');
assert(~draft.valid && strcmp(draft.status, 'unknown'));
for token = {'ARTIFACT', 'MUTATION', 'AMSOL', 'HMC', 'PHSO1R'}
    draft = Annotations.Catalog.parse(token{1}, 'XX');
    assert(draft.valid && strcmp(draft.kind, 'classification') && isempty(draft.candidates));
end

% A model class uses its own pinned vocabulary, never a matching family label.
[members, mapping] = Annotations.Catalog.modelMembers('gat-20260601-v1', 'IL1');
assert(mapping.available && isequal(members, expected{2}));
assert(isequal(members, Annotations.Catalog.modelMembers('gat-20260601-v1', 'IL1', mapping.vocabulary_version)));
assert(isempty(Annotations.Catalog.modelMembers('gat-20260601-v1', 'IL1', 'other-vocabulary')));
assert(isempty(Annotations.Catalog.modelMembers('unknown-bundle', 'IL1')));
assert(isempty(Annotations.Catalog.modelMembers('gat-20260601-v1', 'CAN')));
assert(isempty(Annotations.Catalog.modelMembers('gat-20260601-v1', 'CEM')));
assert(isequal(Annotations.Catalog.modelMembers('gat-20260601-v1', 'AS'), expected{7}));
assert(strcmp(Annotations.Catalog.version(), 'neuropal-individuals-20261015-v1'));
fprintf('ANNOTATION_CATALOG_CONTEXT_GROUPS_STRICT_PARSER=PASS\n');
end
