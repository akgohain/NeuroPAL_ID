classdef JobIO
    %JOBIO Transactional worker interchange for tracking jobs.

    methods (Static)
        function workspace = stage(request)
            request = Tracking.JobContract.request(request);
            workspace = char(string(request.output_dir));
            if exist(workspace, 'dir') == 7 || exist(workspace, 'file') == 2
                error('Tracking:JobIO:WorkspaceExists', ...
                    'Refusing to reuse tracking workspace: %s', workspace);
            end
            if exist(request.source, 'file') ~= 2
                error('Tracking:JobIO:MissingSource', ...
                    'Tracking source does not exist: %s', request.source);
            end
            request.source_signature = ...
                DataHandling.Helpers.large_file.source_signature(request.source);

            [parent, ~, ~] = fileparts(workspace);
            if isempty(parent)
                parent = pwd;
            end
            if exist(parent, 'dir') ~= 7
                error('Tracking:JobIO:MissingWorkspaceParent', ...
                    'Tracking workspace parent does not exist: %s', parent);
            end
            mkdir(workspace);
            try
                request_path = fullfile(workspace, 'request.json');
                state_path = fullfile(workspace, 'state.json');
                Tracking.JobIO.writeJsonExclusive(request_path, request);
                state = struct( ...
                    'schema_version', 1, ...
                    'backend', request.backend, ...
                    'status', 'staged', ...
                    'created_at', Tracking.JobIO.timestamp(), ...
                    'request_file', 'request.json');
                Tracking.JobIO.writeJsonExclusive(state_path, state);
            catch ME
                Tracking.JobIO.removeDirectory(workspace);
                rethrow(ME)
            end
        end

        function manifest = writeResult(workspace, observations, video_info, native_artifacts)
            arguments
                workspace {mustBeTextScalar}
                observations table
                video_info struct
                native_artifacts = strings(0, 1)
            end
            workspace = char(string(workspace));
            request_path = fullfile(workspace, 'request.json');
            result_path = fullfile(workspace, 'result.json');
            observations_path = fullfile(workspace, 'observations.csv');
            if exist(request_path, 'file') ~= 2
                error('Tracking:JobIO:MissingRequest', ...
                    'Tracking workspace is missing request.json: %s', workspace);
            end
            if exist(result_path, 'file') == 2 || exist(observations_path, 'file') == 2
                error('Tracking:JobIO:ResultExists', ...
                    'Refusing to overwrite an existing tracking result in %s.', workspace);
            end

            request = Tracking.JobContract.request(jsondecode(fileread(request_path)));
            Tracking.JobIO.validateWorkspaceRequest(workspace, request);
            observations = Tracking.JobContract.observations(observations, video_info);
            native_artifacts = string(native_artifacts(:));
            for i = 1:numel(native_artifacts)
                native_path = Tracking.JobIO.resolveArtifact(workspace, native_artifacts(i));
                if exist(native_path, 'file') ~= 2 && exist(native_path, 'dir') ~= 7
                    error('Tracking:JobIO:MissingNativeArtifact', ...
                        'Tracking native artifact does not exist: %s', native_path);
                end
            end

            temp_csv = [tempname(workspace), '.csv'];
            temp_json = [tempname(workspace), '.json'];
            cleanup = onCleanup(@() Tracking.JobIO.deleteFiles({temp_csv, temp_json}));
            writetable(observations, temp_csv);
            manifest = struct( ...
                'schema_version', 1, ...
                'backend', request.backend, ...
                'status', 'complete', ...
                'completed_at', Tracking.JobIO.timestamp(), ...
                'request_file', 'request.json', ...
                'observations_csv', 'observations.csv', ...
                'observation_count', height(observations), ...
                'native_artifacts', {cellstr(native_artifacts)});
            Tracking.JobIO.writeJsonExclusive(temp_json, manifest);

            % The manifest is promoted last. A worker crash may leave an
            % orphan CSV, but never a visible complete result.
            Tracking.JobIO.promoteExclusive(temp_csv, observations_path);
            try
                Tracking.JobIO.promoteExclusive(temp_json, result_path);
            catch ME
                if exist(observations_path, 'file') == 2
                    delete(observations_path);
                end
                rethrow(ME)
            end
            clear cleanup
        end

        function [observations, manifest, request] = readResult(workspace, video_info)
            workspace = char(string(workspace));
            result_path = fullfile(workspace, 'result.json');
            if exist(result_path, 'file') ~= 2
                error('Tracking:JobIO:IncompleteResult', ...
                    'Tracking result is not complete: %s is missing.', result_path);
            end
            manifest = jsondecode(fileread(result_path));
            required = {'schema_version', 'backend', 'status', 'request_file', ...
                'observations_csv', 'observation_count'};
            missing = required(~isfield(manifest, required));
            if ~isempty(missing) || double(manifest.schema_version) ~= 1 || ...
                    ~strcmp(char(string(manifest.status)), 'complete')
                error('Tracking:JobIO:InvalidResultManifest', ...
                    'Tracking result manifest is missing fields or is not complete.');
            end
            Tracking.BackendRegistry.find(manifest.backend);
            request_file = Tracking.JobIO.resolveArtifact(workspace, manifest.request_file);
            observations_file = Tracking.JobIO.resolveArtifact(workspace, manifest.observations_csv);
            if exist(request_file, 'file') ~= 2 || exist(observations_file, 'file') ~= 2
                error('Tracking:JobIO:MissingResultArtifact', ...
                    'Tracking result references a missing request or observation file.');
            end
            request = Tracking.JobContract.request(jsondecode(fileread(request_file)));
            Tracking.JobIO.validateWorkspaceRequest(workspace, request);
            if ~strcmp(request.backend, char(string(manifest.backend)))
                error('Tracking:JobIO:BackendMismatch', ...
                    'Tracking request and result backends do not match.');
            end
            observations = readtable(observations_file, 'TextType', 'string');
            observations = Tracking.JobContract.observations(observations, video_info);
            if height(observations) ~= double(manifest.observation_count)
                error('Tracking:JobIO:ObservationCountMismatch', ...
                    'Tracking result row count does not match its manifest.');
            end
            if isfield(manifest, 'native_artifacts')
                artifacts = string(manifest.native_artifacts(:));
                for i = 1:numel(artifacts)
                    artifact_path = Tracking.JobIO.resolveArtifact(workspace, artifacts(i));
                    if exist(artifact_path, 'file') ~= 2 && exist(artifact_path, 'dir') ~= 7
                        error('Tracking:JobIO:MissingNativeArtifact', ...
                            'Tracking result references a missing native artifact: %s', artifact_path);
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function validateWorkspaceRequest(workspace, request)
            workspace_file = javaObject('java.io.File', workspace);
            request_file = javaObject('java.io.File', request.output_dir);
            if ~strcmp(char(workspace_file.getCanonicalPath()), ...
                    char(request_file.getCanonicalPath()))
                error('Tracking:JobIO:WorkspaceMismatch', ...
                    'request.output_dir does not match its tracking workspace.');
            end
            if ~isfield(request, 'source_signature')
                error('Tracking:JobIO:MissingSourceSignature', ...
                    'Staged tracking request is missing source_signature.');
            end
            actual = DataHandling.Helpers.large_file.source_signature(request.source);
            if ~isequaln(actual, request.source_signature)
                error('Tracking:JobIO:SourceChanged', ...
                    'Tracking source changed after this job was staged.');
            end
        end

        function path = resolveArtifact(workspace, relative_path)
            relative_path = Tracking.JobIO.safeRelativePath(relative_path);
            path = fullfile(workspace, relative_path);
        end

        function relative_path = safeRelativePath(relative_path)
            relative_path = char(strtrim(string(relative_path)));
            normalized = strrep(relative_path, '\', '/');
            parts = regexp(normalized, '/', 'split');
            is_absolute = startsWith(relative_path, '/') || startsWith(relative_path, '\') || ...
                ~isempty(regexp(relative_path, '^[A-Za-z]:[\\/]', 'once'));
            if isempty(relative_path) || is_absolute || any(strcmp(parts, '..'))
                error('Tracking:JobIO:UnsafeArtifactPath', ...
                    'Tracking artifact paths must be safe workspace-relative paths.');
            end
        end

        function writeJsonExclusive(path, value)
            if exist(path, 'file') == 2
                error('Tracking:JobIO:FileExists', 'Refusing to overwrite %s.', path);
            end
            fid = fopen(path, 'w');
            if fid < 0
                error('Tracking:JobIO:WriteFailed', 'Could not create %s.', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(value, PrettyPrint=true), 'char');
        end

        function promoteExclusive(source, destination)
            if exist(destination, 'file') == 2
                error('Tracking:JobIO:FileExists', ...
                    'Refusing to overwrite %s.', destination);
            end
            [ok, message] = movefile(source, destination);
            if ~ok
                error('Tracking:JobIO:PromotionFailed', ...
                    'Could not promote %s: %s', destination, message);
            end
        end

        function value = timestamp()
            value = char(datetime('now', 'TimeZone', 'UTC', ...
                'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX'));
        end

        function deleteFiles(paths)
            for i = 1:numel(paths)
                if exist(paths{i}, 'file') == 2
                    delete(paths{i});
                end
            end
        end

        function removeDirectory(path)
            if exist(path, 'dir') == 7
                try
                    rmdir(path, 's');
                catch
                end
            end
        end
    end
end
