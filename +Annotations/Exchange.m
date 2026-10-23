classdef Exchange
    %EXCHANGE Transfer structured identities without selecting unresolved members.
    methods (Static)
        function report = export(path, store, neurons)
            Annotations.Store.validate(store);
            if nargin < 3, projection = Annotations.Store.project(store);
            else, projection = Annotations.Store.project(store, neurons); end
            path = char(string(path));
            [folder, ~, extension] = fileparts(path);
            if isempty(folder), folder = pwd; path = fullfile(folder, path); end
            if exist(folder, 'dir') ~= 7
                error('Annotations:ExchangeFolder', 'The export destination directory does not exist.');
            end
            report = Annotations.Exchange.report(store, projection);
            report.path = path;
            if strcmpi(extension, '.csv')
                report.format = 'NeuroPAL.IdentitySummary/1';
                report.full_fidelity = false;
                report.omitted_fields = {'embedded model evidence', 'annotation history', ...
                    'catalog manifest', 'full typed store and context'};
                report.warnings{end+1} = 'CSV is a summary. Use the structured MAT export for a full round trip.';
                Annotations.Exchange.writeCSV(path, store, projection, report);
                return;
            end
            if ~strcmpi(extension, '.mat')
                error('Annotations:ExchangeFormat', 'Use .mat for a full identity exchange or .csv for a declared summary.');
            end

            manifest = Annotations.Catalog.manifest();
            payload = struct('created_utc', char(datetime('now', 'TimeZone', 'UTC', ...
                'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")), ...
                'annotation_store', store, 'catalog_manifest', manifest, ...
                'legacy_projection', projection, 'report', report);
            identity_exchange = struct('format', 'NeuroPAL.IdentityExchange', ...
                'schema_version', 1, 'hash_algorithm', 'sha256-canonical-matlab-v1', ...
                'payload_sha256', Annotations.Exchange.hash(payload), 'payload', payload);
            temporary = [tempname(folder) '.mat'];
            cleanup = onCleanup(@() Annotations.Exchange.remove(temporary));
            save(temporary, 'identity_exchange', '-v7.3');
            [verified, verifyReport] = Annotations.Exchange.read(temporary);
            if ~isequaln(verified, store) || ~verifyReport.integrity_verified
                error('Annotations:ExchangeVerification', 'The exported annotation store did not round-trip.');
            end
            Annotations.Exchange.atomicMove(temporary, path);
            report.integrity_verified = true;
            report.payload_sha256 = identity_exchange.payload_sha256;
        end

        function [store, report] = read(path)
            path = char(string(path));
            variables = whos('-file', path);
            match = find(strcmp({variables.name}, 'identity_exchange'), 1);
            if isempty(match) || ~strcmp(variables(match).class, 'struct') || ...
                    ~isequal(variables(match).size, [1 1])
                error('Annotations:ExchangeFormat', 'Choose a structured NeuroPAL identity exchange MAT file.');
            end
            loaded = load(path, 'identity_exchange');
            envelope = loaded.identity_exchange;
            required = {'format', 'schema_version', 'hash_algorithm', 'payload_sha256', 'payload'};
            if ~isscalar(envelope) || ~all(isfield(envelope, required)) || ...
                    ~strcmp(envelope.format, 'NeuroPAL.IdentityExchange') || ...
                    ~isequal(envelope.schema_version, 1) || ...
                    ~strcmp(envelope.hash_algorithm, 'sha256-canonical-matlab-v1')
                error('Annotations:ExchangeFormat', 'The identity exchange format or version is unsupported.');
            end
            if ~strcmp(envelope.payload_sha256, Annotations.Exchange.hash(envelope.payload))
                error('Annotations:ExchangeIntegrity', 'The identity exchange failed its content integrity check.');
            end
            payload = envelope.payload;
            required = {'annotation_store', 'catalog_manifest', 'legacy_projection', 'report'};
            if ~isstruct(payload) || ~isscalar(payload) || ~all(isfield(payload, required))
                error('Annotations:ExchangeFormat', 'The identity exchange is missing structured annotation data.');
            end
            store = payload.annotation_store;
            Annotations.Store.validate(store);
            report = Annotations.Exchange.report(store, payload.legacy_projection);
            report.path = path; report.integrity_verified = true;
            report.payload_sha256 = envelope.payload_sha256;
            report.catalog_compatible = isfield(payload.catalog_manifest, 'version') && ...
                strcmp(payload.catalog_manifest.version, store.catalog_version) && ...
                strcmp(store.catalog_version, Annotations.Catalog.version());
            if ~report.catalog_compatible
                report.warnings{end+1} = 'The exchange catalog differs from this app. Review catalog compatibility before applying identities.';
            end
            % Returning a store never associates it with a different image by row.
        end
    end

    methods (Static, Access = private)
        function report = report(store, projection)
            lossy = false(1, numel(projection));
            if ~isempty(projection), lossy = [projection.lossy]; end
            ids = {store.evidence.evidence_id}; missing = cell(0, 1);
            for i = 1:numel(store.records)
                requested = cellstr(string(store.records(i).model_evidence_ids(:)));
                missing = [missing; requested(~ismember(requested, ids))];
            end
            external = cell(0, 1); legacy = cell(0, 1);
            for i = 1:numel(store.evidence)
                row = store.evidence(i);
                external = [external; Annotations.Exchange.references(row.values, row.evidence_id)];
                if contains(lower(row.origin), 'legacy') || contains(lower(row.originality), 'unverified')
                    legacy{end+1, 1} = row.evidence_id;
                end
            end
            report = struct('format', 'NeuroPAL.IdentityExchange/1', 'full_fidelity', true, ...
                'integrity_verified', false, 'source_id', store.source_id, ...
                'catalog_version', store.catalog_version, 'owner_count', numel(store.owners), ...
                'record_count', numel(store.records), 'evidence_count', numel(store.evidence), ...
                'event_count', numel(store.journal), 'missing_evidence_ids', {unique(missing)}, ...
                'external_evidence_references', {unique(external)}, ...
                'evidence_complete', isempty(missing) && isempty(external), ...
                'unverified_legacy_evidence_ids', {legacy}, ...
                'original_model_evidence_verified', ~isempty(store.evidence) && isempty(legacy) && isempty(missing) && isempty(external), ...
                'legacy_lossy_owner_ids', {{projection(lossy).annotation_id}}, ...
                'legacy_omitted_fields', {{'structured ambiguity', 'certainty and review semantics', ...
                    'stable ownership', 'provenance and exceptions', 'history', 'model evidence'}}, ...
                'omitted_fields', {{}}, 'warnings', {{}});
            if ~report.evidence_complete
                report.warnings{end+1} = 'Some model evidence is missing or externally referenced; complete portable model evidence is not claimed.';
            end
            if ~isempty(legacy)
                report.warnings{end+1} = 'Legacy model snapshots are preserved exactly; their originality cannot be reconstructed or guaranteed.';
            end
            if ~strcmp(store.catalog_version, Annotations.Catalog.version())
                report.warnings{end+1} = 'The current catalog manifest does not establish the meaning of every saved catalog version.';
            end
        end

        function references = references(value, prefix)
            references = cell(0, 1);
            if isstruct(value)
                fields = fieldnames(value);
                for i = 1:numel(value)
                    for j = 1:numel(fields)
                        key = fields{j}; next = value(i).(key);
                        label = sprintf('%s.%s', prefix, key);
                        pathField = any(strcmpi(key, {'path', 'file', 'uri', 'url', 'reference', 'references'})) || ...
                            endsWith(lower(key), {'_path', '_file', '_uri', '_url', '_reference', '_references'});
                        if pathField && ~isempty(next) && (ischar(next) || isstring(next) || iscellstr(next))
                            if ischar(next), paths = string(next);
                            else, paths = string(next(:)); end
                            references{end+1, 1} = [label ': ' char(strjoin(paths, ', '))];
                        else
                            references = [references; Annotations.Exchange.references(next, label)];
                        end
                    end
                end
            elseif iscell(value)
                for i = 1:numel(value)
                    references = [references; Annotations.Exchange.references(value{i}, sprintf('%s{%d}', prefix, i))];
                end
            end
        end

        function writeCSV(path, store, projection, report)
            folder = fileparts(path); temporary = [tempname(folder) '.csv'];
            cleanup = onCleanup(@() Annotations.Exchange.remove(temporary));
            fid = fopen(temporary, 'w', 'n', 'UTF-8');
            if fid < 0, error('Annotations:ExchangeWrite', 'Cannot write the identity summary.'); end
            stream = onCleanup(@() fclose(fid));
            headers = {'format', 'source_id', 'specimen_id', 'scope_id', 'owner_id', 'record_id', ...
                'revision', 'catalog_version', 'kind', 'candidates_json', 'group', 'classification', ...
                'certainty', 'review', 'on_off', 'emphasized', 'notes', 'context_exception_reason', ...
                'provenance_json', 'model_evidence_ids_json', 'constraint_policy', 'issue', ...
                'conflicts_json', 'legacy_annotation', 'legacy_lossy', 'omitted_fields_json'};
            Annotations.Exchange.csvRow(fid, headers);
            for i = 1:numel(store.records)
                row = store.records(i);
                owner = store.owners(strcmp({store.owners.owner_id}, row.owner_id));
                p = projection(strcmp({projection.annotation_id}, row.owner_id));
                legacy = ''; lossy = 'true';
                if ~isempty(p), legacy = p.annotation; lossy = Annotations.Exchange.bool(p.lossy); end
                state = 'unknown';
                if ~isnan(row.attributes.on_off)
                    if row.attributes.on_off, state = 'ON'; else, state = 'OFF'; end
                end
                classification = '';
                if isfield(row, 'classification_token'), classification = row.classification_token; end
                values = {report.format, owner.source_id, store.specimen_id, owner.scope_id, ...
                    row.owner_id, row.record_id, sprintf('%d', row.revision), row.catalog_version, ...
                    row.kind, jsonencode(row.candidates), row.group, classification, row.certainty, ...
                    row.review, state, Annotations.Exchange.bool(row.attributes.emphasized), ...
                    row.attributes.notes, row.context_exception_reason, jsonencode(row.provenance), ...
                    jsonencode(row.model_evidence_ids), row.constraint_policy, row.issue, ...
                    jsonencode(row.conflicts), legacy, lossy, jsonencode(report.omitted_fields)};
                Annotations.Exchange.csvRow(fid, values);
            end
            clear stream;
            Annotations.Exchange.atomicMove(temporary, path);
        end

        function csvRow(fid, values)
            quoted = cell(size(values));
            for i = 1:numel(values)
                value = char(string(values{i}));
                quoted{i} = ['"' strrep(value, '"', '""') '"'];
            end
            fprintf(fid, '%s\n', strjoin(quoted, ','));
        end

        function value = bool(value)
            if value, value = 'true'; else, value = 'false'; end
        end

        function value = hash(value)
            digest = java.security.MessageDigest.getInstance('SHA-256');
            Annotations.Exchange.digestValue(digest, value);
            value = lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
        end

        function digestValue(digest, value)
            % Typed dimensions and exact numeric bytes keep NaN distinct from Inf.
            type = class(value);
            allowed = {'struct', 'cell', 'char', 'string', 'logical', 'double', 'single', ...
                'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'};
            if ~any(strcmp(type, allowed))
                error('Annotations:ExchangeType', 'Identity exchanges contain plain data, not %s objects.', type);
            end
            Annotations.Exchange.bytes(digest, uint8(type));
            Annotations.Exchange.bytes(digest, uint8(sprintf('%d,', size(value))));
            if isstruct(value)
                fields = sort(fieldnames(value));
                Annotations.Exchange.bytes(digest, uint8(sprintf('%d', numel(fields))));
                for j = 1:numel(fields)
                    Annotations.Exchange.bytes(digest, uint8(fields{j}));
                end
                for i = 1:numel(value)
                    for j = 1:numel(fields)
                        Annotations.Exchange.digestValue(digest, value(i).(fields{j}));
                    end
                end
            elseif iscell(value)
                for i = 1:numel(value), Annotations.Exchange.digestValue(digest, value{i}); end
            elseif isstring(value)
                for i = 1:numel(value)
                    Annotations.Exchange.bytes(digest, uint8(ismissing(value(i))));
                    if ~ismissing(value(i)), Annotations.Exchange.digestValue(digest, char(value(i))); end
                end
            elseif ischar(value)
                Annotations.Exchange.numericBytes(digest, uint16(value(:)));
            elseif issparse(value)
                Annotations.Exchange.bytes(digest, uint8('sparse'));
                [rows, columns, values] = find(value);
                Annotations.Exchange.digestValue(digest, rows);
                Annotations.Exchange.digestValue(digest, columns);
                Annotations.Exchange.digestValue(digest, values);
            elseif islogical(value)
                Annotations.Exchange.bytes(digest, uint8(value(:)));
            else
                Annotations.Exchange.bytes(digest, uint8(isreal(value)));
                Annotations.Exchange.numericBytes(digest, real(value(:)));
                if ~isreal(value), Annotations.Exchange.numericBytes(digest, imag(value(:))); end
            end
        end

        function numericBytes(digest, value)
            [~, ~, endian] = computer;
            if endian == 'B', value = swapbytes(value); end
            Annotations.Exchange.bytes(digest, typecast(value(:), 'uint8'));
        end

        function bytes(digest, value)
            value = uint8(value(:));
            digest.update(typecast(uint8(sprintf('%d:', numel(value))), 'int8'));
            if ~isempty(value), digest.update(typecast(value, 'int8')); end
        end

        function atomicMove(source, destination)
            options = javaArray('java.nio.file.CopyOption', 2);
            options(1) = java.nio.file.StandardCopyOption.ATOMIC_MOVE;
            options(2) = java.nio.file.StandardCopyOption.REPLACE_EXISTING;
            try
                java.nio.file.Files.move(java.io.File(source).toPath(), java.io.File(destination).toPath(), options);
            catch ME
                error('Annotations:ExchangeWrite', 'Cannot atomically publish the export: %s', ME.message);
            end
        end

        function remove(path)
            if exist(path, 'file') == 2, delete(path); end
        end
    end
end
