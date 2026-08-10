classdef JobContract
    %JOBCONTRACT Validate backend-neutral tracking requests and observations.

    methods (Static)
        function request = request(request)
            if ~isstruct(request) || ~isscalar(request)
                error('Tracking:JobContract:RequestNotStruct', ...
                    'A tracking request must be one scalar structure.');
            end
            required = {'schema_version', 'backend', 'source', 'output_dir', ...
                'scale_zyx', 'time_step', 'segmentation'};
            Tracking.JobContract.requireFields(request, required, 'request');
            if double(request.schema_version) ~= 1
                error('Tracking:JobContract:UnsupportedSchema', ...
                    'Unsupported tracking request schema: %s', ...
                    char(string(request.schema_version)));
            end
            backend = Tracking.BackendRegistry.find(request.backend);
            request.backend = char(backend.id);
            request.source = Tracking.JobContract.nonemptyText(request.source, 'source');
            request.output_dir = Tracking.JobContract.nonemptyText(request.output_dir, 'output_dir');
            scale = double(request.scale_zyx(:)');
            if numel(scale) ~= 3 || any(~isfinite(scale)) || any(scale <= 0)
                error('Tracking:JobContract:InvalidScale', ...
                    'scale_zyx must contain three finite positive values.');
            end
            request.scale_zyx = scale;
            time_step = double(request.time_step);
            if ~isscalar(time_step) || ~isfinite(time_step) || time_step <= 0
                error('Tracking:JobContract:InvalidTimeStep', ...
                    'time_step must be one finite positive value.');
            end
            request.time_step = time_step;
            if ~isstruct(request.segmentation) || ~isscalar(request.segmentation) || ...
                    ~all(isfield(request.segmentation, {'kind', 'path'}))
                error('Tracking:JobContract:InvalidSegmentation', ...
                    'segmentation must contain kind and path fields.');
            end
            kind = lower(string(request.segmentation.kind));
            allowed = ["none", "labels", "foreground_contours"];
            if ~isscalar(kind) || ~any(kind == allowed)
                error('Tracking:JobContract:InvalidSegmentation', ...
                    'Segmentation kind must be none, labels, or foreground_contours.');
            end
            request.segmentation.kind = char(kind);
            request.segmentation.path = char(string(request.segmentation.path));
            if backend.requires_segmentation && kind == "none"
                error('Tracking:JobContract:SegmentationRequired', ...
                    '%s requires a segmentation source.', char(backend.name));
            end
            if kind ~= "none" && isempty(strtrim(request.segmentation.path))
                error('Tracking:JobContract:MissingSegmentationPath', ...
                    'The selected segmentation source requires a path.');
            end
        end

        function observations = observations(observations, video_info)
            if ~istable(observations)
                error('Tracking:JobContract:ObservationsNotTable', ...
                    'Tracking observations must be a MATLAB table.');
            end
            required = {'track_id', 'parent_id', 't', 'z', 'y', 'x', ...
                'confidence', 'provenance'};
            missing = setdiff(required, observations.Properties.VariableNames, 'stable');
            if ~isempty(missing)
                error('Tracking:JobContract:MissingColumns', ...
                    'Tracking observations are missing: %s', strjoin(missing, ', '));
            end
            numeric_fields = {'track_id', 'parent_id', 't', 'z', 'y', 'x', 'confidence'};
            values = double(observations{:, numeric_fields});
            if any(~isfinite(values), 'all')
                error('Tracking:JobContract:NonFiniteObservation', ...
                    'Tracking IDs, coordinates, frames, and confidence must be finite.');
            end
            ids = double(observations.track_id);
            parents = double(observations.parent_id);
            frames = double(observations.t);
            if any(ids < 1 | mod(ids, 1) ~= 0) || ...
                    any(parents < 0 | mod(parents, 1) ~= 0) || ...
                    any(frames < 1 | mod(frames, 1) ~= 0)
                error('Tracking:JobContract:InvalidIndex', ...
                    'track_id and t must be positive integers; parent_id uses 0 for roots.');
            end
            confidence = double(observations.confidence);
            if any(confidence < 0 | confidence > 1)
                error('Tracking:JobContract:InvalidConfidence', ...
                    'Tracking confidence must lie in [0,1].');
            end
            provenance = strtrim(string(observations.provenance));
            if any(ismissing(provenance) | strlength(provenance) == 0)
                error('Tracking:JobContract:MissingProvenance', ...
                    'Every tracking observation needs provenance.');
            end
            if height(unique(observations(:, {'track_id', 't'}), 'rows')) ~= height(observations)
                error('Tracking:JobContract:DuplicateObservation', ...
                    'A track may have at most one observation per frame.');
            end

            Tracking.JobContract.validateBounds(observations, video_info);
            Tracking.JobContract.validateLineage(ids, parents);
        end
    end

    methods (Static, Access = private)
        function requireFields(value, required, kind)
            missing = required(~isfield(value, required));
            if ~isempty(missing)
                error('Tracking:JobContract:MissingFields', ...
                    'Tracking %s is missing: %s', kind, strjoin(missing, ', '));
            end
        end

        function value = nonemptyText(value, field_name)
            value = char(strtrim(string(value)));
            if isempty(value)
                error('Tracking:JobContract:MissingText', ...
                    'Tracking request %s must be nonempty.', field_name);
            end
        end

        function validateBounds(observations, video_info)
            if nargin < 2 || isempty(video_info)
                return
            end
            required = {'nt', 'nz', 'ny', 'nx'};
            if ~isstruct(video_info) || ~all(isfield(video_info, required))
                error('Tracking:JobContract:InvalidVideoInfo', ...
                    'video_info must contain nt, nz, ny, and nx bounds.');
            end
            maxima = double([video_info.nt, video_info.nz, video_info.ny, video_info.nx]);
            coordinates = double(observations{:, {'t', 'z', 'y', 'x'}});
            if any(maxima < 1) || any(~isfinite(maxima)) || ...
                    any(coordinates < 1, 'all') || any(coordinates > maxima, 'all')
                error('Tracking:JobContract:OutOfBounds', ...
                    'One or more tracking observations fall outside the video bounds.');
            end
        end

        function validateLineage(ids, parents)
            track_ids = unique(ids, 'stable');
            parent_for_track = zeros(size(track_ids));
            for i = 1:numel(track_ids)
                track_parents = unique(parents(ids == track_ids(i)));
                if numel(track_parents) ~= 1
                    error('Tracking:JobContract:InconsistentParent', ...
                        'Each track_id must have one consistent parent_id.');
                end
                parent_for_track(i) = track_parents;
            end
            if any(parent_for_track == track_ids)
                error('Tracking:JobContract:LineageCycle', ...
                    'A track cannot be its own parent.');
            end
            missing = setdiff(parent_for_track(parent_for_track > 0), track_ids);
            if ~isempty(missing)
                error('Tracking:JobContract:MissingParent', ...
                    'Lineage references missing parent track IDs: %s', mat2str(missing(:)'));
            end
            for i = 1:numel(track_ids)
                seen = false(size(track_ids));
                current = track_ids(i);
                while current > 0
                    index = find(track_ids == current, 1);
                    if isempty(index)
                        break
                    end
                    if seen(index)
                        error('Tracking:JobContract:LineageCycle', ...
                            'The tracking lineage graph contains a cycle.');
                    end
                    seen(index) = true;
                    current = parent_for_track(index);
                end
            end
        end
    end
end
