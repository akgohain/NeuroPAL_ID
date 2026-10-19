classdef Store
    %STORE Keep human identities independent of model evidence.
    methods (Static)
        function [store, owners] = create(neurons, context)
            if nargin < 2, context = struct(); end
            if isa(neurons, 'Neurons.Image'), neurons = neurons.neurons; end
            source = Annotations.Store.text(context, 'source_id', Annotations.Store.uuid());
            specimen = Annotations.Store.text(context, 'specimen_id', '');
            scope = specimen;
            if isempty(scope), scope = ['acquisition:' source]; end
            store = struct('schema_version', 2, 'revision', 0, 'generation', 0, ...
                'source_id', source, 'specimen_id', specimen, 'scope_id', scope, ...
                'catalog_version', Annotations.Catalog.version(), 'context', context, ...
                'constraints_enabled', false, 'owners', repmat(Annotations.Store.owner(), 1, 0), ...
                'records', repmat(Annotations.Store.emptyRecord(''), 1, 0), ...
                'evidence', repmat(Annotations.Store.emptyEvidence(), 1, 0), ...
                'journal', repmat(Annotations.Store.emptyEvent(), 1, 0), ...
                'imported_histories', {{}}, 'context_history', {{}}, ...
                'migration_issues', struct('owner_id', {}, 'message', {}, 'raw', {}));
            owners = cell(1, numel(neurons));
            for i = 1:numel(neurons)
                id = Annotations.Store.text(neurons(i), 'annotation_id', '');
                if isempty(id), id = Annotations.Store.uuid(); end
                owners{i} = id;
                item = Annotations.Store.owner();
                item.owner_id = id; item.source_id = source; item.scope_id = scope;
                item.geometry_revision = Annotations.Store.text(context, 'geometry_revision', '');
                store.owners(end + 1) = item;
                evidence = Annotations.Store.emptyEvidence();
                evidence.evidence_id = Annotations.Store.uuid(); evidence.owner_id = id;
                evidence.source_id = source; evidence.origin = 'legacy-model-snapshot';
                evidence.originality = 'unverified legacy snapshot; earlier manual edits may have overwritten predictions';
                fields = {'deterministic_id','probabilistic_ids','probabilistic_probs','rank'};
                for j = 1:numel(fields)
                    evidence.values.(fields{j}) = Annotations.Store.value(neurons(i), fields{j}, []);
                end
                evidence.sha256 = Annotations.Store.hashValue(evidence.values);
                store.evidence(end + 1) = evidence;
                record = Annotations.Store.emptyRecord(id);
                record.catalog_version = store.catalog_version;
                record.model_evidence_ids = {evidence.evidence_id};
                raw = Annotations.Store.text(neurons(i), 'annotation', '');
                if ~isempty(strtrim(raw))
                    sex = Annotations.Store.text(context, 'sex', '');
                    parsed = Annotations.Catalog.parse(raw, sex, true);
                    if parsed.valid || (strcmp(parsed.kind, 'unresolved_set') && strcmp(parsed.status,'ambiguous'))
                        record = Annotations.Store.fromDraft(record, parsed, struct());
                        record.review = 'legacy-reviewed';
                        confidence = Annotations.Store.value(neurons(i), 'annotation_confidence', -1);
                        if isscalar(confidence) && isfinite(confidence) && confidence == 1
                            record.certainty = 'confident';
                        elseif isscalar(confidence) && isfinite(confidence) && confidence == 0.5
                            record.certainty = 'tentative';
                        else
                            record.certainty = 'unspecified';
                        end
                        legacy_state = Annotations.Store.value(neurons(i), 'is_annotation_on', NaN);
                        if ~isnan(legacy_state), record.attributes.on_off = legacy_state; end
                        record.attributes.emphasized = logical(Annotations.Store.value(neurons(i), 'is_emphasized', false));
                        if Annotations.Store.value(parsed, 'context_exception_required', false)
                            record.issue = 'Legacy identity conflicts with specimen context.';
                            record.review = 'needs-review';
                        end
                        record.provenance = struct('source', 'legacy-human-annotation', ...
                            'author', '', 'time', '', 'reason', '', 'raw', raw);
                    else
                        record.kind = 'legacy_issue'; record.issue = parsed.message;
                        record.review = 'needs-review';
                        record.provenance.raw = raw;
                    end
                end
                store.records(end + 1) = record;
            end
            % Imported duplicate bindings are issues; no arbitrary owner wins.
            for i = 1:numel(store.records)
                r = store.records(i);
                if ~Annotations.Store.confirmed(r), continue; end
                indices = find(arrayfun(@(x) Annotations.Store.confirmed(x) && ...
                    strcmp(x.candidates{1}, r.candidates{1}), store.records));
                if numel(indices) > 1
                    for j = indices
                        store.records(j).issue = 'Conflicting legacy duplicate individual binding.';
                        store.records(j).review = 'needs-review';
                    end
                end
            end
            for i = 1:numel(store.records)
                r = store.records(i);
                if ~isempty(r.issue)
                    store.migration_issues(end + 1) = struct('owner_id', r.owner_id, ...
                        'message', r.issue, 'raw', r.provenance.raw);
                end
            end
            Annotations.Store.validate(store);
        end

        function record = record(store, ownerId)
            index = find(strcmp({store.records.owner_id}, char(string(ownerId))), 1);
            if isempty(index), error('Annotations:UnknownOwner', 'The annotation target no longer exists.'); end
            record = store.records(index);
        end

        function yes = reviewed(record)
            yes = any(strcmp(record.review, {'reviewed', 'legacy-reviewed'}));
        end

        function yes = confirmed(record)
            yes = strcmp(record.kind, 'individual') && numel(record.candidates) == 1 && ...
                strcmp(record.certainty, 'confident') && Annotations.Store.reviewed(record) && isempty(record.issue);
        end

        function value = display(record)
            value = '';
            if strcmp(record.kind, 'legacy_issue'), value = record.provenance.raw; return; end
            if strcmp(record.kind, 'unresolved_set')
                value = record.group;
                if isempty(value), value = strjoin(record.candidates, '/'); end
                value = [value ' (unresolved)'];
            elseif ~isempty(record.candidates)
                value = record.candidates{1};
            elseif strcmp(record.kind,'classification')
                value = record.classification_token;
            end
            if isempty(value), return; end
            if isequal(record.attributes.on_off, true) || isequal(record.attributes.on_off, 1)
                value = [value '-ON'];
            elseif isequal(record.attributes.on_off, false) || isequal(record.attributes.on_off, 0)
                value = [value '-OFF'];
            end
            if ~strcmp(record.certainty, 'confident'), value = [value '?']; end
            if record.attributes.emphasized, value = [value '!']; end
        end

        function id = occupant(store, candidate, scope, exclude)
            if nargin < 3 || isempty(scope), scope = store.scope_id; end
            if nargin < 4, exclude = ''; end
            id = '';
            for i = 1:numel(store.records)
                r = store.records(i);
                owner = store.owners(strcmp({store.owners.owner_id}, r.owner_id));
                if Annotations.Store.confirmed(r) && strcmp(owner.scope_id, scope) && ...
                        strcmp(r.candidates{1}, char(string(candidate))) && ~strcmp(r.owner_id, exclude)
                    id = r.owner_id; return;
                end
            end
        end

        function [next, event] = command(store, ownerId, draft, action, options)
            if nargin < 4 || isempty(action), action = 'assign'; end
            if nargin < 5, options = struct(); end
            Annotations.Store.validate(store);
            ownerId = char(string(ownerId)); action = lower(char(string(action)));
            operation = Annotations.Store.text(options, 'operation_id', Annotations.Store.uuid());
            previous = find(strcmp({store.journal.operation_id}, operation), 1);
            if ~isempty(previous)
                next = store; event = store.journal(previous); event.changed = false; event.replayed = true; return;
            end
            current = Annotations.Store.record(store, ownerId);
            Annotations.Store.checkRevision(store, current, options);
            next = store; event = Annotations.Store.emptyEvent();
            event.operation_id = operation; event.action = action; event.owner_ids = {ownerId};
            event.before = current;
            if strcmp(action, 'cancel')
                event.changed = false; return;
            elseif strcmp(action, 'clear')
                Annotations.Store.requireConfirmation(options);
                result = Annotations.Store.emptyRecord(ownerId);
                result.catalog_version = current.catalog_version;
                result.model_evidence_ids = current.model_evidence_ids;
                result.attributes.notes = current.attributes.notes;
            else
                result = Annotations.Store.fromDraft(current, draft, options);
                result.review = 'reviewed'; result.issue = '';
                Annotations.Store.validateDraft(result, draft, store, options);
                conflict = '';
                if Annotations.Store.confirmed(result)
                    conflict = Annotations.Store.occupant(store, result.candidates{1}, [], ownerId);
                end
                if any(strcmp(action, {'move', 'swap'}))
                    Annotations.Store.requireConfirmation(options);
                    if isempty(conflict), error('Annotations:ConflictChanged', 'The previous identity owner changed. Reopen the conflict action.'); end
                    expected = Annotations.Store.text(options, 'conflict_owner', conflict);
                    if ~strcmp(expected, conflict), error('Annotations:ConflictChanged', 'The previous identity owner changed.'); end
                    other = Annotations.Store.record(store, conflict);
                    if strcmp(action, 'swap')
                        if ~Annotations.Store.confirmed(current)
                            error('Annotations:InvalidSwap', 'Swap requires two confirmed individual identities.');
                        end
                        replacement = other;
                        replacement.kind = 'individual'; replacement.candidates = current.candidates;
                        replacement.group = ''; replacement.certainty = 'confident'; replacement.review = 'reviewed';
                        replacement.constraint_policy = 'off'; replacement.issue = ''; replacement.conflicts = {};
                        if ~isnan(other.attributes.on_off) && ~any(ismember(current.candidates,{'AWCL','AWCR'}))
                            if ~Annotations.Store.value(options,'resolve_attributes',false)
                                error('Annotations:Attributes','Resolve the other owner''s incompatible AWC state before swapping identities.');
                            end
                            replacement.attributes.on_off = NaN;
                        end
                        replacement.provenance = Annotations.Store.provenance(options, 'manual');
                    else
                        replacement = Annotations.Store.emptyRecord(conflict);
                        replacement.catalog_version = other.catalog_version;
                        replacement.attributes.notes = other.attributes.notes;
                    end
                    replacement.model_evidence_ids = other.model_evidence_ids;
                    replacement.record_id = Annotations.Store.uuid();
                    event.owner_ids{end + 1} = conflict; event.before(end + 1) = other;
                    replacement.revision = other.revision + 1;
                    next.records(strcmp({next.records.owner_id}, conflict)) = replacement;
                elseif ~isempty(conflict)
                    error('Annotations:Occupied', 'Identity %s is already confirmed for owner %s. Choose Move, Swap, or Cancel.', result.candidates{1}, conflict);
                elseif ~any(strcmp(action, {'assign','replace'}))
                    error('Annotations:Command', 'Unknown annotation command: %s.', action);
                end
            end
            if numel(event.owner_ids) == 1 && Annotations.Store.sameMeaning(current, result)
                event.changed = false; return;
            end
            result.revision = current.revision + 1; result.record_id = Annotations.Store.uuid();
            next.records(strcmp({next.records.owner_id}, ownerId)) = result;
            next.revision = store.revision + 1;
            % Competing hypotheses retain their evidence and get a visible conflict.
            if Annotations.Store.confirmed(result)
                for i = 1:numel(next.records)
                    r = next.records(i);
                    if strcmp(r.owner_id, ownerId) || ~any(strcmp(r.candidates, result.candidates{1})) || Annotations.Store.confirmed(r), continue; end
                    if ~any(strcmp(event.owner_ids, r.owner_id))
                        event.owner_ids{end + 1} = r.owner_id; event.before(end + 1) = store.records(i);
                    end
                    next.records(i).conflicts = unique([r.conflicts, {result.candidates{1}}]);
                    next.records(i).revision = r.revision + 1;
                end
            end
            [next,event] = Annotations.Store.refreshConflicts(store,next,event);
            % Keep delta order identical even when a caller's owner is not first.
            event.after = Annotations.Store.orderedRecords(next, event.owner_ids);
            event.event_id = Annotations.Store.uuid(); event.revision = next.revision;
            event.time = Annotations.Store.now(); event.changed = true;
            next.journal(end + 1) = event;
            Annotations.Store.validate(next);
        end

        function [next, event] = undo(store, options)
            if nargin < 2, options = struct(); end
            Annotations.Store.validate(store);
            if isempty(store.journal), error('Annotations:NothingToUndo', 'There is no annotation edit to undo.'); end
            operation = Annotations.Store.text(options, 'operation_id', Annotations.Store.uuid());
            if any(strcmp({store.journal.operation_id}, operation))
                next = store; event = store.journal(find(strcmp({store.journal.operation_id}, operation),1));
                event.changed = false; event.replayed = true; return;
            end
            index = find(~strcmp({store.journal.action}, 'undo'), 1, 'last');
            undone = {store.journal.undo_of};
            while ~isempty(index) && any(strcmp(undone, store.journal(index).event_id))
                index = find(~strcmp({store.journal(1:index-1).action}, 'undo'),1,'last');
            end
            if isempty(index), error('Annotations:NothingToUndo', 'There is no annotation edit to undo.'); end
            target = store.journal(index); next = store;
            for i = 1:numel(target.owner_ids)
                current = Annotations.Store.record(store, target.owner_ids{i});
                if ~Annotations.Store.sameMeaning(current, target.after(i))
                    error('Annotations:UndoConflict', 'This neuron changed after the edit. Resolve the newer work before undoing it.');
                end
                restored = target.before(i); restored.revision = current.revision + 1;
                restored.record_id = Annotations.Store.uuid();
                restored.model_evidence_ids = current.model_evidence_ids;
                next.records(strcmp({next.records.owner_id}, current.owner_id)) = restored;
            end
            next.revision = store.revision + 1;
            event = Annotations.Store.emptyEvent(); event.event_id = Annotations.Store.uuid();
            event.operation_id = operation; event.action = 'undo'; event.undo_of = target.event_id;
            event.owner_ids = target.owner_ids; event.before = Annotations.Store.orderedRecords(store,target.owner_ids);
            event.after = Annotations.Store.orderedRecords(next, target.owner_ids);
            event.revision = next.revision; event.time = Annotations.Store.now(); event.changed = true;
            next.journal(end + 1) = event;
            try
                Annotations.Store.validate(next);
            catch ME
                error('Annotations:UndoConflict', 'Undo would conflict with current identities: %s', ME.message);
            end
        end

        function [next, event] = batch(store, changes, options)
            if nargin < 3, options = struct(); end
            Annotations.Store.validate(store); Annotations.Store.requireConfirmation(options);
            operation = Annotations.Store.text(options,'operation_id',Annotations.Store.uuid());
            previous = find(strcmp({store.journal.operation_id},operation),1);
            if ~isempty(previous)
                next=store; event=store.journal(previous); event.changed=false; event.replayed=true; return;
            end
            next=store; event=Annotations.Store.emptyEvent();
            event.operation_id=operation; event.action='batch';
            if isempty(changes), return; end
            if numel(unique({changes.owner_id}))~=numel(changes)
                error('Annotations:Batch','A batch cannot change one owner twice.');
            end
            for i=1:numel(changes)
                current=Annotations.Store.record(store,changes(i).owner_id);
                local_options=options;
                if isfield(changes(i),'expected_revision'), local_options.expected_revision=changes(i).expected_revision; end
                Annotations.Store.checkRevision(store,current,local_options);
                action=Annotations.Store.text(changes(i),'action','assign');
                if strcmp(action,'clear')
                    result=Annotations.Store.emptyRecord(current.owner_id);
                    result.catalog_version=current.catalog_version;
                    result.attributes.notes=current.attributes.notes;
                else
                    result=Annotations.Store.fromDraft(current,changes(i).draft,local_options);
                    result.review='reviewed'; result.issue='';
                    Annotations.Store.validateDraft(result,changes(i).draft,store,local_options);
                end
                result.model_evidence_ids=current.model_evidence_ids;
                if Annotations.Store.sameMeaning(current,result), continue; end
                result.revision=current.revision+1; result.record_id=Annotations.Store.uuid();
                next.records(strcmp({next.records.owner_id},current.owner_id))=result;
                event.owner_ids{end+1}=current.owner_id; event.before(end+1)=current;
            end
            if isempty(event.owner_ids), return; end
            [next,event]=Annotations.Store.refreshConflicts(store,next,event);
            next.revision=store.revision+1; event.revision=next.revision;
            event.event_id=Annotations.Store.uuid(); event.time=Annotations.Store.now(); event.changed=true;
            event.after=Annotations.Store.orderedRecords(next,event.owner_ids);
            next.journal(end+1)=event; Annotations.Store.validate(next);
        end

        function [next, event] = recontextualize(store, context)
            Annotations.Store.validate(store);
            next=store; next.context=context;
            if ~isfield(next,'context_history'), next.context_history={}; end
            event=Annotations.Store.emptyEvent(); event.action='recontextualize';
            event.operation_id=Annotations.Store.uuid();
            sex=Annotations.Store.text(context,'sex','');
            for i=1:numel(next.records)
                current=store.records(i);
                if isempty(current.candidates) || ~isempty(strtrim(current.context_exception_reason)), continue; end
                applicable=true;
                for j=1:numel(current.candidates)
                    info=Annotations.Catalog.lookup(current.candidates{j},sex);
                    applicable=applicable && info.applicable;
                end
                if applicable, continue; end
                result=current; result.review='needs-review';
                message='The identity conflicts with the current specimen context. Review it or record an explicit exception.';
                if isempty(result.issue), result.issue=message;
                elseif ~contains(result.issue,message), result.issue=[result.issue ' ' message]; end
                if Annotations.Store.sameMeaning(current,result), continue; end
                result.revision=current.revision+1; result.record_id=Annotations.Store.uuid();
                next.records(i)=result; event.owner_ids{end+1}=current.owner_id; event.before(end+1)=current;
            end
            if isequaln(context,store.context) && isempty(event.owner_ids), return; end
            next.revision=store.revision+1;
            next.context_history{end+1}=struct('before',store.context,'after',context, ...
                'revision',next.revision,'time',Annotations.Store.now());
            [next,event]=Annotations.Store.refreshConflicts(store,next,event);
            if ~isempty(event.owner_ids)
                event.event_id=Annotations.Store.uuid(); event.revision=next.revision;
                event.time=Annotations.Store.now(); event.changed=true;
                event.after=Annotations.Store.orderedRecords(next,event.owner_ids);
                next.journal(end+1)=event;
            end
            Annotations.Store.validate(next);
        end

        function [next, event] = restore(store, imported, options)
            if nargin<3, options=struct(); end
            Annotations.Store.validate(store); Annotations.Store.validate(imported);
            Annotations.Store.requireConfirmation(options);
            if ~strcmp(store.source_id,imported.source_id) || ...
                    ~all(ismember({imported.owners.owner_id},{store.owners.owner_id}))
                error('Annotations:Correspondence','Imported annotations require explicit source and stable-owner correspondence.');
            end
            if ~strcmp(store.catalog_version,imported.catalog_version)
                error('Annotations:CatalogMigration','An explicit catalog migration is required before restoring these annotations.');
            end
            targets=Annotations.Store.value(options,'owner_ids',{store.owners.owner_id});
            targets=reshape(cellstr(string(targets)),1,[]);
            if ~all(ismember(targets,{store.owners.owner_id})) || ...
                    ~all(ismember(targets,{imported.records.owner_id}))
                error('Annotations:Correspondence','Every selected active owner must exist in the current and imported annotation stores.');
            end
            operation=Annotations.Store.text(options,'operation_id',Annotations.Store.uuid());
            previous=find(strcmp({store.journal.operation_id},operation),1);
            if ~isempty(previous)
                next=store; event=store.journal(previous); event.changed=false; event.replayed=true; return;
            end
            next=store; event=Annotations.Store.emptyEvent(); event.action='restore'; event.operation_id=operation;
            for i=1:numel(imported.evidence)
                evidence=imported.evidence(i); index=find(strcmp({next.evidence.evidence_id},evidence.evidence_id),1);
                if isempty(index), next.evidence(end+1)=evidence;
                elseif ~isequaln(next.evidence(index),evidence)
                    error('Annotations:EvidenceCollision','The same immutable evidence ID has conflicting contents.');
                end
            end
            for i=1:numel(imported.records)
                result=imported.records(i); current=Annotations.Store.record(store,result.owner_id);
                if ~any(strcmp(targets,result.owner_id)), continue; end
                result.model_evidence_ids=union(current.model_evidence_ids,result.model_evidence_ids,'stable');
                if Annotations.Store.sameMeaning(current,result) && isequaln(current.provenance,result.provenance)
                    index=find(strcmp({next.records.owner_id},result.owner_id),1);
                    next.records(index).model_evidence_ids=result.model_evidence_ids;
                    continue;
                end
                result.record_id=Annotations.Store.uuid(); result.revision=current.revision+1;
                next.records(strcmp({next.records.owner_id},result.owner_id))=result;
                event.owner_ids{end+1}=result.owner_id; event.before(end+1)=current;
            end
            if ~isfield(next,'imported_histories'), next.imported_histories={}; end
            snapshot=struct('source_id',imported.source_id,'revision',imported.revision, ...
                'generation',imported.generation,'records',imported.records,'journal',imported.journal, ...
                'context',imported.context,'imported_histories',{Annotations.Store.value(imported,'imported_histories',{})});
            digest=Annotations.Store.hashValue(snapshot);
            known=cellfun(@(x) x.sha256,next.imported_histories,'UniformOutput',false);
            if ~any(strcmp(known,digest))
                next.imported_histories{end+1}=struct('sha256',digest,'snapshot',snapshot,'time',Annotations.Store.now());
            end
            [next,event]=Annotations.Store.refreshConflicts(store,next,event);
            next.revision=store.revision+1;
            event.event_id=Annotations.Store.uuid(); event.revision=next.revision;
            event.time=Annotations.Store.now(); event.changed=true;
            event.after=Annotations.Store.orderedRecords(next,event.owner_ids);
            next.journal(end+1)=event; Annotations.Store.validate(next);
        end

        function projection = project(store, neurons)
            if nargin < 2, owners = {store.owners.owner_id};
            else
                if isa(neurons, 'Neurons.Image'), neurons = neurons.neurons; end
                owners = cell(1,numel(neurons));
                for i=1:numel(neurons), owners{i}=Annotations.Store.text(neurons(i),'annotation_id',''); end
            end
            template = struct('annotation_id', '', 'annotation', '', 'annotation_confidence', -1, ...
                'is_annotation_on', NaN, 'is_emphasized', false, 'annotation_record', struct(), 'lossy', false);
            projection = repmat(template, 1, numel(owners));
            for i = 1:numel(owners)
                r = Annotations.Store.record(store, owners{i});
                projection(i).annotation_id = r.owner_id; projection(i).annotation_record = r;
                projection(i).is_annotation_on = r.attributes.on_off;
                projection(i).is_emphasized = r.attributes.emphasized;
                if Annotations.Store.confirmed(r)
                    projection(i).annotation = r.candidates{1}; projection(i).annotation_confidence = 1;
                elseif strcmp(r.kind,'classification') && strcmp(r.certainty,'confident') && ...
                        Annotations.Store.reviewed(r) && isempty(r.issue)
                    projection(i).annotation = r.classification_token; projection(i).annotation_confidence = 1;
                else
                    projection(i).lossy = ~strcmp(r.kind,'unassigned');
                end
            end
        end

        function records = constraints(store, backend)
            records = store.records([]);
            if ~isfield(store,'constraints_enabled') || ~store.constraints_enabled, return; end
            types = {};
            if isstruct(backend)
                types = Annotations.Store.value(backend,'constraint_types',{});
            elseif any(strcmpi(char(string(backend)),{'crf','legacy-crf'}))
                types = {'individual'};
            end
            for i = 1:numel(store.records)
                r = store.records(i);
                if strcmp(r.constraint_policy,'off'), continue; end
                if ~strcmp(r.certainty,'confident') || ~Annotations.Store.reviewed(r) || ~isempty(r.issue)
                    error('Annotations:TentativeConstraint','Only confidently reviewed identities can be hard constraints.');
                end
                if ~any(strcmp(types,r.kind))
                    error('Annotations:UnsupportedConstraint','The selected backend does not support the %s constraint. Disable it or select a compatible backend.',r.kind);
                end
                records(end + 1) = r;
            end
        end

        function [next, evidenceId] = captureEvidence(store, ownerId, values, metadata)
            if nargin<4, metadata=struct(); end
            current=Annotations.Store.record(store,ownerId); next=store;
            evidence=Annotations.Store.emptyEvidence(); evidenceId=Annotations.Store.uuid();
            evidence.evidence_id=evidenceId; evidence.owner_id=current.owner_id;
            evidence.source_id=store.source_id;
            evidence.origin=Annotations.Store.text(metadata,'origin','model-state-snapshot');
            evidence.originality='unverified inference provenance; immutable app model-state snapshot';
            if ~isempty(Annotations.Store.text(metadata,'inference_id','')) && ...
                    ~isempty(Annotations.Store.text(metadata,'bundle_id',''))
                evidence.origin=Annotations.Store.text(metadata,'origin','model-inference');
                evidence.originality='immutable inference snapshot';
            end
            evidence.values=struct('outputs',values,'metadata',metadata);
            evidence.sha256=Annotations.Store.hashValue(evidence.values);
            next.evidence(end+1)=evidence;
            index=find(strcmp({next.records.owner_id},current.owner_id),1);
            next.records(index).model_evidence_ids{end+1}=evidenceId;
            Annotations.Store.validate(next);
        end

        function next = selectConstraints(store, enabled, owners)
            if nargin < 3, owners = {store.records.owner_id}; end
            next = store; next.constraints_enabled = logical(enabled);
            changed=~isequal(next.constraints_enabled,store.constraints_enabled);
            for i = 1:numel(next.records)
                previous=next.records(i).constraint_policy;
                % Owners is the complete selected set; omitted owners must not
                % retain hard pins from a previous selection or disabled run.
                if enabled && any(strcmp(owners,next.records(i).owner_id)) && ...
                        Annotations.Store.confirmed(next.records(i))
                    next.records(i).constraint_policy = 'hard';
                else
                    next.records(i).constraint_policy = 'off';
                end
                if ~strcmp(previous,next.records(i).constraint_policy)
                    next.records(i).revision=next.records(i).revision+1;
                    changed=true;
                end
            end
            if changed, next.revision=store.revision+1; end
            Annotations.Store.validate(next);
        end

        function validate(store)
            required = {'schema_version','revision','generation','source_id','scope_id','owners','records','evidence','journal'};
            if ~isstruct(store) || ~isscalar(store) || ~all(isfield(store,required)) || store.schema_version ~= 2
                error('Annotations:Schema','Invalid annotation store schema.');
            end
            if ~isnumeric(store.revision) || ~isreal(store.revision) || ~isscalar(store.revision) || ...
                    ~isfinite(store.revision) || store.revision < 0 || store.revision >= flintmax || store.revision ~= round(store.revision) || ...
                    ~isnumeric(store.generation) || ~isreal(store.generation) || ~isscalar(store.generation) || ...
                    ~isfinite(store.generation) || store.generation < 0 || store.generation >= flintmax || store.generation ~= round(store.generation)
                error('Annotations:Schema','Invalid annotation revision or generation.');
            end
            ids = {store.owners.owner_id};
            if numel(unique(ids)) ~= numel(ids) || any(cellfun(@isempty,ids)) || ...
                    ~isequal(sort(ids),sort({store.records.owner_id}))
                error('Annotations:Ownership','Each annotation must have one unique stable owner.');
            end
            occupied = {};
            for i = 1:numel(store.records)
                r = store.records(i);
                if ~all(isfield(r,fieldnames(Annotations.Store.emptyRecord('')))) || ...
                        ~iscellstr(r.candidates) || numel(unique(r.candidates)) ~= numel(r.candidates) || ...
                        ~any(strcmp(r.kind,{'unassigned','individual','unresolved_set','classification','legacy_issue'})) || ...
                        ~any(strcmp(r.certainty,{'confident','tentative','unspecified'})) || ...
                        ~any(strcmp(r.review,{'unreviewed','reviewed','legacy-reviewed','needs-review'})) || ...
                        ~any(strcmp(r.constraint_policy,{'off','hard'}))
                    error('Annotations:Record','Invalid structured annotation record.');
                end
                if strcmp(r.kind,'individual') && numel(r.candidates) ~= 1
                    error('Annotations:Record','An individual record requires one canonical token.');
                end
                if strcmp(r.kind,'classification') && (~isempty(r.candidates) || isempty(r.classification_token))
                    error('Annotations:Record','A classification token is separate from candidate individual IDs.');
                end
                if strcmp(r.kind,'unresolved_set') && numel(r.candidates) < 2
                    error('Annotations:Record','Unresolved membership must retain at least two explicit members.');
                end
                for j=1:numel(r.candidates)
                    info=Annotations.Catalog.lookup(r.candidates{j},'');
                    if ~strcmp(info.kind,'individual') || ~strcmp(info.token,r.candidates{j})
                        error('Annotations:Record','The saved annotation contains a noncanonical individual.');
                    end
                    if Annotations.Store.confirmed(r)
                        applicable=Annotations.Catalog.lookup(r.candidates{j},Annotations.Store.text(store.context,'sex',''));
                        if ~applicable.applicable && isempty(strtrim(r.context_exception_reason))
                            error('Annotations:Context','A confirmed identity requires a recorded exception outside its specimen context.');
                        end
                    end
                end
                if strcmp(r.kind,'classification')
                    info=Annotations.Catalog.lookup(r.classification_token,'');
                    if ~strcmp(info.kind,'classification')
                        error('Annotations:Record','Unknown non-neuronal classification token.');
                    end
                end
                if strcmp(r.kind,'unassigned') && ~isempty(r.candidates)
                    error('Annotations:Record','An unassigned record cannot retain candidate identity claims.');
                end
                if strcmp(r.kind,'unresolved_set')
                    members=Annotations.Catalog.members(r.group,'',true);
                    if isempty(r.group) || ~all(ismember(r.candidates,members))
                        error('Annotations:Record','Saved unresolved membership does not belong to its explicit catalog group.');
                    end
                end
                if ~isscalar(r.revision) || ~isfinite(r.revision) || r.revision < 0 || r.revision ~= round(r.revision) || ...
                        ~isscalar(r.attributes.on_off) || ~isreal(r.attributes.on_off) || ...
                        ~(isnan(r.attributes.on_off) || any(r.attributes.on_off == [0 1])) || ...
                        ~isscalar(r.attributes.emphasized)
                    error('Annotations:Record','Invalid annotation attributes or revision.');
                end
                if ~isnan(r.attributes.on_off) && (isempty(r.candidates) || ~all(ismember(r.candidates,{'AWCL','AWCR'})))
                    error('Annotations:Record','Saved ON/OFF metadata is only applicable to AWC members.');
                end
                if Annotations.Store.confirmed(r)
                    owner = store.owners(strcmp(ids,r.owner_id));
                    key = [owner.scope_id '|' r.candidates{1}];
                    if any(strcmp(occupied,key)), error('Annotations:Occupied','A canonical individual has multiple confirmed owners.'); end
                    occupied{end + 1} = key;
                end
            end
            evidence_ids={store.evidence.evidence_id};
            if numel(unique(evidence_ids))~=numel(evidence_ids)
                error('Annotations:EvidenceIntegrity','Model evidence identifiers are not unique.');
            end
            for i=1:numel(store.evidence)
                evidence=store.evidence(i);
                if ~strcmp(evidence.sha256,Annotations.Store.hashValue(evidence.values))
                    error('Annotations:EvidenceIntegrity','Saved model evidence failed its integrity check.');
                end
            end
            revisions=[store.journal.revision];
            if any(~isfinite(revisions) | revisions<1 | revisions~=round(revisions) | revisions>store.revision) || any(diff(revisions)<=0)
                error('Annotations:Journal','Invalid annotation journal revisions.');
            end
            for i=1:numel(store.journal)
                item=store.journal(i);
                if numel(item.owner_ids)~=numel(item.before) || numel(item.owner_ids)~=numel(item.after) || ...
                        ~isequal(item.owner_ids,{item.before.owner_id}) || ~isequal(item.owner_ids,{item.after.owner_id})
                    error('Annotations:Journal','Annotation history does not identify all affected owners.');
                end
            end
        end

        function ids = missingEvidence(store)
            ids={}; embedded={store.evidence.evidence_id};
            for i=1:numel(store.records)
                requested=store.records(i).model_evidence_ids;
                ids=[ids,requested(~ismember(requested,embedded))];
            end
            ids=unique(ids,'stable');
        end

        function [payload, fingerprint, issues] = loadValidated(path)
            payload=load(path); fingerprint=Annotations.Store.fingerprint(path);
            issues=Annotations.Store.verifyLineage(path,payload);
            if isfield(payload,'annotation_store'), Annotations.Store.validate(payload.annotation_store); end
        end

        function issues = verifyLineage(path, payload)
            if nargin<2, payload=load(path); end
            issues=struct('code',{},'message',{});
            pending=[char(string(path)) '.processing.pending.json'];
            if exist(pending,'file')==2
                issues(end+1)=struct('code','processing-save-pending','message', ...
                    sprintf('An image/ID processing save requires recovery review. Verify its saved image, ID generation, and recovery files before editing: %s',pending));
            end
            if isfield(payload,'annotation_store')
                missing=Annotations.Store.missingEvidence(payload.annotation_store);
                if ~isempty(missing)
                    issues(end+1)=struct('code','evidence-unavailable','message', ...
                        sprintf('%d referenced model evidence artifacts are unavailable. Manual annotations remain editable; model scores have not been reconstructed.',numel(missing)));
                end
            end
            marker=[char(string(path)) '.annotations.lineage.json'];
            if exist(marker,'file')==2
                try
                    lineage=jsondecode(fileread(marker)); current=Annotations.Store.fingerprint(path);
                    if ~isfield(payload,'annotation_store')
                        issues(end+1)=struct('code','versioned-store-erased','message', ...
                            'Recovery evidence shows a versioned annotation save, but this file is legacy. Reconcile it with the recovery copy; it has not been restored automatically.');
                    elseif ~strcmp(current.sha256,lineage.pending_sha256) && ...
                            (~isfield(lineage,'previous') || ~strcmp(current.sha256,lineage.previous.sha256))
                        issues(end+1)=struct('code','external-writer','message', ...
                            'This ID file differs from its recorded publication lineage. Review external edits before saving.');
                    end
                catch
                    issues(end+1)=struct('code','lineage-unavailable','message','ID recovery metadata could not be verified.');
                end
            end
            if isfield(payload,'annotation_store') && isfield(payload,'neurons') && isa(payload.neurons,'Neurons.Image')
                store=payload.annotation_store;
                embedded=Annotations.Store.value(payload.neurons,'annotation_store',struct());
                if isstruct(embedded) && isfield(embedded,'schema_version')
                    embedded.generation=store.generation;
                    if ~isequaln(embedded,store)
                        issues(end+1)=struct('code','embedded-store-mismatch','message', ...
                            'The neuron compatibility copy differs from the authoritative annotation store. The versioned top-level store takes precedence.');
                    end
                end
                try
                    projection=Annotations.Store.project(store,payload.neurons.neurons);
                    for i=1:numel(projection)
                        n=payload.neurons.neurons(i); p=projection(i);
                        if ~strcmp(n.annotation,p.annotation) || ~isequaln(n.annotation_confidence,p.annotation_confidence) || ...
                                ~isequaln(n.is_annotation_on,p.is_annotation_on) || ~isequaln(n.is_emphasized,p.is_emphasized)
                            issues(end+1)=struct('code','projection-mismatch','message', ...
                                'Legacy neuron fields contradict the authoritative annotation records. Review the difference before reconciling.');
                            break;
                        end
                    end
                catch ME
                    issues(end+1)=struct('code','owner-mapping-mismatch','message',ME.message);
                end
            end
        end

        function value = fingerprint(path)
            value = struct('exists', false, 'sha256', '', 'generation', 0, 'revision', 0);
            if exist(path,'file') ~= 2, return; end
            value.exists = true; value.sha256 = Annotations.Store.hashFile(path);
            try
                variables = whos('-file',path,'annotation_store');
                if ~isempty(variables)
                    loaded = load(path,'annotation_store');
                    metadata=loaded.annotation_store;
                    if isstruct(metadata) && isscalar(metadata)
                        if isfield(metadata,'generation'), value.generation=Annotations.Store.boundedCounter(metadata.generation); end
                        if isfield(metadata,'revision'), value.revision=Annotations.Store.boundedCounter(metadata.revision); end
                    end
                end
            catch
                % A legacy or damaged file still has a useful content fingerprint.
            end
        end

        function [payload, published] = save(path, payload, expected, options)
            if nargin < 3, error('Annotations:ExpectedSave','Capture the file fingerprint before editing.'); end
            if nargin < 4, options = struct(); end
            if ~isstruct(payload) || ~isfield(payload,'annotation_store')
                error('Annotations:SavePayload','The save must include its authoritative annotation store.');
            end
            Annotations.Store.validate(payload.annotation_store);
            if ~(ischar(path) || (isstring(path) && isscalar(path) && ~ismissing(path)))
                error('Annotations:SavePath','Choose a file path for the neuron IDs.');
            end
            path = char(string(path));
            [folder,filename]=fileparts(path);
            if isempty(strtrim(path)) || isempty(filename) || isfolder(path)
                error('Annotations:SavePath','The ID destination must name a file, not a directory.');
            end
            if isempty(folder), folder = pwd; path = fullfile(folder,path); end
            if exist(folder,'dir') ~= 7, error('Annotations:SaveFolder','The ID destination directory does not exist.'); end
            temporary = [tempname(folder) '.mat'];
            cleanup = onCleanup(@() Annotations.Store.removeTemporary(temporary));
            % The staged value contains no live edits; only publish after verification.
            payload.annotation_store.generation = expected.generation + 1;
            builtin('save',temporary,'-struct','payload','-v7.3');
            verify = load(temporary,'annotation_store');
            Annotations.Store.validate(verify.annotation_store);
            if ~isequaln(verify.annotation_store,payload.annotation_store)
                error('Annotations:SaveVerification','The staged annotation store did not round-trip.');
            end
            Annotations.Store.injectFailure(options,'after_stage');
            lease = java.io.RandomAccessFile([path '.annotations.lock'],'rw');
            lease_cleanup = onCleanup(@() lease.close());
            try
                lock = lease.getChannel().tryLock();
            catch
                error('Annotations:WriterBusy','Another app is writing this ID file. Try again after it finishes.');
            end
            if isempty(lock), error('Annotations:WriterBusy','Another app is writing this ID file.'); end
            current = Annotations.Store.fingerprint(path);
            if ~isequal(current.exists,expected.exists) || ~strcmp(current.sha256,expected.sha256) || current.generation ~= expected.generation
                error('Annotations:StaleSave','The ID file changed after editing began. Reload or reconcile the newer save; your draft is retained.');
            end
            if current.exists
                readable = true;
                try
                    old_variables = whos('-file',path); %#ok<NASGU>
                catch
                    readable = false;
                end
                if readable
                    backup = [path '.lastgood.mat']; pending = [tempname(folder) '.lastgood.mat'];
                    pending_cleanup = onCleanup(@() Annotations.Store.removeTemporary(pending));
                    [ok,message] = copyfile(path,pending);
                    if ~ok || ~strcmp(Annotations.Store.hashFile(pending),current.sha256)
                        error('Annotations:RecoverySave','Could not preserve the previous save: %s',message);
                    end
                    Annotations.Store.atomicMove(pending,backup);
                else
                    % Explicit recovery must retain the unreadable original at
                    % a separate path. Verify its bytes again under this lease;
                    % never replace a valid last-good save with corrupt bytes.
                    retained = Annotations.Store.value(options,'validated_recovery_original','');
                    preserved = false;
                    if (ischar(retained) && isrow(retained)) || ...
                            (isstring(retained) && isscalar(retained) && ~ismissing(retained))
                        retained = char(retained);
                        try
                            preserved = isfile(retained) && ...
                                ~java.nio.file.Files.isSameFile(java.io.File(path).toPath(),java.io.File(retained).toPath()) && ...
                                strcmp(Annotations.Store.hashFile(retained),current.sha256);
                        catch
                            preserved = false;
                        end
                    end
                    if ~preserved
                        error('Annotations:RecoverySave','The previous ID file is unreadable. Explicit recovery must first retain a separate byte-verified copy of its original content.');
                    end
                end
            end
            lineage = struct('schema_version',2,'source_id',payload.annotation_store.source_id, ...
                'previous',current,'pending_generation',payload.annotation_store.generation, ...
                'pending_sha256',Annotations.Store.hashFile(temporary));
            lineage_pending = [tempname(folder) '.json'];
            lineage_cleanup = onCleanup(@() Annotations.Store.removeTemporary(lineage_pending));
            fid = fopen(lineage_pending,'w');
            if fid < 0, error('Annotations:RecoverySave','Cannot write ID recovery metadata.'); end
            stream_cleanup = onCleanup(@() fclose(fid));
            fwrite(fid,jsonencode(lineage),'char'); clear stream_cleanup;
            Annotations.Store.atomicMove(lineage_pending,[path '.annotations.lineage.json']);
            Annotations.Store.injectFailure(options,'before_replace');
            Annotations.Store.atomicMove(temporary,path);
            try
                Annotations.Store.injectFailure(options,'after_replace');
                published = Annotations.Store.fingerprint(path);
                if ~strcmp(published.sha256,lineage.pending_sha256) || published.generation ~= payload.annotation_store.generation
                    error('Annotations:SaveVerification','The published generation or content differs from the staged save.');
                end
            catch ME
                exception=MException('Annotations:PublishedSave', ...
                    'The ID file was replaced, but its publication could not be verified. Reload and verify that saved generation before further editing; do not assume the edit was rolled back.');
                exception=addCause(exception,ME); throw(exception);
            end
        end
    end

    methods (Static, Access = private)
        function result = fromDraft(previous, draft, options)
            result = previous; result.record_id = Annotations.Store.uuid();
            result.kind = Annotations.Store.text(draft,'kind','unassigned');
            result.candidates = cellstr(string(Annotations.Store.value(draft,'candidates',{})));
            result.candidates = reshape(result.candidates,1,[]);
            result.group = Annotations.Store.text(draft,'group','');
            result.classification_token='';
            if strcmp(result.kind,'classification')
                result.classification_token=Annotations.Store.text(draft,'token','');
                result.candidates={};
            end
            result.certainty = Annotations.Store.text(draft,'certainty','confident');
            result.catalog_version = Annotations.Store.text(draft,'catalog_version',Annotations.Catalog.version());
            attributes = Annotations.Store.value(draft,'attributes',struct());
            result.attributes = struct('on_off',Annotations.Store.value(attributes,'on_off',NaN), ...
                'emphasized',logical(Annotations.Store.value(attributes,'emphasized',false)), ...
                'notes',Annotations.Store.text(attributes,'notes',previous.attributes.notes));
            result.context_exception_reason = '';
            if isfield(options,'context_exception_reason')
                result.context_exception_reason = strtrim(char(string(options.context_exception_reason)));
            elseif isfield(draft,'context_exception_reason') && ...
                    strcmp(Annotations.Store.text(draft,'owner_id',''),previous.owner_id) && ...
                    strcmp(result.kind,previous.kind) && isequal(result.candidates,previous.candidates) && ...
                    strcmp(result.group,previous.group) && strcmp(result.classification_token,previous.classification_token)
                result.context_exception_reason = previous.context_exception_reason;
            end
            result.provenance = Annotations.Store.provenance(options,'manual');
            result.constraint_policy = 'off';
            fields={'kind','candidates','group','classification_token','certainty','attributes','context_exception_reason'};
            unchanged=true;
            for i=1:numel(fields), unchanged=unchanged && isequaln(previous.(fields{i}),result.(fields{i})); end
            if unchanged, result.constraint_policy=previous.constraint_policy; end
        end

        function validateDraft(record, draft, store, options)
            if ~Annotations.Store.value(draft,'valid',false)
                error('Annotations:InvalidDraft','%s',Annotations.Store.text(draft,'message','Choose a valid individual or explicitly stage unresolved membership.'));
            end
            if Annotations.Store.value(draft,'requires_staging',false)
                error('Annotations:UnresolvedDraft','Explicitly stage the group membership before assigning it.');
            end
            if Annotations.Store.value(draft,'context_exception_required',false) && isempty(strtrim(record.context_exception_reason))
                error('Annotations:Context','An identity outside the specimen context needs an explicit exception reason.');
            end
            sex = Annotations.Store.text(store.context,'sex','');
            for i = 1:numel(record.candidates)
                parsed = Annotations.Catalog.parse(record.candidates{i},sex,true);
                if ~strcmp(parsed.kind,'individual') || ~parsed.valid || ~strcmp(parsed.token,record.candidates{i})
                    error('Annotations:InvalidDraft','The draft contains an unknown canonical identity.');
                end
                if parsed.context_exception_required && isempty(strtrim(record.context_exception_reason))
                    error('Annotations:Context','The selected canonical individual requires an explicit specimen-context exception.');
                end
            end
            if strcmp(record.kind,'classification')
                info=Annotations.Catalog.lookup(record.classification_token,sex);
                if ~strcmp(info.kind,'classification'), error('Annotations:InvalidDraft','Unknown non-neuronal classification.'); end
            end
            if strcmp(record.kind,'unresolved_set')
                group = Annotations.Catalog.parse(record.group,sex,true);
                if isempty(record.group) || ~isequal(sort(record.candidates(:)),sort(group.candidates(:)))
                    error('Annotations:InvalidDraft','The unresolved member set must match an explicitly staged catalog group.');
                end
            end
            if ~isnan(record.attributes.on_off) && (isempty(record.candidates) || ~all(ismember(record.candidates,{'AWCL','AWCR'})))
                error('Annotations:Attributes','ON/OFF applies only to AWC identities or explicitly unresolved AWC membership.');
            end
            previous=Annotations.Store.record(store,record.owner_id);
            if ~isnan(previous.attributes.on_off) && ...
                    isnan(record.attributes.on_off) && ~any(ismember(record.candidates,{'AWCL','AWCR'})) && ...
                    ~Annotations.Store.value(options,'resolve_attributes',false)
                error('Annotations:Attributes','Explicitly resolve the previous AWC ON/OFF attribute before replacing it.');
            end
        end

        function checkRevision(store, record, options)
            if isfield(options,'expected_revision') && options.expected_revision ~= record.revision
                error('Annotations:StaleDraft','The target annotation changed. Review the new value before assigning.');
            end
            if isfield(options,'expected_store_revision') && options.expected_store_revision ~= store.revision
                error('Annotations:StaleDraft','Annotations changed while this action was open. Revalidate the action.');
            end
        end

        function yes = sameMeaning(a,b)
            fields = {'kind','candidates','group','classification_token','certainty','review','attributes','context_exception_reason','constraint_policy','issue','conflicts'};
            yes = true;
            for i=1:numel(fields), yes = yes && isequaln(a.(fields{i}),b.(fields{i})); end
        end

        function [next,event] = refreshConflicts(previous,next,event)
            for i=1:numel(next.records)
                r=next.records(i); conflicts={};
                if ~Annotations.Store.confirmed(r)
                    for j=1:numel(r.candidates)
                        if ~isempty(Annotations.Store.occupant(next,r.candidates{j},[],r.owner_id))
                            conflicts{end+1}=r.candidates{j};
                        end
                    end
                end
                if isequal(r.conflicts,conflicts), continue; end
                if ~any(strcmp(event.owner_ids,r.owner_id))
                    event.owner_ids{end+1}=r.owner_id;
                    event.before(end+1)=Annotations.Store.record(previous,r.owner_id);
                    next.records(i).revision=r.revision+1;
                end
                next.records(i).conflicts=conflicts;
            end
        end

        function records = orderedRecords(store, ids)
            records = store.records([]);
            for i=1:numel(ids), records(end+1)=Annotations.Store.record(store,ids{i}); end
        end

        function requireConfirmation(options)
            if ~Annotations.Store.value(options,'confirmed',false)
                error('Annotations:Confirmation','This annotation change requires an explicit confirmation.');
            end
        end

        function value = emptyRecord(ownerId)
            value = struct('owner_id',ownerId,'record_id','','revision',0,'catalog_version','', ...
                'kind','unassigned','candidates',{{}},'group','','classification_token','','certainty','unspecified', ...
                'review','unreviewed','attributes',struct('on_off',NaN,'emphasized',false,'notes',''), ...
                'context_exception_reason','','provenance',struct('source','','author','','time','','reason','','raw',''), ...
                'model_evidence_ids',{{}},'constraint_policy','off','issue','','conflicts',{{}});
        end

        function value = emptyEvent()
            value = struct('event_id','','operation_id','','action','','owner_ids',{{}}, ...
                'before',repmat(Annotations.Store.emptyRecord(''),1,0), ...
                'after',repmat(Annotations.Store.emptyRecord(''),1,0), ...
                'revision',0,'time','','undo_of','','changed',false,'replayed',false);
        end

        function value = owner()
            value=struct('owner_id','','source_id','','scope_id','','geometry_revision','');
        end

        function value = emptyEvidence()
            value=struct('evidence_id','','owner_id','','source_id','','origin','','originality','','values',struct(),'sha256','');
        end

        function value = provenance(options, source)
            value=struct('source',source,'author',Annotations.Store.text(options,'author',''), ...
                'time',Annotations.Store.now(),'reason',Annotations.Store.text(options,'reason',''),'raw','');
        end

        function result = value(object, field, fallback)
            result=fallback;
            if (isstruct(object) && isfield(object,field)) || (isobject(object) && isprop(object,field))
                result=object.(field);
            end
        end

        function result = text(object, field, fallback)
            value=Annotations.Store.value(object,field,fallback);
            if isempty(value), result=fallback; else, result=char(string(value)); end
        end

        function value = uuid()
            value=char(java.util.UUID.randomUUID());
        end

        function value = now()
            value=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
        end

        function hash = hashFile(path)
            fid=fopen(path,'rb');
            if fid<0, error('Annotations:Fingerprint','Cannot read the ID file for verification.'); end
            cleanup=onCleanup(@() fclose(fid)); digest=java.security.MessageDigest.getInstance('SHA-256');
            while true
                bytes=fread(fid,1024*1024,'*uint8');
                if isempty(bytes), break; end
                digest.update(typecast(bytes(:),'int8'));
            end
            hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
        end

        function hash = hashBytes(bytes)
            digest=java.security.MessageDigest.getInstance('SHA-256'); digest.update(typecast(bytes(:),'int8'));
            hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
        end

        function hash = hashValue(value)
            bytes=unicode2native(jsonencode(value,'ConvertInfAndNaN',false),'UTF-8');
            hash=Annotations.Store.hashBytes(bytes);
        end

        function result = boundedCounter(value)
            result=0;
            if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && ...
                    value>=0 && value<flintmax && value==round(value)
                result=double(value);
            end
        end

        function atomicMove(source, destination)
            opts=javaArray('java.nio.file.CopyOption',2);
            opts(1)=java.nio.file.StandardCopyOption.ATOMIC_MOVE;
            opts(2)=java.nio.file.StandardCopyOption.REPLACE_EXISTING;
            try
                java.nio.file.Files.move(java.io.File(source).toPath(),java.io.File(destination).toPath(),opts);
            catch ME
                error('Annotations:AtomicSave','The ID destination does not support a verified atomic replacement: %s',ME.message);
            end
        end

        function removeTemporary(path)
            if exist(path,'file')==2, delete(path); end
        end

        function injectFailure(options, stage)
            if strcmp(Annotations.Store.text(options,'fail_at',''),stage)
                error('Annotations:InjectedFailure','Injected save failure at %s.',stage);
            end
        end
    end
end
