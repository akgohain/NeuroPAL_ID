classdef ResultAdapter
    %RESULTADAPTER Convert canonical observations to legacy app data safely.

    methods (Static)
        function video_neurons = toVideoNeurons(observations, video_info, track_names)
            observations = Tracking.JobContract.observations(observations, video_info);
            track_ids = unique(double(observations.track_id), 'stable');
            if nargin < 3 || isempty(track_names)
                track_names = strings(numel(track_ids), 1);
            else
                track_names = string(track_names(:));
                if numel(track_names) ~= numel(track_ids)
                    error('Tracking:ResultAdapter:NameCount', ...
                        'Provide one track name for each unique track ID.');
                end
            end

            video_neurons = struct('provenance', {}, 'worldline', {}, ...
                'rois', {}, 'tracking', {});
            roi_template = struct('x_slice', [], 'y_slice', [], 'z_slice', [], ...
                'xy_pos', [], 'xz_pos', [], 'yz_pos', [], 'confidence', []);
            palette = lines(max(numel(track_ids), 1));

            for i = 1:numel(track_ids)
                track_id = track_ids(i);
                rows = observations(double(observations.track_id) == track_id, :);
                parent_ids = unique(double(rows.parent_id));
                provenances = unique(string(rows.provenance), 'stable');
                if strlength(track_names(i)) == 0
                    track_names(i) = "Track " + string(track_id);
                end
                rois = repmat(roi_template, 1, double(video_info.nt));
                for j = 1:height(rows)
                    t = double(rows.t(j));
                    x = double(rows.x(j));
                    y = double(rows.y(j));
                    z = double(rows.z(j));
                    rois(t).x_slice = x;
                    rois(t).y_slice = y;
                    rois(t).z_slice = z;
                    rois(t).xy_pos = [x, y];
                    rois(t).xz_pos = [x, z];
                    rois(t).yz_pos = [z, y];
                    rois(t).confidence = double(rows.confidence(j));
                end
                worldline = struct('name', char(track_names(i)), 'node', [], ...
                    'color', palette(i, :), 'style', [], 'id', track_id);
                tracking = struct('track_id', track_id, ...
                    'parent_id', parent_ids(1), ...
                    'provenance_by_frame', string(rows.provenance), ...
                    'frames', double(rows.t));
                video_neurons(end+1) = struct( ...
                    'provenance', char(strjoin(provenances, '+')), ...
                    'worldline', worldline, 'rois', rois, ...
                    'tracking', tracking); %#ok<AGROW>
            end
        end

        function observations = fromVideoNeurons(video_neurons, video_info)
            row_count = Tracking.ResultAdapter.positionCount(video_neurons, video_info);
            rows = cell(row_count, 8);
            row_index = 0;
            for i = 1:numel(video_neurons)
                [track_id, parent_id] = Tracking.ResultAdapter.trackIdentity( ...
                    video_neurons(i), i);
                if ~isfield(video_neurons(i), 'rois') || isempty(video_neurons(i).rois)
                    continue
                end
                for t = 1:min(numel(video_neurons(i).rois), double(video_info.nt))
                    roi = video_neurons(i).rois(t);
                    if ~Tracking.ResultAdapter.hasPosition(roi)
                        continue
                    end
                    confidence = Tracking.ResultAdapter.confidence(roi);
                    provenance = Tracking.ResultAdapter.provenance(video_neurons(i), t);
                    row_index = row_index + 1;
                    rows(row_index, :) = {track_id, parent_id, t, ...
                        double(roi.z_slice), double(roi.y_slice), ...
                        double(roi.x_slice), confidence, provenance};
                end
            end
            variable_names = {'track_id', 'parent_id', 't', 'z', 'y', 'x', ...
                'confidence', 'provenance'};
            if isempty(rows)
                observations = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
                    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
                    strings(0, 1), 'VariableNames', variable_names);
            else
                observations = cell2table(rows, 'VariableNames', variable_names);
                observations{:, 1:7} = double(observations{:, 1:7});
                observations.provenance = string(observations.provenance);
            end
            observations = sortrows(observations, {'track_id', 't'});
            observations = Tracking.JobContract.observations(observations, video_info);
        end
    end

    methods (Static, Access = private)
        function count = positionCount(video_neurons, video_info)
            count = 0;
            for i = 1:numel(video_neurons)
                if ~isfield(video_neurons(i), 'rois')
                    continue
                end
                for t = 1:min(numel(video_neurons(i).rois), double(video_info.nt))
                    count = count + Tracking.ResultAdapter.hasPosition( ...
                        video_neurons(i).rois(t));
                end
            end
        end

        function [track_id, parent_id] = trackIdentity(video_neuron, fallback_id)
            track_id = fallback_id;
            parent_id = 0;
            if isfield(video_neuron, 'tracking') && isstruct(video_neuron.tracking)
                if isfield(video_neuron.tracking, 'track_id')
                    track_id = double(video_neuron.tracking.track_id);
                end
                if isfield(video_neuron.tracking, 'parent_id')
                    parent_id = double(video_neuron.tracking.parent_id);
                end
            end
        end

        function tf = hasPosition(roi)
            fields = {'x_slice', 'y_slice', 'z_slice'};
            tf = true;
            for i = 1:numel(fields)
                value = [];
                if isfield(roi, fields{i})
                    value = roi.(fields{i});
                end
                tf = tf && isnumeric(value) && isscalar(value) && isfinite(value);
            end
        end

        function value = confidence(roi)
            value = 1;
            if isfield(roi, 'confidence') && isnumeric(roi.confidence) && ...
                    isscalar(roi.confidence) && isfinite(roi.confidence)
                value = double(roi.confidence);
            end
        end

        function value = provenance(video_neuron, frame)
            value = "legacy";
            if isfield(video_neuron, 'tracking') && isstruct(video_neuron.tracking) && ...
                    all(isfield(video_neuron.tracking, {'frames', 'provenance_by_frame'}))
                frames = double(video_neuron.tracking.frames(:));
                index = find(frames == frame, 1);
                provenances = string(video_neuron.tracking.provenance_by_frame);
                if ~isempty(index) && index <= numel(provenances)
                    value = provenances(index);
                    return
                end
            end
            if isfield(video_neuron, 'provenance') && ~isempty(video_neuron.provenance)
                value = string(video_neuron.provenance);
            end
        end
    end
end
