classdef Catalog
    %CATALOG Resolve exact atlas identities without inferring anatomical sides.
    methods (Static)
        function value = version()
            data = Annotations.Catalog.data();
            value = data.version;
        end

        function value = manifest()
            value = Annotations.Catalog.data();
        end

        function names = names(sex, allNames)
            if nargin < 1, sex = ''; end
            if nargin < 2, allNames = false; end
            index = Annotations.Catalog.index();
            sex = Annotations.Catalog.normalizeSex(sex);
            if allNames || isempty(sex), names = index.allNames;
            else, names = index.(sex); end
        end

        function groups = groups(sex, allNames)
            if nargin < 1, sex = ''; end
            if nargin < 2, allNames = false; end
            data = Annotations.Catalog.data();
            allowed = Annotations.Catalog.names(sex, allNames);
            groups = struct('token', {}, 'members', {}, 'applicable', {}, ...
                'description', {}, 'sexes', {});
            for i = 1:numel(data.groups)
                row = data.groups(i);
                members = Annotations.Catalog.cells(row.members);
                members = members(ismember(members, allowed));
                if numel(members) < 2, continue; end
                info = Annotations.Catalog.lookup(row.token, sex);
                groups(end+1) = struct('token', row.token, ...
                    'members', {members}, 'applicable', info.applicable, ...
                    'description', info.description, 'sexes', {info.sexes});
            end
        end

        function names = members(token, sex, allNames)
            if nargin < 2, sex = ''; end
            if nargin < 3, allNames = false; end
            info = Annotations.Catalog.lookup(token, sex);
            names = info.candidates;
            if ~allNames
                allowed = Annotations.Catalog.names(sex);
                names = names(ismember(names, allowed));
            end
        end

        function info = lookup(token, sex)
            if nargin < 2, sex = ''; end
            token = Annotations.Catalog.text(token);
            data = Annotations.Catalog.data();
            index = Annotations.Catalog.index();
            info = struct('kind', 'unknown', 'token', token, ...
                'candidates', {cell(0, 1)}, 'applicable', false, ...
                'sexes', {cell(0, 1)}, 'description', '', 'group', '', ...
                'catalog_version', data.version, 'metadata', struct());
            if isempty(token), return; end

            % Canonical individuals and explicit aliases take precedence.
            if isKey(index.individuals, token)
                row = data.individuals(index.individuals(token));
                info.kind = 'individual';
                info.token = row.name;
                info.candidates = {row.name};
                info.sexes = Annotations.Catalog.cells(row.sexes);
                info.applicable = Annotations.Catalog.applies(row.sexes, sex);
                info.description = row.description;
                info.group = row.group;
                info.metadata = row;
                return;
            end
            if isKey(index.classifications, token)
                row = data.classifications(index.classifications(token));
                info.kind = 'classification';
                info.applicable = true;
                info.description = row.description;
                return;
            end
            if isKey(index.groups, token)
                rowIndex = index.groups(token);
                row = data.groups(rowIndex);
                info.kind = 'group'; info.group = row.token;
                info.candidates = index.groupMembers{rowIndex};
                info.description = 'individual member unresolved';
                info.sexes = index.groupSexes{rowIndex};
                info.applicable = Annotations.Catalog.applies(info.sexes, sex);
            end
        end

        function draft = parse(text, sex, allowAll)
            if nargin < 2, sex = ''; end
            if nargin < 3, allowAll = false; end
            raw = Annotations.Catalog.rawText(text);
            value = Annotations.Catalog.text(text);
            draft = struct('valid', false, 'status', 'empty', 'message', '', ...
                'kind', 'unassigned', 'candidates', {cell(0, 1)}, ...
                'certainty', 'confident', 'review', 'unreviewed', ...
                'attributes', struct('on_off', NaN, 'emphasized', false), ...
                'group', '', 'token', '', 'raw', raw, ...
                'catalog_version', Annotations.Catalog.version(), ...
                'requires_staging', false, 'context_exception_required', false);
            if isempty(value)
                draft.message = 'Enter an individual neuron name or choose a group.';
                return;
            end
            parts = regexp(value, ...
                '^(?<token>[A-Z][A-Z0-9]*)(?<state>-ON|-OFF)?(?<tentative>\?)?(?<emphasized>!)?$', ...
                'names', 'once');
            if isempty(parts)
                draft.kind = 'unknown'; draft.status = 'malformed';
                draft.message = 'Use a name, optional -ON/-OFF, then optional ? and !.';
                return;
            end
            info = Annotations.Catalog.lookup(parts.token, sex);
            draft.token = info.token;
            if ~isempty(parts.tentative), draft.certainty = 'tentative'; end
            draft.attributes.emphasized = ~isempty(parts.emphasized);
            if ~isempty(parts.state)
                draft.attributes.on_off = strcmp(parts.state, '-ON');
            end
            if strcmp(info.kind, 'unknown')
                draft.kind = 'unknown'; draft.status = 'unknown';
                draft.message = 'Choose an exact individual or catalog group.';
                index = Annotations.Catalog.index();
                if any(startsWith(index.searchTokens, parts.token))
                    draft.status = 'incomplete';
                    draft.message = 'Continue typing or choose a matching name.';
                end
                return;
            end
            draft.kind = info.kind;
            draft.candidates = info.candidates;
            if strcmp(info.kind, 'group')
                draft.kind = 'unresolved_set'; draft.group = info.token;
                draft.requires_staging = true;
                if info.applicable && ~allowAll
                    draft.candidates = Annotations.Catalog.members(info.token, sex);
                end
            end
            if ~isnan(draft.attributes.on_off)
                permitted = ~isempty(draft.candidates);
                for i = 1:numel(draft.candidates)
                    candidate = Annotations.Catalog.lookup(draft.candidates{i}, sex);
                    permitted = permitted && candidate.metadata.on_off_allowed;
                end
                if ~permitted
                    draft.status = 'attribute';
                    draft.message = 'ON/OFF is available only for AWC identities.';
                    return;
                end
            end
            draft.context_exception_required = ~info.applicable;
            if draft.context_exception_required && ~allowAll
                draft.status = 'context';
                draft.message = 'This identity is outside the selected sex. Use All atlas names to request an exception.';
                return;
            end
            if draft.requires_staging
                draft.status = 'ambiguous';
                draft.message = 'Choose an individual, or explicitly keep the complete group unresolved.';
                return;
            end
            draft.valid = true; draft.status = 'ready';
        end

        function draft = stageGroup(text, sex, allowAll)
            if nargin < 2, sex = ''; end
            if nargin < 3, allowAll = false; end
            draft = Annotations.Catalog.parse(text, sex, allowAll);
            if ~strcmp(draft.status, 'ambiguous'), return; end
            if numel(draft.candidates) < 2
                draft.status = 'invalid_group';
                draft.message = 'The catalog group does not contain multiple valid individuals.';
                return;
            end
            draft.valid = true; draft.status = 'ready';
            draft.requires_staging = false; draft.message = '';
        end

        function value = format(draft)
            value = draft.token;
            if isfield(draft, 'group') && strcmp(draft.kind, 'unresolved_set')
                value = draft.group;
            end
            if ~isnan(draft.attributes.on_off)
                if draft.attributes.on_off, value = [value '-ON'];
                else, value = [value '-OFF']; end
            end
            if strcmp(draft.certainty, 'tentative'), value = [value '?']; end
            if draft.attributes.emphasized, value = [value '!']; end
        end

        function partner = bilateralPartner(name, sex)
            if nargin < 2, sex = ''; end
            partner = '';
            info = Annotations.Catalog.lookup(name, sex);
            if ~strcmp(info.kind, 'individual') || ~info.applicable, return; end
            candidate = info.metadata.bilateral_partner;
            if isempty(candidate), return; end
            other = Annotations.Catalog.lookup(candidate, sex);
            if other.applicable, partner = other.token; end
        end

        function [members, info] = modelMembers(bundleId, token, vocabulary)
            if nargin < 3, vocabulary = ''; end
            members = cell(0, 1);
            info = struct('available', false, 'bundle_id', '', ...
                'vocabulary_version', '', 'class_token', '', 'source_sha256', '');
            data = Annotations.Catalog.data();
            for i = 1:numel(data.model_mappings)
                mapping = data.model_mappings(i);
                if ~strcmp(char(string(bundleId)), mapping.bundle_id), continue; end
                if ~isempty(vocabulary) && ~strcmp(vocabulary, mapping.vocabulary_version), return; end
                token = Annotations.Catalog.text(token);
                for j = 1:numel(mapping.classes)
                    if ~strcmp(token, mapping.classes(j).token), continue; end
                    members = Annotations.Catalog.cells(mapping.classes(j).members);
                    info = struct('available', true, 'bundle_id', mapping.bundle_id, ...
                        'vocabulary_version', mapping.vocabulary_version, ...
                        'class_token', token, 'source_sha256', mapping.source_sha256);
                    return;
                end
            end
        end

        function value = normalizeSex(sex)
            value = Annotations.Catalog.text(sex);
            if any(strcmp(value, {'XX', 'HERMAPHRODITE'})), value = 'XX';
            elseif any(strcmp(value, {'XO', 'MALE'})), value = 'XO';
            else, value = ''; end
        end
    end

    methods (Static, Access = private)
        function index = index()
            persistent cached;
            if isempty(cached)
                data = Annotations.Catalog.data();
                cached = struct('individuals', containers.Map('KeyType', 'char', 'ValueType', 'double'), ...
                    'groups', containers.Map('KeyType', 'char', 'ValueType', 'double'), ...
                    'classifications', containers.Map('KeyType', 'char', 'ValueType', 'double'), ...
                    'allNames', {cell(0, 1)}, 'XX', {cell(0, 1)}, 'XO', {cell(0, 1)}, ...
                    'groupMembers', {cell(numel(data.groups), 1)}, ...
                    'groupSexes', {cell(numel(data.groups), 1)}, 'searchTokens', {cell(0, 1)});
                for i = 1:numel(data.individuals)
                    row = data.individuals(i);
                    tokens = [{row.name}; Annotations.Catalog.cells(row.aliases)];
                    for j = 1:numel(tokens)
                        assert(~isKey(cached.individuals, tokens{j}), ...
                            'Annotations:CatalogInvalid', 'Catalog aliases must resolve to one individual.');
                        cached.individuals(tokens{j}) = i;
                    end
                    cached.allNames{end+1, 1} = row.name;
                    if Annotations.Catalog.applies(row.sexes, 'XX'), cached.XX{end+1, 1} = row.name; end
                    if Annotations.Catalog.applies(row.sexes, 'XO'), cached.XO{end+1, 1} = row.name; end
                    cached.searchTokens = [cached.searchTokens; tokens];
                end
                for i = 1:numel(data.classifications)
                    cached.classifications(data.classifications(i).name) = i;
                end
                for i = 1:numel(data.groups)
                    row = data.groups(i);
                    assert(~isKey(cached.groups, row.token), ...
                        'Annotations:CatalogInvalid', 'Catalog group tokens must be unique.');
                    cached.groups(row.token) = i;
                    cached.groupMembers{i} = Annotations.Catalog.cells(row.members);
                    sexes = cell(0, 1);
                    for j = 1:numel(cached.groupMembers{i})
                        member = data.individuals(cached.individuals(cached.groupMembers{i}{j}));
                        sexes = union(sexes, Annotations.Catalog.cells(member.sexes), 'stable');
                    end
                    cached.groupSexes{i} = sexes;
                    cached.searchTokens{end+1, 1} = row.token;
                end
            end
            index = cached;
        end

        function data = data()
            persistent catalog;
            if isempty(catalog)
                path = fullfile(fileparts(mfilename('fullpath')), 'catalog_v1.json');
                catalog = jsondecode(fileread(path));
                names = {catalog.individuals.name};
                assert(numel(names) == numel(unique(names)), ...
                    'Annotations:CatalogInvalid', 'Catalog individual names must be unique.');
                for i = 1:numel(catalog.groups)
                    members = Annotations.Catalog.cells(catalog.groups(i).members);
                    assert(all(ismember(members, names)) && numel(members) == numel(unique(members)), ...
                        'Annotations:CatalogInvalid', 'Catalog groups must contain exact unique individuals.');
                end
                for i = 1:numel(catalog.individuals)
                    row = catalog.individuals(i);
                    if isempty(row.bilateral_partner), continue; end
                    index = find(strcmp(names, row.bilateral_partner), 1);
                    assert(~isempty(index) && strcmp(catalog.individuals(index).bilateral_partner, row.name), ...
                        'Annotations:CatalogInvalid', 'Bilateral catalog links must be reciprocal.');
                end
            end
            data = catalog;
        end

        function value = applies(sexes, sex)
            sex = Annotations.Catalog.normalizeSex(sex);
            value = isempty(sex) || any(strcmp(Annotations.Catalog.cells(sexes), sex));
        end

        function value = cells(value)
            if isempty(value), value = cell(0, 1);
            else, value = cellstr(string(value(:))); end
        end

        function value = text(value)
            value = upper(strtrim(Annotations.Catalog.rawText(value)));
        end

        function value = rawText(value)
            if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
                    ~(isstring(value) && isscalar(value) && ~ismissing(value))
                value = '';
                return;
            end
            value = char(value);
        end
    end
end
