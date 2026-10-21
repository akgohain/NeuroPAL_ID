classdef ManualIDService
    %MANUALIDSERVICE Save human annotations without changing model evidence.
    methods (Static)
        function store = ensure(app)
            if isempty(app.image_neurons)
                error('Annotations:NoSource', 'Open an image and select a neuron first.');
            end
            image = app.image_neurons;
            store = image.annotation_store;
            if isempty(fieldnames(store))
                context = struct('sex', app.worm.sex, ...
                    'source_file', app.image_file, 'catalog_version', Annotations.Catalog.version());
                [store, owners] = Annotations.Store.create(image.neurons, context);
                for i = 1:numel(image.neurons)
                    image.neurons(i).annotation_id = owners{i};
                end
                image.annotation_store = store;
                Program.GUI.ManualIDService.apply(image, store);
            else
                oldSex = '';
                if isfield(store.context, 'sex'), oldSex = store.context.sex; end
                if ~strcmp(Annotations.Catalog.normalizeSex(oldSex), Annotations.Catalog.normalizeSex(app.worm.sex))
                    context = store.context; context.sex = app.worm.sex;
                    [store, ~] = Annotations.Store.recontextualize(store, context);
                    Program.GUI.ManualIDService.apply(image, store);
                end
                % New detections have new owners; a list row is not an identity.
                missing = arrayfun(@(n) isempty(n.annotation_id), image.neurons);
                if any(missing)
                    context = struct('sex', app.worm.sex, 'source_id', store.source_id, ...
                        'specimen_id', store.specimen_id, 'catalog_version', Annotations.Catalog.version());
                    [extra, owners] = Annotations.Store.create(image.neurons(missing), context);
                    indices = find(missing);
                    for j = 1:numel(indices)
                        image.neurons(indices(j)).annotation_id = owners{j};
                    end
                    store.records = [store.records, extra.records];
                    store.owners = [store.owners, extra.owners];
                    if isfield(store, 'evidence'), store.evidence = [store.evidence, extra.evidence]; end
                    image.annotation_store = store;
                end
            end
            key = Program.GUI.ManualIDService.fileKey(app);
            known = getappdata(app.CELL_ID, 'manual_id_file_snapshot');
            if isempty(known) || ~strcmp(known.key, key)
                setappdata(app.CELL_ID, 'manual_id_file_snapshot', ...
                    struct('key', key, 'fingerprint', Annotations.Store.fingerprint(app.id_file)));
            end
        end

        function value = context(app, index)
            store = Program.GUI.ManualIDService.ensure(app);
            if nargin < 2, index = app.selected_neuron; end
            if isempty(index) || ~isscalar(index) || ~isfinite(index) || ...
                    index ~= round(index) || index < 1 || index > numel(app.image_neurons.neurons)
                error('Annotations:NoTarget', 'Select a neuron in the image first.');
            end
            neuron = app.image_neurons.neurons(index);
            record = Annotations.Store.record(store, neuron.annotation_id);
            scale = reshape(app.image_neurons.scale, 1, []);
            geometry = [app.image_neurons.get_positions(), repmat(scale, numel(app.image_neurons.neurons), 1)];
            value = struct('source_id', store.source_id, 'owner_id', neuron.annotation_id, ...
                'annotation_revision', record.revision, ...
                'geometry_revision', Program.GUI.ManualIDService.digest(geometry), ...
                'context_revision', Program.GUI.ManualIDService.digest(app.worm), ...
                'sex', app.worm.sex, 'file', app.image_file, 'id_file', app.id_file, ...
                'target', neuron);
        end

        function record = record(app, index)
            store = Program.GUI.ManualIDService.ensure(app);
            if nargin < 2, index = app.selected_neuron; end
            record = Annotations.Store.record(store, app.image_neurons.neurons(index).annotation_id);
        end

        function result = assign(app, index, draft, action, options)
            if nargin < 4 || isempty(action), action = 'assign'; end
            if nargin < 5, options = struct(); end
            captured = Program.GUI.ManualIDService.context(app, index);
            if isfield(options, 'context')
                Program.GUI.ManualIDService.checkContext(app, index, options.context);
                captured = options.context;
            end
            result = struct('changed', false, 'noop', false, 'index', index, ...
                'owner_id', captured.owner_id, 'source_id', captured.source_id, 'event', []);
            if ischar(draft) || isstring(draft)
                draft = Annotations.Catalog.parse(draft, captured.sex);
            end
            old = Program.GUI.ManualIDService.record(app, index);
            if ~isempty(app.image_neurons.annotation_read_only_reason)
                error('Annotations:ReadOnly', '%s', app.image_neurons.annotation_read_only_reason);
            end
            if strcmp(action, 'clear') || (isfield(draft, 'status') && strcmp(draft.status, 'empty'))
                if strcmp(old.kind, 'unassigned'), result.noop = true; return; end
                if ~isfield(options, 'confirmed') || ~options.confirmed
                    answer = uiconfirm(app.CELL_ID, 'Clear this neuron''s ID? Its geometry and original model predictions will be kept.', ...
                        'Clear ID', 'Options', {'Clear ID', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(answer, 'Clear ID'), return; end
                end
                action = 'clear'; options.confirmed = true;
            else
                if ~isfield(draft, 'valid') || ~draft.valid
                    if isfield(draft, 'message'), message = draft.message; else, message = 'Choose an individual or explicitly keep the group unresolved.'; end
                    error('Annotations:InvalidDraft', '%s', message);
                end
                if isfield(draft, 'context_exception_required') && draft.context_exception_required
                    reason = '';
                    if isfield(options, 'reason'), reason = strtrim(char(options.reason)); end
                    if isempty(reason)
                        answer = inputdlg('Reason for using an ID outside the specimen''s catalog:', ...
                            'Anatomical context exception', [2 55]);
                        if isempty(answer) || isempty(strtrim(answer{1})), return; end
                        reason = strtrim(answer{1});
                    end
                    options.reason = reason;
                end
                if ~isnan(old.attributes.on_off) && isnan(draft.attributes.on_off) && ...
                        ~any(ismember(draft.candidates, {'AWCL', 'AWCR'}))
                    answer = uiconfirm(app.CELL_ID, 'This ID cannot carry the previous AWC ON/OFF state. Clear that state with this replacement?', ...
                        'Incompatible annotation attribute', 'Options', {'Clear state and replace', 'Cancel'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(answer, 'Clear state and replace'), return; end
                    options.resolve_attributes = true;
                end
                store = app.image_neurons.annotation_store;
                if strcmp(draft.kind, 'individual') && strcmp(draft.certainty, 'confident')
                    other = Annotations.Store.occupant(store, draft.candidates{1});
                    if ~isempty(other) && ~strcmp(other, captured.owner_id)
                        if ~isfield(options, 'conflict_owner') || ~strcmp(options.conflict_owner, other)
                            row = find(strcmp({app.image_neurons.neurons.annotation_id}, other), 1);
                            before = Annotations.Store.display(old);
                            if isempty(before), before = 'unassigned'; end
                            message = sprintf('%s is assigned to neuron %d.\n\nMove: neuron %d becomes %s; neuron %d becomes unassigned.\nYour current claim (%s) is withdrawn.', ...
                                draft.candidates{1}, row, index, draft.candidates{1}, row, before);
                            choices = {'Move', 'Cancel'};
                            if Annotations.Store.confirmed(old)
                                choices = {'Move', 'Swap', 'Cancel'};
                                message = sprintf('%s\n\nSwap: neuron %d becomes %s; neuron %d becomes %s.', ...
                                    message, index, draft.candidates{1}, row, old.candidates{1});
                            end
                            answer = uiconfirm(app.CELL_ID, message, 'Occupied neuron ID', ...
                                'Options', choices, 'DefaultOption', numel(choices), 'CancelOption', numel(choices));
                            if strcmp(answer, 'Cancel'), return; end
                            action = lower(answer); options.conflict_owner = other; options.confirmed = true;
                        end
                    end
                end
            end
            if strcmp(action, 'swap') && isfield(options, 'conflict_owner')
                otherRecord = Annotations.Store.record(app.image_neurons.annotation_store, options.conflict_owner);
                if ~isnan(otherRecord.attributes.on_off) && ...
                        ~any(ismember(old.candidates, {'AWCL', 'AWCR'}))
                    answer = uiconfirm(app.CELL_ID, ...
                        'The other neuron''s AWC ON/OFF state cannot apply to its swapped ID. Clear that state and swap both IDs?', ...
                        'Incompatible annotation attribute', 'Options', {'Clear state and swap', 'Cancel'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(answer, 'Clear state and swap'), return; end
                    options.resolve_attributes = true;
                end
            end
            Program.GUI.ManualIDService.checkContext(app, index, captured);
            if isfield(options, 'draft_generation')
                current = Program.GUI.ManualIDController.state(app);
                if current.generation ~= options.draft_generation || ...
                        ~strcmp(current.key, Program.GUI.ManualIDController.ownerKey(captured))
                    error('Annotations:StaleDraft', 'The draft or selected neuron changed while this action was open. Review the retained text before assigning.');
                end
            end
            options.expected_revision = captured.annotation_revision;
            options.expected_store_revision = app.image_neurons.annotation_store.revision;
            if isfield(options, 'reason'), options.context_exception_reason = options.reason; end
            if ~isfield(options, 'operation_id'), options.operation_id = char(java.util.UUID.randomUUID()); end
            store = app.image_neurons.annotation_store;
            store.context.sex = captured.sex;
            [next, event] = Annotations.Store.command(store, captured.owner_id, draft, action, options);
            result.event = event;
            if isfield(event, 'changed') && ~event.changed, result.noop = true; return; end
            next = Program.GUI.ManualIDService.persist(app, next);
            Program.GUI.ManualIDService.apply(app.image_neurons, next);
            result.changed = true;
        end

        function result = undo(app)
            store = Program.GUI.ManualIDService.ensure(app);
            [next, event] = Annotations.Store.undo(store);
            active = {app.image_neurons.neurons.annotation_id};
            for i = 1:numel(event.owner_ids)
                restored = Annotations.Store.record(next, event.owner_ids{i});
                if ~ismember(event.owner_ids{i}, active) && ~strcmp(restored.kind, 'unassigned')
                    error('Annotations:UndoTargetMissing', 'This edit belongs to a deleted neuron. Restore its geometry before restoring an anatomical claim.');
                end
            end
            result = struct('changed', false, 'noop', false, 'index', app.selected_neuron, ...
                'source_id', store.source_id, 'owner_id', '', 'event', event);
            if isfield(event, 'changed') && ~event.changed, result.noop = true; return; end
            next = Program.GUI.ManualIDService.persist(app, next);
            Program.GUI.ManualIDService.apply(app.image_neurons, next);
            result.changed = true;
        end

        function save(app)
            store = Program.GUI.ManualIDService.ensure(app);
            store = Program.GUI.ManualIDService.captureEvidence(app, store);
            store = Program.GUI.ManualIDService.persist(app, store);
            Program.GUI.ManualIDService.apply(app.image_neurons, store);
        end

        function store = persist(app, store, image)
            if nargin < 3, image = app.image_neurons; end
            if ~isempty(app.image_neurons.annotation_read_only_reason)
                error('Annotations:ReadOnly', '%s', app.image_neurons.annotation_read_only_reason);
            end
            if isempty(app.id_file)
                error('Annotations:NoDestination', 'This image has no ID save destination. Save the image to a writable local folder first.');
            end
            snapshot = getappdata(app.CELL_ID, 'manual_id_file_snapshot');
            if isempty(snapshot) || ~strcmp(snapshot.key, Program.GUI.ManualIDService.fileKey(app))
                error('Annotations:StaleSource', 'The ID destination changed. Reopen the image before saving.');
            end
            payload = struct();
            if exist(app.id_file, 'file') == 2
                payload = load(app.id_file);
            end
            payload.version = Program.ProgramInfo.version;
            payload.mp_params = app.mp_params;
            payload.mp_params.k = numel(image.neurons);
            payload.neurons = Program.GUI.ManualIDService.copyImage(image);
            Program.GUI.ManualIDService.apply(payload.neurons, store);
            payload.annotation_store = store;
            try
                [saved, fingerprint] = Annotations.Store.save(app.id_file, payload, snapshot.fingerprint);
            catch ME
                if ~strcmp(ME.identifier, 'Annotations:PublishedSave'), rethrow(ME); end
                % Publication may have succeeded even when its verification failed.
                try
                    [saved, ~, issues] = Annotations.Store.loadValidated(app.id_file);
                    acceptable = isempty(issues) || all(ismember({issues.code}, ...
                        {'embedded-store-mismatch', 'evidence-unavailable'}));
                    expectedStore = store;
                    expectedStore.generation = snapshot.fingerprint.generation + 1;
                    if ~acceptable || ~isequaln(saved.annotation_store, expectedStore), rethrow(ME); end
                    fingerprint = Annotations.Store.fingerprint(app.id_file);
                catch
                    app.image_neurons.annotation_read_only_reason = ...
                        'A save was published but could not be verified. Reopen and review the ID file before further edits. Your draft is retained.';
                    error('Annotations:SaveNeedsReload', '%s', app.image_neurons.annotation_read_only_reason);
                end
            end
            store = saved.annotation_store;
            setappdata(app.CELL_ID, 'manual_id_file_snapshot', ...
                struct('key', snapshot.key, 'fingerprint', fingerprint));
            processing = Program.ProcessingSession.get(app);
            if ~isempty(processing) && ~processing.pixels && strcmp(processing.id_file, app.id_file)
                processing.id_fingerprint = fingerprint;
                processing.neurons = Program.GUI.ManualIDService.copyImage(saved.neurons);
                setappdata(app.CELL_ID, 'processing_session', processing);
            end
        end

        function apply(image, store)
            projection = Annotations.Store.project(store, image.neurons);
            for i = 1:numel(image.neurons)
                neuron = image.neurons(i);
                neuron.annotation = projection(i).annotation;
                neuron.annotation_confidence = projection(i).annotation_confidence;
                neuron.is_annotation_on = projection(i).is_annotation_on;
                neuron.is_emphasized = projection(i).is_emphasized;
                neuron.annotation_record = projection(i).annotation_record;
            end
            image.annotation_store = store;
        end

        function copy = copyImage(image)
            copy = Neurons.Image([]);
            fields = properties(image);
            for i = 1:numel(fields)
                if strcmp(fields{i}, 'neurons'), continue; end
                copy.(fields{i}) = image.(fields{i});
            end
            if isa(image.meta_data, 'containers.Map') && image.meta_data.Count > 0
                copy.meta_data = containers.Map(keys(image.meta_data), values(image.meta_data));
            elseif isa(image.meta_data, 'containers.Map')
                copy.meta_data = containers.Map('KeyType', image.meta_data.KeyType, 'ValueType', image.meta_data.ValueType);
            end
            for i = 1:numel(image.neurons)
                neuron = Neurons.Neuron;
                fields = properties(neuron);
                for j = 1:numel(fields), neuron.(fields{j}) = image.neurons(i).(fields{j}); end
                copy.neurons(i) = neuron;
            end
        end

        function checkContext(app, index, captured)
            current = Program.GUI.ManualIDService.context(app, index);
            fields = {'source_id', 'owner_id', 'annotation_revision', 'geometry_revision', ...
                'context_revision', 'file', 'id_file', 'target'};
            for i = 1:numel(fields)
                if ~isfield(captured, fields{i}) || ~isequaln(current.(fields{i}), captured.(fields{i}))
                    error('Annotations:StaleDraft', 'The neuron, image, or anatomical context changed. Review the retained draft before assigning.');
                end
            end
        end

        function allowed = prepareClose(app)
            allowed = true;
            state = Program.GUI.ManualIDController.state(app);
            if app.is_saving_ID || state.busy
                uialert(app.CELL_ID, 'Wait for the current ID save to finish before closing or replacing its image.', 'Saving ID');
                allowed = false; return;
            end
            if Program.GUI.ManualIDController.dirty(app)
                answer = uiconfirm(app.CELL_ID, 'There are ID drafts that have not been assigned.', ...
                    'Unassigned ID drafts', 'Options', {'Return to editing', 'Discard drafts'}, ...
                    'DefaultOption', 1, 'CancelOption', 1);
                allowed = strcmp(answer, 'Discard drafts');
                if allowed, Program.GUI.ManualIDController.invalidate(app); end
            end
        end

        function key = fileKey(app)
            key = [char(app.image_file), '|', char(app.id_file)];
        end

        function value = rank(neuron)
            value = Inf;
            if isscalar(neuron.rank) && isfinite(neuron.rank), value = neuron.rank; end
        end

        function setConstraints(app, enabled)
            try
                store = Program.GUI.ManualIDService.ensure(app);
                next = Annotations.Store.selectConstraints(store, enabled);
                next = Program.GUI.ManualIDService.persist(app, next);
                Program.GUI.ManualIDService.apply(app.image_neurons, next);
                if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app, app.selected_neuron); end
            catch ME
                uialert(app.CELL_ID, ME.message, 'Constraint policy could not be saved');
            end
        end

        function contextChanged(app)
            if isempty(app.image_neurons), return; end
            previous = app.image_neurons.annotation_store;
            try
                if isempty(fieldnames(previous)), previous = Program.GUI.ManualIDService.ensure(app); end
                [next, ~] = Annotations.Store.recontextualize(previous, app.worm);
                next = Program.GUI.ManualIDService.persist(app, next);
                Program.GUI.ManualIDService.apply(app.image_neurons, next);
                app.manualIDDidCommit([], struct('changed', true), false);
                if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app, app.selected_neuron); end
            catch ME
                Program.GUI.ManualIDService.apply(app.image_neurons, previous);
                sex = '';
                if isfield(previous.context, 'sex'), sex = Annotations.Catalog.normalizeSex(previous.context.sex); end
                if isempty(sex), sex = 'Unknown'; end
                app.worm.sex = sex; app.SexDropDown.Value = sex;
                uialert(app.CELL_ID, ME.message, 'Annotation context could not be saved');
            end
        end

        function deleteNeuron(app, index)
            Program.HeavyJob.assertIdle();
            try
                captured = Program.GUI.ManualIDService.context(app, index);
                record = Program.GUI.ManualIDService.record(app, index);
                state = Program.GUI.ManualIDController.state(app);
                key = Program.GUI.ManualIDController.ownerKey(captured);
                draft = isKey(state.drafts, key) || (strcmp(state.key, key) && state.dirty);
                if ~strcmp(record.kind, 'unassigned') || draft
                    message = sprintf('Delete neuron %d and withdraw its ID (%s)? Any unassigned draft for this neuron will also be discarded. Its prior annotation remains in history.', ...
                        index, Annotations.Store.display(record));
                    answer = uiconfirm(app.CELL_ID, message, 'Delete neuron', ...
                        'Options', {'Delete neuron', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(answer, 'Delete neuron'), return; end
                end
                Program.GUI.ManualIDService.checkContext(app, index, captured);
                image = Program.GUI.ManualIDService.copyImage(app.image_neurons);
                changes = struct('owner_id', captured.owner_id, 'action', 'clear', ...
                    'draft', struct(), 'expected_revision', captured.annotation_revision);
                [next, ~] = Annotations.Store.batch(image.annotation_store, changes, struct('confirmed', true));
                image.del_neuron(index);
                next = Program.GUI.ManualIDService.persist(app, next, image);
                Program.GUI.ManualIDService.apply(image, next);
                selected = app.selected_neuron;
                app.image_neurons = image;
                state = Program.GUI.ManualIDController.state(app);
                if isKey(state.drafts, key), remove(state.drafts, key); end
                if strcmp(state.key, key), state.dirty = false; end
                Program.GUI.ManualIDController.put(app, state);
                if isequal(selected, index)
                    Program.GUI.ManualIDController.unselect(app);
                    app.selected_neuron = [];
                    Program.GUI.ManualIDInput.setValue(app, '');
                    Program.GUI.ManualIDInput.setEnabled(app, 'off');
                elseif ~isempty(selected) && selected > index
                    app.selected_neuron = selected - 1;
                end
                app.manualIDDidCommit([], struct('changed', true), false);
            catch ME
                uialert(app.CELL_ID, ME.message, 'Neuron could not be deleted');
            end
        end

        function capture = captureEvidence(app, store)
            capture = store;
            fields = {'deterministic_id', 'probabilistic_ids', 'probabilistic_probs', 'rank'};
            for i = 1:numel(app.image_neurons.neurons)
                neuron = app.image_neurons.neurons(i); values = struct();
                for j = 1:numel(fields), values.(fields{j}) = neuron.(fields{j}); end
                entries = find(strcmp({capture.evidence.owner_id}, neuron.annotation_id));
                same = false;
                if ~isempty(entries)
                    previous = capture.evidence(entries(end)).values;
                    if isfield(previous, 'outputs'), previous = previous.outputs; end
                    same = true;
                    for j = 1:numel(fields)
                        same = same && isfield(previous, fields{j}) && isequaln(previous.(fields{j}), values.(fields{j}));
                    end
                end
                if ~same
                    metadata = struct('source_file', app.image_file, 'worm', app.worm, ...
                        'position', neuron.position, 'catalog_version', Annotations.Catalog.version(), ...
                        'constraint_revision', store.revision, 'constraints_enabled', store.constraints_enabled);
                    [capture, ~] = Annotations.Store.captureEvidence(capture, neuron.annotation_id, values, metadata);
                end
            end
        end

        function clearAll(app)
            try
                store = Program.GUI.ManualIDService.ensure(app);
                source = Program.GUI.ManualIDService.bulkContext(app);
                changes = struct('owner_id', {}, 'action', {}, 'draft', {}, 'expected_revision', {});
                for i = 1:numel(app.image_neurons.neurons)
                    record = Annotations.Store.record(store, app.image_neurons.neurons(i).annotation_id);
                    if strcmp(record.kind, 'unassigned'), continue; end
                    changes(end+1) = struct('owner_id', record.owner_id, 'action', 'clear', ...
                        'draft', struct(), 'expected_revision', record.revision);
                end
                if isempty(changes), return; end
                answer = uiconfirm(app.CELL_ID, sprintf('Clear %d human annotations? Original predictions and geometry will be kept. This can be undone.', numel(changes)), ...
                    'Clear all IDs', 'Options', {'Clear all IDs', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(answer, 'Clear all IDs'), return; end
                Program.GUI.ManualIDService.checkBulkContext(app, source);
                [next, event] = Annotations.Store.batch(store, changes, struct('confirmed', true));
                next = Program.GUI.ManualIDService.persist(app, next);
                Program.GUI.ManualIDService.apply(app.image_neurons, next);
                result = struct('changed', true, 'event', event);
                app.manualIDDidCommit([], result, false);
                if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app, app.selected_neuron); end
            catch ME
                uialert(app.CELL_ID, ME.message, 'IDs could not be cleared');
            end
        end

        function flipAnatomicalSides(app)
            try
                store = Program.GUI.ManualIDService.ensure(app);
                source = Program.GUI.ManualIDService.bulkContext(app);
                changes = struct('owner_id', {}, 'action', {}, 'draft', {}, 'expected_revision', {});
                preview = {};
                for i = 1:numel(app.image_neurons.neurons)
                    record = Annotations.Store.record(store, app.image_neurons.neurons(i).annotation_id);
                    if ~strcmp(record.kind, 'individual'), continue; end
                    partner = Annotations.Catalog.bilateralPartner(record.candidates{1}, app.worm.sex);
                    if isempty(partner), continue; end
                    draft = Annotations.Catalog.parse(partner, app.worm.sex);
                    draft.certainty = record.certainty; draft.attributes = record.attributes;
                    changes(end+1) = struct('owner_id', record.owner_id, 'action', 'assign', ...
                        'draft', draft, 'expected_revision', record.revision);
                    preview{end+1} = sprintf('Neuron %d: %s → %s', i, record.candidates{1}, partner);
                end
                if isempty(changes)
                    uialert(app.CELL_ID, 'There are no resolved bilateral annotations to swap.', 'Anatomical L/R correction'); return;
                end
                shown = preview(1:min(12, numel(preview)));
                if numel(preview)>12, shown{end+1} = sprintf('… and %d more', numel(preview)-12); end
                message = sprintf('Change anatomical IDs for %d neurons? This does not flip the displayed image.\n\n%s\n\nThe complete change is one Undo step.', numel(changes), strjoin(shown, '\n'));
                answer = uiconfirm(app.CELL_ID, message, 'Anatomical L/R correction', ...
                    'Options', {'Swap anatomical IDs', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(answer, 'Swap anatomical IDs'), return; end
                Program.GUI.ManualIDService.checkBulkContext(app, source);
                [next, event] = Annotations.Store.batch(store, changes, struct('confirmed', true, 'reason', 'Explicit anatomical L/R correction'));
                next = Program.GUI.ManualIDService.persist(app, next);
                Program.GUI.ManualIDService.apply(app.image_neurons, next);
                app.manualIDDidCommit([], struct('changed', true, 'event', event), false);
                if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app, app.selected_neuron); end
            catch ME
                uialert(app.CELL_ID, ME.message, 'Anatomical IDs could not be changed');
            end
        end

        function nextUnresolved(app)
            Program.GUI.ManualIDService.ensure(app);
            indices = find(arrayfun(@(n) ~n.has_confirmed_annotation() && ...
                (any(strcmp(n.annotation_record.kind, {'individual', 'unresolved_set', 'legacy_issue'})) || ...
                 strcmp(n.annotation_record.review, 'needs-review')), app.image_neurons.neurons));
            if isempty(indices), uialert(app.CELL_ID, 'There are no unresolved human IDs.', 'Resolve ID'); return; end
            selected = app.selected_neuron;
            next = indices(1);
            if ~isempty(selected)
                later = indices(indices > selected); if ~isempty(later), next = later(1); end
            end
            app.selectManualID(next);
        end

        function exportDialog(app)
            try
                store = Program.GUI.ManualIDService.ensure(app);
                [~, stem] = fileparts(app.image_file);
                [name, folder, filter] = Program.GUI.ManualIDService.selectFile(app, 'uiputfile', ...
                    {'*.mat', 'Full annotations and evidence (*.mat)'; '*.csv', 'Legacy analysis CSV + full annotation companion'}, ...
                    'Export neuron IDs', [stem '_annotations.mat']);
                if isequal(name, 0), return; end
                selected_path = fullfile(folder, name);
                path = Program.GUI.ManualIDService.exportPath(selected_path, filter);
                destinations = {path};
                if filter == 2
                    [folder, stem] = fileparts(path);
                    destinations{end+1} = fullfile(folder, [stem '_annotations.mat']);
                end
                if any(cellfun(@isfolder, destinations))
                    error('Annotations:ExchangeFolder', 'An export destination is a folder. Choose another filename.');
                end
                % The native picker confirms only its own selected filename.
                unchecked = destinations;
                if strcmp(path, selected_path), unchecked(1) = []; end
                existing = unchecked(cellfun(@isfile, unchecked));
                if ~isempty(existing)
                    answer = uiconfirm(app.CELL_ID, ...
                        sprintf('Replace these existing export files?\n%s', strjoin(existing, '\n')), ...
                        'Replace exported IDs', 'Options', {'Replace', 'Cancel'}, ...
                        'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(answer, 'Replace'), return; end
                end
                if filter == 1
                    Annotations.Exchange.export(path, store);
                else
                    answer = uiconfirm(app.CELL_ID, 'The analysis CSV contains compatible resolved IDs. Tentative and unresolved claims, attributes, history and evidence are retained in the accompanying annotation MAT file.', ...
                        'CSV compatibility', 'Options', {'Export both files', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                    if ~strcmp(answer, 'Export both files'), return; end
                    Output.ImageAnalysis.exportID2CSV(path, app.image_prefs, app.image_data, ...
                        app.image_data_zscored, app.image_neurons, app.image_um_scale);
                    [folder, stem] = fileparts(path);
                    Annotations.Exchange.export(fullfile(folder, [stem '_annotations.mat']), store);
                end
                uialert(app.CELL_ID, ['Exported to ' path], 'Neuron IDs exported', 'Icon', 'success');
            catch ME
                uialert(app.CELL_ID, ME.message, 'Neuron IDs could not be exported');
            end
        end

        function path = exportPath(path, filter)
            % Keep the extension consistent with the selected export format.
            extensions = {'.mat', '.csv'};
            if ~isnumeric(filter) || ~isscalar(filter) || ~ismember(filter, [1 2])
                error('Annotations:ExchangeFormat', 'Choose a supported annotation export format.');
            end
            [folder, stem, extension] = fileparts(char(string(path)));
            while any(strcmpi(extension, extensions))
                path = fullfile(folder, stem);
                [folder, stem, extension] = fileparts(path);
            end
            path = [fullfile(folder, [stem extension]) extensions{filter}];
        end

        function [name, folder, filter] = selectFile(app, picker, varargin)
            % Keep the native chooser in front of the app and prevent reentry.
            name = 0; folder = 0; filter = 0;
            if ~any(strcmp(picker, {'uigetfile', 'uiputfile'}))
                error('Annotations:FileDialog', 'Choose a supported file dialog.');
            end
            if isequal(getappdata(app.CELL_ID, 'manual_id_file_dialog'), true), return; end
            visible = app.CELL_ID.Visible;
            setappdata(app.CELL_ID, 'manual_id_file_dialog', true);
            cleanup = onCleanup(@() Program.GUI.ManualIDService.finishFileDialog(app, visible));
            Program.GUI.ManualIDController.close(app);
            app.CELL_ID.Visible = 'off';
            [name, folder, filter] = feval(picker, varargin{:});
        end

        function finishFileDialog(app, visible)
            if ~isvalid(app) || ~isvalid(app.CELL_ID), return; end
            rmappdata(app.CELL_ID, 'manual_id_file_dialog');
            app.CELL_ID.Visible = visible;
        end

        function recoveryDialog(app)
            try
                if isempty(app.image_neurons) || isempty(app.id_file)
                    error('Annotations:NoSource', 'Open the original image before reviewing ID recovery.');
                end
                source = Program.GUI.ManualIDService.bulkContext(app);
                report = Annotations.Recovery.inspect(app.id_file, app.image_neurons);
                if report.blocked, error('Annotations:RecoveryBlocked', '%s', report.message); end
                valid = find([report.candidates.valid]);
                labels = {report.candidates(valid).label};
                [selection, accepted] = listdlg('Name', 'Review ID recovery', ...
                    'PromptString', 'Choose the annotation source to review. Nothing is applied yet.', ...
                    'SelectionMode', 'single', 'ListString', labels, 'ListSize', [470 130]);
                if ~accepted, return; end
                chosen = report.candidates(valid(selection));
                current = app.image_neurons.annotation_store;
                changes = 0;
                for i = 1:numel(app.image_neurons.neurons)
                    owner = app.image_neurons.neurons(i).annotation_id;
                    before = Annotations.Store.record(current, owner);
                    after = Annotations.Store.record(chosen.store, owner);
                    fields = {'kind', 'candidates', 'certainty', 'review', 'attributes', 'issue'};
                    for j = 1:numel(fields)
                        if ~isequaln(before.(fields{j}), after.(fields{j}))
                            changes = changes + 1; break;
                        end
                    end
                end
                message = sprintf('%s\n\nReview will update %d neuron records and rebuild their compatibility fields. Current geometry is preserved. Verified copies of both the current file and previous recovery file will be retained.\n\n%s', ...
                    chosen.label, changes, strjoin(chosen.warnings, ' '));
                answer = uiconfirm(app.CELL_ID, message, 'Reconcile annotation save', ...
                    'Options', {'Reconcile IDs', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(answer, 'Reconcile IDs'), return; end
                Program.GUI.ManualIDService.checkBulkContext(app, source);
                prepared = Annotations.Recovery.prepare(report, chosen.id, app.image_neurons, ...
                    struct('context', app.worm, 'mp_params', app.mp_params));
                [saved, fingerprint, retained] = Annotations.Recovery.publish(prepared);
                Program.GUI.ManualIDService.apply(app.image_neurons, saved.annotation_store);
                app.image_neurons.annotation_read_only_reason = '';
                setappdata(app.CELL_ID, 'manual_id_file_snapshot', ...
                    struct('key', Program.GUI.ManualIDService.fileKey(app), 'fingerprint', fingerprint));
                app.manualIDDidCommit([], struct('changed', true), false);
                if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app, app.selected_neuron); end
                uialert(app.CELL_ID, sprintf('Reconciled IDs. Retained original files:\n%s', strjoin(retained, '\n')), ...
                    'ID recovery complete', 'Icon', 'success');
            catch ME
                if strcmp(ME.identifier, 'Annotations:PublishedSave')
                    app.image_neurons.annotation_read_only_reason = ...
                        'Recovery may have been published but could not be verified. Reopen the image and review recovery before further editing.';
                end
                uialert(app.CELL_ID, ME.message, 'ID recovery could not complete');
            end
        end

        function importDialog(app)
            try
                store = Program.GUI.ManualIDService.ensure(app);
                source = struct('image', app.image_neurons, 'source_id', store.source_id, ...
                    'worm', app.worm, 'positions', app.image_neurons.get_positions());
                [name, folder] = Program.GUI.ManualIDService.selectFile(app, ...
                    'uigetfile', '*.mat', 'Import annotations for this image');
                if isequal(name, 0), return; end
                [imported, report] = Annotations.Exchange.read(fullfile(folder, name));
                if ~report.catalog_compatible
                    error('Annotations:CatalogMigration', 'This export requires an explicit catalog migration before it can be restored.');
                end
                owners = {app.image_neurons.neurons.annotation_id};
                if ~strcmp(imported.source_id, store.source_id) || ~all(ismember(owners, {imported.records.owner_id}))
                    error('Annotations:Correspondence', 'These annotations do not share this image''s stable neuron owners. An explicit correspondence is required; row numbers are not sufficient.');
                end
                [imported, ~] = Annotations.Store.recontextualize(imported, app.worm);
                answer = uiconfirm(app.CELL_ID, 'Import the exported annotations for these same neurons? Current evidence and history will be retained. Anatomical context conflicts remain unresolved. This annotation change can be undone.', ...
                    'Import annotations', 'Options', {'Import', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(answer, 'Import'), return; end
                current = Program.GUI.ManualIDService.ensure(app);
                if ~isequal(source.image, app.image_neurons) || ~strcmp(source.source_id, current.source_id) || ...
                        ~isequaln(source.worm, app.worm) || ~isequaln(source.positions, app.image_neurons.get_positions())
                    error('Annotations:StaleSource', 'The source or context changed while import was open. Review the source before importing.');
                end
                [next, ~] = Annotations.Store.restore(current, imported, struct('confirmed', true, 'owner_ids', {owners}));
                next = Program.GUI.ManualIDService.persist(app, next);
                Program.GUI.ManualIDService.apply(app.image_neurons, next);
                app.manualIDDidCommit([], struct('changed', true), false);
                if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app, app.selected_neuron); end
            catch ME
                uialert(app.CELL_ID, ME.message, 'Annotations could not be imported');
            end
        end

        function value = bulkContext(app)
            value = struct('image', app.image_neurons, 'file', app.image_file, ...
                'id_file', app.id_file, 'worm', app.worm, ...
                'owners', {{app.image_neurons.neurons.annotation_id}}, ...
                'positions', app.image_neurons.get_positions(), ...
                'store', app.image_neurons.annotation_store);
        end

        function checkBulkContext(app, expected)
            current = Program.GUI.ManualIDService.bulkContext(app);
            if ~isequaln(current, expected)
                error('Annotations:StaleSource', 'The source or its annotations changed while this action was open. Review them before trying again.');
            end
        end

        function value = digest(data)
            bytes = getByteStreamFromArray(data);
            md = java.security.MessageDigest.getInstance('SHA-256');
            md.update(bytes);
            value = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
        end
    end
end
