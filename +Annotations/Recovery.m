classdef Recovery
    %RECOVERY Reconcile explicit annotation choices without guessing correspondence.
    methods (Static)
        function report = inspect(path, image)
            path=char(string(path));
            report=struct('path',path,'expected',Annotations.Store.fingerprint(path), ...
                'active_ids',{{}},'geometry','','blocked',false,'message','', ...
                'candidates',repmat(Annotations.Recovery.candidate(),1,0),'current_payload',struct());
            if isfile([path '.processing.pending.json'])
                report.blocked=true;
                report.message='An interrupted image/ID processing save must be recovered as a pair before annotation reconciliation.';
                return;
            end
            try
                report.active_ids=Annotations.Recovery.activeIds(image);
                report.geometry=Annotations.Recovery.geometry(image);
            catch ME
                report.blocked=true; report.message=ME.message; return;
            end
            current=struct(); backup=struct();
            if report.expected.exists
                try, current=load(path); catch, end
            end
            report.current_payload=current;
            backup_path=[path '.lastgood.mat'];
            if isfile(backup_path)
                try, backup=load(backup_path); catch, end
            end
            if isfield(current,'annotation_store')
                item=Annotations.Recovery.inspectStore('current-structured','Current structured annotations', ...
                    path,current.annotation_store,image);
                report.candidates(end+1)=item;
            end
            if isfield(backup,'annotation_store')
                item=Annotations.Recovery.inspectStore('lastgood','Previous verified annotation save', ...
                    backup_path,backup.annotation_store,image);
                report.candidates(end+1)=item;
            end
            % Legacy fields can represent external edits, but only stable IDs establish ownership.
            if isfield(current,'neurons') && isa(current.neurons,'Neurons.Image')
                try
                    legacy_ids=Annotations.Recovery.activeIds(current.neurons);
                    if ~isequal(sort(legacy_ids),sort(report.active_ids))
                        error('Annotations:RecoveryCorrespondence','The legacy file does not preserve the active stable neuron owners.');
                    end
                    context=struct();
                    active_store=image.annotation_store;
                    if isfield(active_store,'context'), context=active_store.context; end
                    if isfield(active_store,'source_id'), context.source_id=active_store.source_id; end
                    if isfield(active_store,'specimen_id'), context.specimen_id=active_store.specimen_id; end
                    if isfield(backup,'annotation_store') && ...
                            ~isfield(context,'source_id')
                        context=backup.annotation_store.context;
                        context.source_id=backup.annotation_store.source_id;
                        context.specimen_id=backup.annotation_store.specimen_id;
                    end
                    [migrated,~]=Annotations.Store.create(current.neurons.neurons,context);
                    migrated.context.recovery_mode='explicit-legacy-migration';
                    different=~isfield(current,'annotation_store');
                    if ~different
                        expected=Annotations.Store.project(current.annotation_store,current.neurons);
                        for i=1:numel(expected)
                            n=current.neurons.neurons(i); p=expected(i);
                            different=different || ~strcmp(n.annotation,p.annotation) || ...
                                ~isequaln(n.annotation_confidence,p.annotation_confidence) || ...
                                ~isequaln(n.is_annotation_on,p.is_annotation_on) || ~isequaln(n.is_emphasized,p.is_emphasized);
                        end
                    end
                    if different
                        item=Annotations.Recovery.inspectStore('current-legacy','Current legacy annotation fields (explicit migration)', ...
                            path,migrated,image);
                        item.warnings={'Legacy fields cannot reconstruct omitted ambiguity, original model scores, or human provenance. The raw current file will be retained.'};
                        report.candidates(end+1)=item;
                    end
                catch ME
                    item=Annotations.Recovery.candidate(); item.id='current-legacy';
                    item.label='Current legacy annotation fields'; item.source_path=path;
                    item.message=ME.message; item.issues=struct('code',ME.identifier,'message',ME.message);
                    report.candidates(end+1)=item;
                end
            end
            if isempty(report.candidates) || ~any([report.candidates.valid])
                report.blocked=true;
                report.message='No recovery candidate has the same stable active neuron owners. Reconciliation cannot match neurons by row or regenerate their IDs.';
            end
        end

        function prepared = prepare(report, selection, image, options)
            if nargin<4, options=struct(); end
            if report.blocked, error('Annotations:RecoveryBlocked','%s',report.message); end
            if isfile([report.path '.processing.pending.json'])
                error('Annotations:RecoveryBlocked','Recover the pending image/ID pair before annotation reconciliation.');
            end
            if ~Annotations.Recovery.sameFingerprint(Annotations.Store.fingerprint(report.path),report.expected)
                error('Annotations:StaleRecovery','The current ID file changed while recovery was open. Inspect it again.');
            end
            if ~isequal(sort(Annotations.Recovery.activeIds(image)),sort(report.active_ids)) || ...
                    ~strcmp(Annotations.Recovery.geometry(image),report.geometry)
                error('Annotations:RecoveryCorrespondence','The active neurons or geometry changed while recovery was open.');
            end
            index=find(strcmp({report.candidates.id},char(string(selection))),1);
            if isempty(index) || ~report.candidates(index).valid
                error('Annotations:RecoverySelection','Explicitly choose a valid inspected recovery candidate.');
            end
            chosen=report.candidates(index);
            if ~Annotations.Recovery.sameFingerprint(Annotations.Store.fingerprint(chosen.source_path),chosen.fingerprint)
                error('Annotations:StaleRecovery','The selected recovery file changed. Inspect the available saves again.');
            end
            selected=chosen.store; Annotations.Store.validate(selected);
            if isfield(options,'context'), [selected,~]=Annotations.Store.recontextualize(selected,options.context); end
            base=struct();
            if isfield(report.current_payload,'annotation_store')
                candidate=report.current_payload.annotation_store;
                try
                    Annotations.Store.validate(candidate);
                    Annotations.Recovery.checkOwners(candidate,image);
                    if ~Annotations.Recovery.isDerived(candidate) && strcmp(candidate.source_id,selected.source_id), base=candidate; end
                catch
                    % Invalid or unrelated history remains in the raw recovery copy.
                end
            end
            if isempty(fieldnames(base))
                candidate=image.annotation_store;
                try
                    Annotations.Store.validate(candidate);
                    Annotations.Recovery.checkOwners(candidate,image);
                    if ~Annotations.Recovery.isDerived(candidate) && strcmp(candidate.source_id,selected.source_id), base=candidate; end
                catch
                end
            end
            if ~isempty(fieldnames(base)) && ~isequaln(base,selected)
                if isfield(options,'context'), [base,~]=Annotations.Store.recontextualize(base,options.context); end
                [selected,~]=Annotations.Store.restore(base,selected, ...
                    struct('confirmed',true,'owner_ids',{report.active_ids}, ...
                    'reason','Explicit annotation recovery reconciliation'));
            end
            payload=report.current_payload;
            clone=Annotations.Recovery.copyImage(image);
            projection=Annotations.Store.project(selected,clone.neurons);
            for i=1:numel(clone.neurons)
                p=projection(i); n=clone.neurons(i);
                n.annotation=p.annotation; n.annotation_confidence=p.annotation_confidence;
                n.is_annotation_on=p.is_annotation_on; n.is_emphasized=p.is_emphasized;
                n.annotation_record=p.annotation_record;
            end
            clone.annotation_store=selected; clone.annotation_read_only_reason='';
            payload.neurons=clone; payload.annotation_store=selected;
            payload.version=Program.ProgramInfo.version;
            if isfield(options,'mp_params'), payload.mp_params=options.mp_params; end
            if ~isfield(payload,'mp_params') || ~isstruct(payload.mp_params), payload.mp_params=struct(); end
            payload.mp_params.k=numel(clone.neurons);
            prepared=struct('path',report.path,'payload',payload,'expected',report.expected, ...
                'selection',chosen.id,'source_path',chosen.source_path, ...
                'source_fingerprint',chosen.fingerprint,'active_ids',{report.active_ids}, ...
                'geometry',report.geometry);
        end

        function [payload, fingerprint, retained] = publish(prepared, options)
            if nargin<2, options=struct(); end
            path=prepared.path;
            if isfile([path '.processing.pending.json'])
                error('Annotations:RecoveryBlocked','Recover the pending image/ID pair before annotation reconciliation.');
            end
            if ~Annotations.Recovery.sameFingerprint(Annotations.Store.fingerprint(path),prepared.expected) || ...
                    ~Annotations.Recovery.sameFingerprint(Annotations.Store.fingerprint(prepared.source_path),prepared.source_fingerprint)
                error('Annotations:StaleRecovery','An ID or selected recovery file changed. Inspect it again before reconciling.');
            end
            retained={};
            if prepared.expected.exists
                retained{end+1}=Annotations.Recovery.preserve(path,prepared.expected,'before-reconcile');
                options.validated_recovery_original=retained{end};
            end
            backup=[path '.lastgood.mat'];
            if isfile(backup)
                retained{end+1}=Annotations.Recovery.preserve(backup,Annotations.Store.fingerprint(backup),'before-reconcile');
            end
            [payload,fingerprint]=Annotations.Store.save(path,prepared.payload,prepared.expected,options);
        end
    end

    methods (Static, Access=private)
        function item = candidate()
            item=struct('id','','label','','source_path','','fingerprint',struct(), ...
                'store',struct(),'valid',false,'message','','warnings',{{}}, ...
                'issues',struct('code',{},'message',{}));
        end

        function item = inspectStore(id,label,path,store,image)
            item=Annotations.Recovery.candidate(); item.id=id; item.label=label;
            item.source_path=path; item.fingerprint=Annotations.Store.fingerprint(path); item.store=store;
            try
                Annotations.Store.validate(store); Annotations.Recovery.checkOwners(store,image);
                if Annotations.Recovery.isDerived(store)
                    error('Annotations:RecoveryDerived','A compatibility-only view is not an authoritative structured recovery candidate.');
                end
                item.valid=true;
            catch ME
                item.message=ME.message; item.issues=struct('code',ME.identifier,'message',ME.message);
            end
        end

        function yes = isDerived(store)
            yes=isfield(store,'context') && isfield(store.context,'recovery_mode') && ...
                strcmp(store.context.recovery_mode,'compatibility-only');
        end

        function ids = activeIds(image)
            if ~isa(image,'Neurons.Image') || isempty(image.neurons)
                error('Annotations:RecoveryCorrespondence','Open the original image with its stable neuron owners before reconciling IDs.');
            end
            ids={image.neurons.annotation_id};
            if any(cellfun(@isempty,ids)) || numel(unique(ids))~=numel(ids)
                error('Annotations:RecoveryCorrespondence','Recovery requires preserved unique neuron IDs; it cannot generate correspondence from array rows.');
            end
        end

        function checkOwners(store,image)
            ids=Annotations.Recovery.activeIds(image);
            if ~all(ismember(ids,{store.owners.owner_id}))
                error('Annotations:RecoveryCorrespondence','The recovery candidate does not contain every active stable neuron owner.');
            end
            extras=store.records(~ismember({store.records.owner_id},ids));
            if any(~strcmp({extras.kind},'unassigned'))
                error('Annotations:RecoveryCorrespondence','The recovery candidate has anatomical claims for owners absent from the active image.');
            end
        end

        function signature = geometry(image)
            value=struct('ids',{Annotations.Recovery.activeIds(image)}, ...
                'positions',image.get_positions(),'scale',image.scale);
            bytes=getByteStreamFromArray(value); digest=java.security.MessageDigest.getInstance('SHA-256');
            digest.update(bytes); signature=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
        end

        function same = sameFingerprint(a,b)
            same=isequal(a.exists,b.exists) && strcmp(a.sha256,b.sha256) && a.generation==b.generation;
        end

        function destination = preserve(source,expected,label)
            destination=[source '.' label '.' char(java.util.UUID.randomUUID()) '.mat'];
            [ok,message]=copyfile(source,destination);
            if ~ok, error('Annotations:RecoveryCopy','Cannot retain the original save: %s',message); end
            copy=Annotations.Store.fingerprint(destination);
            if ~Annotations.Recovery.sameFingerprint(copy,expected)
                error('Annotations:RecoveryCopy','The retained original failed byte verification. No reconciliation was published.');
            end
        end

        function clone = copyImage(image)
            clone=Neurons.Image([]); names=properties(image);
            for i=1:numel(names)
                if ~strcmp(names{i},'neurons'), clone.(names{i})=image.(names{i}); end
            end
            for i=1:numel(image.neurons)
                n=Neurons.Neuron; fields=properties(n);
                for j=1:numel(fields), n.(fields{j})=image.neurons(i).(fields{j}); end
                clone.neurons(i)=n;
            end
        end
    end
end
