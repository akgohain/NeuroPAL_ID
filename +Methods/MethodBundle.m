classdef MethodBundle
    %METHODBUNDLE Resolve and validate checkpoint/configuration bundles.

    methods (Static)
        function path_value = resolve(method_id, explicit_path)
            if nargin < 2
                explicit_path = "";
            end
            explicit_path = strtrim(string(explicit_path));
            if strlength(explicit_path) > 0
                path_value = char(explicit_path);
                return
            end

            method_id = char(string(method_id));
            env_name = ['NEUROPAL_', upper(regexprep(method_id, '[^A-Za-z0-9]', '_')), '_BUNDLE'];
            project_root = fileparts(fileparts(mfilename('fullpath')));
            candidates = { ...
                getenv(env_name), ...
                fullfile(fileparts(project_root), 'artifacts', 'method_bundles', method_id), ...
                fullfile(project_root, 'method_bundles', method_id)};
            path_value = '';
            for i = 1:numel(candidates)
                candidate = strtrim(char(string(candidates{i})));
                if isempty(candidate)
                    continue
                end
                if isempty(path_value)
                    path_value = candidate;
                end
                if exist(candidate, 'dir') == 7
                    path_value = candidate;
                    return
                end
            end
        end

        function readiness = inspect(method_id, explicit_path)
            if nargin < 2
                explicit_path = "";
            end
            method_id = char(string(method_id));
            bundle_path = Methods.MethodBundle.resolve(method_id, explicit_path);
            readiness = struct( ...
                'method_id', method_id, ...
                'bundle_path', bundle_path, ...
                'ready', false, ...
                'summary', '', ...
                'missing', {{}}, ...
                'manifest', struct());

            if isempty(bundle_path) || exist(bundle_path, 'dir') ~= 7
                readiness.summary = sprintf('Model bundle required for %s.', method_id);
                readiness.missing = {'bundle directory'};
                return
            end
            manifest_path = fullfile(bundle_path, 'method_bundle.json');
            if exist(manifest_path, 'file') ~= 2
                readiness.summary = 'Bundle is missing method_bundle.json.';
                readiness.missing = {'method_bundle.json'};
                return
            end

            try
                manifest = jsondecode(fileread(manifest_path));
                Methods.MethodBundle.validateManifest(method_id, manifest);
            catch ME
                readiness.summary = sprintf('Invalid model bundle: %s', ME.message);
                readiness.missing = {'valid manifest'};
                return
            end

            readiness.manifest = manifest;
            missing = {};
            artifacts = manifest.artifacts;
            if ~isstruct(artifacts)
                artifacts = struct([]);
            end
            for i = 1:numel(artifacts)
                required = true;
                if isfield(artifacts(i), 'required')
                    required = logical(artifacts(i).required);
                end
                artifact_path = fullfile(bundle_path, char(string(artifacts(i).path)));
                if required && exist(artifact_path, 'file') ~= 2 && exist(artifact_path, 'dir') ~= 7
                    missing{end + 1} = char(string(artifacts(i).path)); %#ok<AGROW>
                end
            end
            readiness.missing = missing;
            readiness.ready = isempty(missing);
            if readiness.ready
                readiness.summary = sprintf('%s bundle ready.', char(string(manifest.display_name)));
            else
                readiness.summary = sprintf('Bundle needs: %s', strjoin(missing, ', '));
            end
        end

        function artifact_path = artifact(readiness, role)
            if ~readiness.ready
                error('Methods:MethodBundle:NotReady', '%s', readiness.summary);
            end
            artifacts = readiness.manifest.artifacts;
            index = find(strcmp(string({artifacts.role}), string(role)), 1);
            if isempty(index)
                error('Methods:MethodBundle:MissingRole', ...
                    'Bundle %s has no artifact with role %s.', ...
                    readiness.bundle_path, char(string(role)));
            end
            artifact_path = fullfile(readiness.bundle_path, char(string(artifacts(index).path)));
        end

        function validateManifest(method_id, manifest)
            required = {'schema_version', 'method_id', 'display_name', 'configuration', 'artifacts'};
            missing = required(~isfield(manifest, required));
            if ~isempty(missing)
                error('Methods:MethodBundle:InvalidManifest', ...
                    'Missing manifest fields: %s', strjoin(missing, ', '));
            end
            if double(manifest.schema_version) ~= 1
                error('Methods:MethodBundle:UnsupportedSchema', ...
                    'Unsupported method bundle schema: %s', char(string(manifest.schema_version)));
            end
            if ~strcmp(char(string(manifest.method_id)), char(string(method_id)))
                error('Methods:MethodBundle:WrongMethod', ...
                    'Bundle method_id is %s; expected %s.', ...
                    char(string(manifest.method_id)), char(string(method_id)));
            end
            if ~isstruct(manifest.artifacts)
                error('Methods:MethodBundle:InvalidArtifacts', ...
                    'Manifest artifacts must be an array of objects.');
            end
            if ~isstruct(manifest.configuration) || ~isscalar(manifest.configuration)
                error('Methods:MethodBundle:InvalidConfiguration', ...
                    'Manifest configuration must be one JSON object.');
            end
            roles = strings(1, numel(manifest.artifacts));
            for i = 1:numel(manifest.artifacts)
                if ~all(isfield(manifest.artifacts(i), {'role', 'path'}))
                    error('Methods:MethodBundle:InvalidArtifact', ...
                        'Every artifact needs role and path fields.');
                end
                roles(i) = strtrim(string(manifest.artifacts(i).role));
                relative_path = char(strtrim(string(manifest.artifacts(i).path)));
                path_parts = regexp(strrep(relative_path, '\', '/'), '/', 'split');
                is_absolute = startsWith(relative_path, '/') || ...
                    startsWith(relative_path, '\') || ...
                    ~isempty(regexp(relative_path, '^[A-Za-z]:[\\/]', 'once'));
                if strlength(roles(i)) == 0 || isempty(relative_path) || ...
                        is_absolute || any(strcmp(path_parts, '..'))
                    error('Methods:MethodBundle:UnsafeArtifactPath', ...
                        'Artifact roles and paths must be nonempty, safe, and bundle-relative.');
                end
            end
            if numel(unique(roles)) ~= numel(roles)
                error('Methods:MethodBundle:DuplicateArtifactRole', ...
                    'Every artifact role must be unique within a method bundle.');
            end
        end
    end
end
