classdef TransformerAutoId
    %TRANSFORMERAUTOID Adapter for Anshita GAT/transformer auto-ID output.

    methods(Static)
        function predictions = run(app, options)
            arguments
                app
                options.NWBPath (1,1) string = ""
                options.BatchSize (1,1) double = 32
                options.NumWorkers (1,1) double = 0
                options.PreprocessWorkers (1,1) double = 0
                options.MinNeighbors (1,1) double = 2
                options.MCSamples (1,1) double = 20
                options.ConfidenceThreshold (1,1) double = 0.5
                options.UncertaintyThreshold (1,1) double = 0.05
                options.QualityThreshold (1,1) double = 0.3
                options.Device (1,1) string = ""
                options.DatasetID (1,1) string = "000981"
                options.CheckpointPath (1,1) string = ""
            end

            progress = Methods.TransformerAutoId.openProgressDialog(app);
            cleanup = onCleanup(@() Methods.TransformerAutoId.closeProgressDialog(progress));
            [~, checkpoint_path] = Wrapper.resolveTransformerAssets("", options.CheckpointPath);

            nwb_path = Methods.TransformerAutoId.resolveNWBPath(app, options.NWBPath);
            if strlength(nwb_path) > 0
                Methods.TransformerAutoId.updateProgress(progress, ...
                    sprintf('Using NWB input: %s', nwb_path));
                predictions = Wrapper.runTransformerAutoID(nwb_path, ...
                    'BatchSize', options.BatchSize, ...
                    'NumWorkers', options.NumWorkers, ...
                    'PreprocessWorkers', options.PreprocessWorkers, ...
                    'MinNeighbors', options.MinNeighbors, ...
                    'MCSamples', options.MCSamples, ...
                    'ConfidenceThreshold', options.ConfidenceThreshold, ...
                    'UncertaintyThreshold', options.UncertaintyThreshold, ...
                    'QualityThreshold', options.QualityThreshold, ...
                    'Device', options.Device, ...
                    'DatasetID', options.DatasetID, ...
                    'CheckpointPath', checkpoint_path, ...
                    'ProgressFcn', @(message) Methods.TransformerAutoId.updateProgress(progress, message));
            else
                Methods.TransformerAutoId.updateProgress(progress, ...
                    'No NWB found; staging current app volume for transformer auto-ID...');
                [volume_rgbw, labels] = Methods.TransformerAutoId.appTransformerVolume(app);
                positions_yxz = Methods.TransformerAutoId.appNeuronPositions(app);
                predictions = Wrapper.runTransformerAutoIDFromVolume(volume_rgbw, positions_yxz, app.image_um_scale', ...
                    'Labels', labels, ...
                    'BatchSize', options.BatchSize, ...
                    'NumWorkers', options.NumWorkers, ...
                    'PreprocessWorkers', options.PreprocessWorkers, ...
                    'MinNeighbors', options.MinNeighbors, ...
                    'MCSamples', options.MCSamples, ...
                    'ConfidenceThreshold', options.ConfidenceThreshold, ...
                    'UncertaintyThreshold', options.UncertaintyThreshold, ...
                    'QualityThreshold', options.QualityThreshold, ...
                    'Device', options.Device, ...
                    'DatasetID', options.DatasetID, ...
                    'CheckpointPath', checkpoint_path, ...
                    'ProgressFcn', @(message) Methods.TransformerAutoId.updateProgress(progress, message));
            end

            Methods.TransformerAutoId.applyPredictions(app, predictions);
            Methods.TransformerAutoId.refreshAppUI(app);
        end

        function nwb_path = resolveNWBPath(app, explicit_path)
            nwb_path = string(explicit_path);
            if strlength(nwb_path) > 0 && exist(nwb_path, 'file') == 2
                return
            end
            nwb_path = "";
            try
                image_file = string(app.image_file);
                if strlength(image_file) > 0
                    [folder, name, ext] = fileparts(image_file);
                    if strcmpi(ext, '.nwb') && exist(image_file, 'file') == 2
                        nwb_path = image_file;
                        return
                    end
                    candidate = fullfile(folder, [name, '.nwb']);
                    if exist(candidate, 'file') == 2
                        nwb_path = string(candidate);
                    end
                end
            catch
            end
        end

        function checkpoint_path = defaultCheckpointPath()
            [~, checkpoint_path] = Wrapper.resolveTransformerAssets();
        end

        function applyPredictions(app, predictions)
            if isempty(app.image_neurons) || app.image_neurons.num_neurons() < 1
                error('Methods:TransformerAutoId:NoNeurons', ...
                    'Run auto-detection before transformer auto-ID.');
            end
            predictions = Methods.MethodContract.identity(predictions);
            required = {'neuron_idx', 'predicted_class', 'confidence'};
            for i = 1:numel(required)
                if ~ismember(required{i}, predictions.Properties.VariableNames)
                    error('Methods:TransformerAutoId:BadPredictions', ...
                        'Prediction CSV is missing %s.', required{i});
                end
            end

            n = app.image_neurons.num_neurons();
            [prediction_to_neuron, match_stats] = Methods.TransformerAutoId.matchPredictionRows(app, predictions);
            snapshot = Methods.TransformerAutoId.captureModelIDs(app.image_neurons);
            try
                app.image_neurons.delete_model_IDs();
                top_k = 5;
                for i = 1:n
                    app.image_neurons.neurons(i).deterministic_id = '';
                    app.image_neurons.neurons(i).probabilistic_ids = repmat({'Artifact'}, 1, top_k);
                    app.image_neurons.neurons(i).probabilistic_probs = zeros(1, top_k);
                    app.image_neurons.neurons(i).rank = 0;
                end
                matched_neuron_indices = [];
                matched_confidences = [];
                for r = 1:height(predictions)
                    idx = prediction_to_neuron(r);
                    if idx < 1 || idx > n
                        continue
                    end
                    neuron = app.image_neurons.neurons(round(idx));
                    predicted_class = char(string(predictions.predicted_class(r)));
                    if isempty(strtrim(predicted_class)) || strcmpi(predicted_class, 'nan')
                        predicted_class = 'Artifact';
                    end
                    neuron.deterministic_id = predicted_class;
                    if ismember('top5_classes', predictions.Properties.VariableNames)
                        names = Methods.TransformerAutoId.parseTopList(predictions.top5_classes(r));
                    else
                        names = {predicted_class};
                    end
                    if isempty(names)
                        names = {predicted_class};
                    end
                    if ~strcmp(char(names{1}), predicted_class)
                        names = [{predicted_class}, names(:)'];
                    end
                    names = names(:)';
                    if numel(names) < top_k
                        names(end+1:top_k) = {'Artifact'};
                    elseif numel(names) > top_k
                        names = names(1:top_k);
                    end
                    neuron.probabilistic_ids = names(:)';
                    if ismember('top5_probs', predictions.Properties.VariableNames)
                        probs = str2double(Methods.TransformerAutoId.parseTopList(predictions.top5_probs(r)));
                    else
                        probs = double(predictions.confidence(r));
                    end
                    probs = double(probs(:)');
                    probs(~isfinite(probs)) = 0;
                    if isempty(probs)
                        probs = double(predictions.confidence(r));
                    end
                    if numel(probs) < top_k
                        probs(end+1:top_k) = 0;
                    elseif numel(probs) > top_k
                        probs = probs(1:top_k);
                    end
                    neuron.probabilistic_probs = probs;
                    matched_neuron_indices(end + 1, 1) = round(idx); %#ok<AGROW>
                    matched_confidences(end + 1, 1) = double(predictions.confidence(r)); %#ok<AGROW>
                end

                if ~isempty(matched_neuron_indices)
                    [~, order] = sort(matched_confidences, 'ascend', 'MissingPlacement', 'last');
                    for rank_i = 1:numel(order)
                        app.image_neurons.neurons(matched_neuron_indices(order(rank_i))).rank = rank_i;
                    end
                end
                Methods.TransformerAutoId.storeMatchStats(app, match_stats);
            catch ME
                Methods.TransformerAutoId.restoreModelIDs(app.image_neurons, snapshot);
                rethrow(ME);
            end
        end

        function snapshot = captureModelIDs(image_neurons)
            neurons = image_neurons.neurons;
            snapshot = struct( ...
                'deterministic_id', {cell(1, numel(neurons))}, ...
                'probabilistic_ids', {cell(1, numel(neurons))}, ...
                'probabilistic_probs', {cell(1, numel(neurons))}, ...
                'rank', {cell(1, numel(neurons))});
            for i = 1:numel(neurons)
                snapshot.deterministic_id{i} = neurons(i).deterministic_id;
                snapshot.probabilistic_ids{i} = neurons(i).probabilistic_ids;
                snapshot.probabilistic_probs{i} = neurons(i).probabilistic_probs;
                snapshot.rank{i} = neurons(i).rank;
            end
        end

        function restoreModelIDs(image_neurons, snapshot)
            neurons = image_neurons.neurons;
            for i = 1:min(numel(neurons), numel(snapshot.deterministic_id))
                neurons(i).deterministic_id = snapshot.deterministic_id{i};
                neurons(i).probabilistic_ids = snapshot.probabilistic_ids{i};
                neurons(i).probabilistic_probs = snapshot.probabilistic_probs{i};
                neurons(i).rank = snapshot.rank{i};
            end
        end

        function refreshAppUI(app)
            try
                Program.Routines.ID.hot_neuron_reset();
            catch
            end
            Methods.TransformerAutoId.drawAutoIdList(app);
            try
                Program.Routines.ID.render();
            catch
            end
            drawnow limitrate;
        end

        function drawAutoIdList(app)
            if isempty(app.image_neurons) || isempty(app.image_neurons.neurons)
                Methods.TransformerAutoId.clearAutoIdList(app);
                return
            end

            rows = {};
            ranks = [];
            neurons = app.image_neurons.neurons;
            for i = 1:numel(neurons)
                neuron = neurons(i);
                if isempty(neuron.rank) || ~isfinite(double(neuron.rank)) || double(neuron.rank) <= 0
                    continue
                end
                ids = neuron.probabilistic_ids;
                probs = neuron.probabilistic_probs;
                if isempty(ids)
                    ids = {neuron.deterministic_id};
                end
                if isempty(probs)
                    probs = 0;
                end
                ids = cellstr(string(ids));
                probs = double(probs(:)');
                if numel(probs) < numel(ids)
                    probs(end+1:numel(ids)) = 0;
                elseif numel(probs) > numel(ids)
                    probs = probs(1:numel(ids));
                end
                probs(~isfinite(probs)) = 0;
                probs = round(probs * 100);

                row = sprintf('%s=%d%%', ids{1}, probs(1));
                alt_i = find(probs(2:end) > 0) + 1;
                if ~isempty(alt_i)
                    row = [row, '   or  ']; %#ok<AGROW>
                end
                for j = 1:numel(alt_i)
                    k = alt_i(j);
                    if j > 1
                        row = [row, ',']; %#ok<AGROW>
                    end
                    row = [row, sprintf(' %s=%d%%', ids{k}, probs(k))]; %#ok<AGROW>
                end
                rows{end + 1, 1} = row; %#ok<AGROW>
                ranks(end + 1, 1) = double(neuron.rank); %#ok<AGROW>
            end

            if isempty(rows)
                Methods.TransformerAutoId.clearAutoIdList(app);
                return
            end
            [ranks, sort_i] = sort(ranks);
            app.UserNeuronIDsListBox.Items = rows(sort_i);
            app.UserNeuronIDsListBox.ItemsData = ranks(:)';
            app.UserNeuronIDsListBox.Value = {};
            try
                app.UserNeuronIDsListBoxLabel.Text = sprintf('Auto-ID Neuron IDs = %d/%d', ...
                    numel(rows), app.image_neurons.num_neurons());
            catch
            end
        end

        function clearAutoIdList(app)
            try
                app.UserNeuronIDsListBox.Items = {};
                app.UserNeuronIDsListBox.ItemsData = [];
                app.UserNeuronIDsListBox.Value = {};
                app.UserNeuronIDsListBoxLabel.Text = 'User Neuron IDs';
            catch
            end
        end

        function values = parseTopList(value)
            text = strtrim(char(string(value)));
            if isempty(text) || strcmpi(text, 'nan') || strcmpi(text, '<missing>')
                values = {};
                return
            end
            values = strtrim(strsplit(text, ','));
            values = values(~cellfun('isempty', values));
        end

        function [volume_rgbw, labels] = appTransformerVolume(app)
            if isempty(app.image_data)
                error('Methods:TransformerAutoId:NoVolume', ...
                    'No image volume is loaded.');
            end
            channel_indices = Methods.TransformerAutoId.appRGBWChannels(app);
            volume_rgbw = app.image_data(:, :, :, channel_indices);
            if numel(channel_indices) < 4
                pad_size = size(volume_rgbw);
                pad_size(4) = 4 - numel(channel_indices);
                volume_rgbw = cat(4, volume_rgbw, zeros(pad_size, 'like', volume_rgbw));
            end
            labels = Methods.TransformerAutoId.appNeuronLabels(app);
        end

        function channel_indices = appRGBWChannels(app)
            n_channels = size(app.image_data, 4);
            channel_indices = [];
            try
                rgbw = app.image_prefs.RGBW;
                rgbw = round(double(rgbw(:)'));
                rgbw = rgbw(~isnan(rgbw) & rgbw >= 1 & rgbw <= n_channels);
                channel_indices = rgbw;
            catch
            end
            if isempty(channel_indices)
                channel_indices = 1:min(4, n_channels);
            end
            channel_indices = unique(channel_indices, 'stable');
            if numel(channel_indices) > 4
                channel_indices = channel_indices(1:4);
            end
        end

        function positions_yxz = appNeuronPositions(app)
            if isempty(app.image_neurons) || app.image_neurons.num_neurons() < 1
                error('Methods:TransformerAutoId:NoNeurons', ...
                    'Run auto-detection before transformer auto-ID.');
            end
            positions_yxz = double(app.image_neurons.get_positions());
            if isempty(positions_yxz) || size(positions_yxz, 2) < 3
                error('Methods:TransformerAutoId:NoNeuronPositions', ...
                    'Detected neurons do not have usable centroid positions.');
            end
            positions_yxz = positions_yxz(:, 1:3);
        end

        function labels = appNeuronLabels(app)
            try
                n = app.image_neurons.num_neurons();
                labels = strings(n, 1);
                for i = 1:n
                    neuron = app.image_neurons.neurons(i);
                    label = "";
                    if isprop(neuron, 'annotation') && ~isempty(neuron.annotation)
                        label = string(neuron.annotation);
                    elseif isprop(neuron, 'deterministic_id') && ~isempty(neuron.deterministic_id)
                        label = string(neuron.deterministic_id);
                    end
                    labels(i) = label;
                end
            catch
                labels = strings(0, 1);
            end
        end

        function [prediction_to_neuron, stats] = matchPredictionRows(app, predictions)
            n_predictions = height(predictions);
            prediction_to_neuron = zeros(n_predictions, 1);
            n = app.image_neurons.num_neurons();
            stats = struct( ...
                'strategy', 'index', ...
                'predictions', n_predictions, ...
                'neurons', n, ...
                'matched', 0, ...
                'unmatched_predictions', n_predictions, ...
                'unmatched_neurons', n, ...
                'max_distance_um', NaN, ...
                'mean_distance_um', NaN);

            coord_fields = {'coord_x_um', 'coord_y_um', 'coord_z_um'};
            has_coords = all(ismember(coord_fields, predictions.Properties.VariableNames));
            if has_coords
                try
                    neuron_positions = app.image_neurons.get_positions();
                    neuron_scale = app.image_neurons.scale;
                    if isempty(neuron_scale)
                        neuron_scale = [1, 1, 1];
                    end
                    neuron_scale = double(neuron_scale(:)');
                    if numel(neuron_scale) < 3
                        neuron_scale(end+1:3) = 1;
                    end
                    neuron_um = double(neuron_positions(:, 1:3)) .* neuron_scale(1:3);
                    prediction_um = [ ...
                        double(predictions.coord_x_um), ...
                        double(predictions.coord_y_um), ...
                        double(predictions.coord_z_um)];

                    available = true(n, 1);
                    max_distance_um = max(8, 4 * max(neuron_scale(1:3)));
                    matched_distances = [];
                    for r = 1:n_predictions
                        delta = neuron_um - prediction_um(r, :);
                        distances = sqrt(sum(delta.^2, 2));
                        distances(~available) = inf;
                        [best_distance, best_idx] = min(distances);
                        if isfinite(best_distance) && best_distance <= max_distance_um
                            prediction_to_neuron(r) = best_idx;
                            available(best_idx) = false;
                            matched_distances(end + 1, 1) = best_distance; %#ok<AGROW>
                        end
                    end

                    if any(prediction_to_neuron > 0)
                        stats.strategy = 'centroid';
                        stats.matched = sum(prediction_to_neuron > 0);
                        stats.unmatched_predictions = n_predictions - stats.matched;
                        stats.unmatched_neurons = sum(available);
                        if ~isempty(matched_distances)
                            stats.max_distance_um = max(matched_distances);
                            stats.mean_distance_um = mean(matched_distances);
                        end
                        return
                    end
                catch
                    prediction_to_neuron(:) = 0;
                end
            end

            if ismember('neuron_idx', predictions.Properties.VariableNames)
                for r = 1:n_predictions
                    idx = double(predictions.neuron_idx(r));
                    if idx >= 1 && idx <= n
                        prediction_to_neuron(r) = round(idx);
                    end
                end
            end
            stats.strategy = 'index';
            stats.matched = sum(prediction_to_neuron > 0);
            stats.unmatched_predictions = n_predictions - stats.matched;
            stats.unmatched_neurons = max(0, n - numel(unique(prediction_to_neuron(prediction_to_neuron > 0))));
        end

        function storeMatchStats(app, stats)
            try
                if isprop(app, 'CELL_ID') && ~isempty(app.CELL_ID) && isvalid(app.CELL_ID)
                    setappdata(app.CELL_ID, 'transformer_autoid_match_stats', stats);
                end
            catch
            end
        end

        function progress = openProgressDialog(app)
            progress = Methods.MLProgress.open( ...
                "Transformer Auto-ID", "Preparing transformer auto-ID...", ...
                'App', app);
        end

        function updateProgress(progress, message)
            Methods.MLProgress.update(progress, string(message), []);
        end

        function closeProgressDialog(progress)
            Methods.MLProgress.close(progress);
        end
    end
end
