classdef IDWriters
    %IDWRITERS Keep legacy jobs and paired image saves from erasing identities.
    methods (Static)
        function idFile = guardBatch(file, method)
            if nargin < 2, method = 'batch operation'; end
            [folder, name, extension] = fileparts(char(string(file)));
            if strcmpi(extension, '.mat') && endsWith(name, '_ID')
                idFile = char(string(file));
            else
                idFile = fullfile(folder, [name '_ID.mat']);
            end
            Annotations.IDWriters.assertLegacy(idFile, method);
        end

        function expected = legacySnapshot(idFile, method)
            if nargin < 2, method = 'batch operation'; end
            Annotations.IDWriters.assertLegacy(idFile, method);
            expected = Annotations.Store.fingerprint(idFile);
        end

        function publishLegacy(idFile, updates, expected)
            % The second check also protects against a new interactive save mid-job.
            if ~isstruct(updates) || ~isscalar(updates)
                error('Annotations:SavePayload', 'Batch ID updates must be a scalar payload.');
            end
            if isfield(updates, 'annotation_store') || ...
                    (isfield(updates, 'neurons') && isa(updates.neurons, 'Neurons.Image') && ...
                    ~isempty(fieldnames(updates.neurons.annotation_store)))
                error('Annotations:LegacyBatchProtected', 'Structured identities require the interactive annotation writer, not a legacy batch publication.');
            end
            idFile = Annotations.IDWriters.absolute(idFile);
            folder = fileparts(idFile);
            if exist(folder, 'dir') ~= 7
                error('Annotations:SaveFolder', 'The ID destination directory does not exist.');
            end
            lease = java.io.RandomAccessFile([idFile '.annotations.lock'], 'rw');
            leaseCleanup = onCleanup(@() lease.close());
            lock = Annotations.IDWriters.lock(lease);
            lockCleanup = onCleanup(@() Annotations.IDWriters.release(lock));
            Annotations.IDWriters.assertLegacy(idFile, 'legacy batch publication');
            Annotations.IDWriters.checkFingerprint(idFile, expected);
            payload = struct();
            if expected.exists, payload = load(idFile); end
            fields = fieldnames(updates);
            for i = 1:numel(fields), payload.(fields{i}) = updates.(fields{i}); end
            temporary = [tempname(folder) '.mat'];
            cleanup = onCleanup(@() Annotations.IDWriters.remove(temporary));
            builtin('save', temporary, '-struct', 'payload', '-v7.3');
            verified = load(temporary);
            if ~all(isfield(verified, fields))
                error('Annotations:SaveVerification', 'The staged batch ID file is incomplete.');
            end
            Annotations.IDWriters.atomicMove(temporary, idFile);
        end

        function [payload, published] = publishPair(imageFile, imageStaged, idFile, payload, expectedImage, expectedID, options)
            if nargin < 7, options = struct(); end
            imageFile = Annotations.IDWriters.absolute(imageFile);
            idFile = Annotations.IDWriters.absolute(idFile);
            if strcmp(imageFile, idFile) || ~expectedImage.exists
                error('Annotations:ProcessingSave', 'The image and ID files require separate valid destinations.');
            end
            if ~isfield(payload, 'annotation_store')
                error('Annotations:SavePayload', 'A processing save must retain its authoritative annotation store.');
            end
            pending = [idFile '.processing.pending.json'];
            if isfile(pending)
                error('Annotations:ProcessingRecovery', 'A previous image/ID save requires recovery. Its marker is %s.', pending);
            end
            Annotations.Store.validate(payload.annotation_store);
            imageFolder = fileparts(imageFile); idFolder = fileparts(idFile);
            if ~isfolder(imageFolder) || ~isfolder(idFolder)
                error('Annotations:SaveFolder', 'The image and ID destination directories must exist.');
            end
            payload.annotation_store.generation = expectedID.generation + 1;
            if isfield(payload, 'neurons') && isa(payload.neurons, 'Neurons.Image')
                payload.neurons = Program.GUI.ManualIDService.copyImage(payload.neurons);
                payload.neurons.annotation_store = payload.annotation_store;
            end
            idStaged = [tempname(idFolder) '.mat'];
            stageCleanup = onCleanup(@() Annotations.IDWriters.remove(idStaged));
            builtin('save', idStaged, '-struct', 'payload', '-v7.3');
            verify = load(idStaged);
            Annotations.Store.validate(verify.annotation_store);
            if ~isequaln(verify.annotation_store, payload.annotation_store)
                error('Annotations:SaveVerification', 'The staged processing identities did not round-trip.');
            end
            issues = Annotations.Store.verifyLineage(idStaged, verify);
            if any(~strcmp({issues.code}, 'evidence-unavailable'))
                error('Annotations:SaveVerification', 'The staged processing neuron projection contradicts the authoritative identity store.');
            end
            newImage = Annotations.Store.fingerprint(imageStaged);
            newID = Annotations.Store.fingerprint(idStaged);
            if ~newImage.exists, error('Annotations:ProcessingSave', 'The staged image is unavailable.'); end

            lease = java.io.RandomAccessFile([idFile '.annotations.lock'], 'rw');
            leaseCleanup = onCleanup(@() lease.close());
            lock = Annotations.IDWriters.lock(lease);
            lockCleanup = onCleanup(@() Annotations.IDWriters.release(lock));
            if isfile(pending)
                error('Annotations:ProcessingRecovery', 'Another image/ID save requires recovery before continuing.');
            end
            Annotations.IDWriters.checkFingerprint(imageFile, expectedImage);
            Annotations.IDWriters.checkFingerprint(idFile, expectedID);
            imageBackup = [tempname(imageFolder) '.previous-image.mat'];
            idBackup = [tempname(idFolder) '.previous-ID.mat'];
            lineage = [idFile '.annotations.lineage.json'];
            lineageBackup = [tempname(idFolder) '.previous-lineage.json'];
            hadLineage = isfile(lineage);
            paths = {imageBackup, idBackup, lineageBackup};
            backupCleanup = onCleanup(@() Annotations.IDWriters.cleanupPair(paths, pending));
            Annotations.IDWriters.backup(imageFile, imageBackup);
            if expectedID.exists, Annotations.IDWriters.backup(idFile, idBackup); end
            if hadLineage, Annotations.IDWriters.backup(lineage, lineageBackup); end
            journal = struct('schema_version', 1, 'operation', 'processing-image-and-identities', ...
                'image_file', imageFile, 'id_file', idFile, 'previous_image', expectedImage, ...
                'previous_id', expectedID, 'pending_image', newImage, 'pending_id', newID, ...
                'image_backup', imageBackup, 'id_backup', idBackup, ...
                'lineage_backup', lineageBackup, 'had_lineage', hadLineage);
            Annotations.IDWriters.writeJSON(pending, journal);
            imagePublished = false; idPublished = false;
            try
                nextLineage = struct('schema_version', 2, 'source_id', payload.annotation_store.source_id, ...
                    'previous', expectedID, 'pending_generation', payload.annotation_store.generation, ...
                    'pending_sha256', newID.sha256);
                Annotations.IDWriters.writeJSON(lineage, nextLineage);
                Annotations.IDWriters.inject(options, 'before_image_replace');
                Annotations.IDWriters.atomicMove(imageStaged, imageFile); imagePublished = true;
                Annotations.IDWriters.inject(options, 'after_image_replace');
                Annotations.IDWriters.atomicMove(idStaged, idFile); idPublished = true;
                Annotations.IDWriters.inject(options, 'after_id_replace');
                currentImage = Annotations.Store.fingerprint(imageFile);
                published = Annotations.Store.fingerprint(idFile);
                if ~strcmp(currentImage.sha256, newImage.sha256) || ~strcmp(published.sha256, newID.sha256)
                    error('Annotations:PublishedSave', 'The published image/ID pair could not be verified.');
                end
                if expectedID.exists, Annotations.IDWriters.restore(idBackup, [idFile '.lastgood.mat']); end
                Annotations.IDWriters.remove(pending);
            catch ME
                errors = {};
                try
                    if imagePublished, Annotations.IDWriters.restore(imageBackup, imageFile); end
                    Annotations.IDWriters.checkFingerprint(imageFile, expectedImage);
                catch recovery, errors{end+1} = recovery.message; end
                try
                    if expectedID.exists && idPublished
                        Annotations.IDWriters.restore(idBackup, idFile);
                    elseif ~expectedID.exists && idPublished
                        Annotations.IDWriters.remove(idFile);
                    end
                    Annotations.IDWriters.checkFingerprint(idFile, expectedID);
                catch recovery, errors{end+1} = recovery.message; end
                try
                    if hadLineage, Annotations.IDWriters.restore(lineageBackup, lineage);
                    else, Annotations.IDWriters.remove(lineage); end
                catch recovery, errors{end+1} = recovery.message; end
                if ~isempty(errors)
                    error('Annotations:ProcessingRecovery', ...
                        'Save failed: %s. Recovery files are recorded in %s. %s', ...
                        ME.message, pending, strjoin(errors, ' '));
                end
                Annotations.IDWriters.remove(pending);
                rethrow(ME);
            end
        end
    end

    methods (Static, Access = private)
        function assertLegacy(path, method)
            path = char(string(path));
            protected = isfile([path '.annotations.lineage.json']) || isfile([path '.processing.pending.json']);
            if ~protected && isfile(path)
                try
                    variables = whos('-file', path, 'annotation_store');
                    protected = ~isempty(variables);
                    if ~protected
                        variables = whos('-file', path, 'neurons');
                        if ~isempty(variables)
                            loaded = load(path, 'neurons');
                            if isa(loaded.neurons, 'Neurons.Image') && isprop(loaded.neurons, 'annotation_store')
                                protected = ~isempty(fieldnames(loaded.neurons.annotation_store));
                            end
                        end
                    end
                catch ME
                    error('Annotations:UnreadableID', 'Cannot verify the existing ID file before %s: %s', method, ME.message);
                end
            end
            if protected
                error('Annotations:LegacyBatchProtected', ...
                    '%s cannot overwrite versioned identities or recovery metadata. Open this image in the app and use the interactive detection/ID action instead. Existing annotations were preserved.', method);
            end
        end

        function value = absolute(path)
            value = char(java.io.File(char(string(path))).getCanonicalPath());
        end

        function lock = lock(lease)
            try, lock = lease.getChannel().tryLock();
            catch, error('Annotations:WriterBusy', 'Another app is writing these identities. Try again after it finishes.'); end
            if isempty(lock), error('Annotations:WriterBusy', 'Another app is writing these identities.'); end
        end

        function release(lock)
            try
                if lock.isValid(), lock.release(); end
            catch
                % Closing the writer channel also releases its lease.
            end
        end

        function checkFingerprint(path, expected)
            current = Annotations.Store.fingerprint(path);
            if current.exists ~= expected.exists || ~strcmp(current.sha256, expected.sha256) || current.generation ~= expected.generation
                error('Annotations:StaleSave', 'The image or ID file changed after this operation began. Reload or reconcile the newer save; pending work was preserved.');
            end
        end

        function backup(source, destination)
            % A same-filesystem link avoids another full image allocation on disk.
            try
                java.nio.file.Files.createLink(java.io.File(destination).toPath(), java.io.File(source).toPath());
            catch
                [ok, message] = copyfile(source, destination);
                if ~ok, error('Annotations:RecoverySave', 'Cannot preserve the previous file: %s', message); end
            end
        end

        function restore(backup, destination)
            temporary = [tempname(fileparts(destination)) '.restore'];
            cleanup = onCleanup(@() Annotations.IDWriters.remove(temporary));
            Annotations.IDWriters.backup(backup, temporary);
            Annotations.IDWriters.atomicMove(temporary, destination);
        end

        function writeJSON(path, value)
            temporary = [tempname(fileparts(path)) '.json'];
            cleanup = onCleanup(@() Annotations.IDWriters.remove(temporary));
            fid = fopen(temporary, 'w');
            if fid < 0, error('Annotations:RecoverySave', 'Cannot write image/ID recovery metadata.'); end
            stream = onCleanup(@() fclose(fid));
            fwrite(fid, unicode2native(jsonencode(value), 'UTF-8'), 'uint8'); clear stream;
            Annotations.IDWriters.atomicMove(temporary, path);
        end

        function cleanupPair(paths, pending)
            if isfile(pending), return; end
            for i = 1:numel(paths), Annotations.IDWriters.remove(paths{i}); end
        end

        function remove(path)
            if isfile(path), delete(path); end
        end

        function atomicMove(source, destination)
            options = javaArray('java.nio.file.CopyOption', 2);
            options(1) = java.nio.file.StandardCopyOption.ATOMIC_MOVE;
            options(2) = java.nio.file.StandardCopyOption.REPLACE_EXISTING;
            try
                java.nio.file.Files.move(java.io.File(source).toPath(), java.io.File(destination).toPath(), options);
            catch ME
                error('Annotations:AtomicSave', 'The destination does not support a verified atomic replacement: %s', ME.message);
            end
        end

        function inject(options, stage)
            if isfield(options, 'fail_at') && strcmp(options.fail_at, stage)
                error('Annotations:InjectedFailure', 'Injected paired save failure at %s.', stage);
            end
        end
    end
end
