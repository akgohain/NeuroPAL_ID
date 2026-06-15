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
                options.CheckpointPath (1,1) string = "/Users/adamg/neuroPAL/artifacts/anshita_transformer"
            end

            nwb_path = Methods.TransformerAutoId.resolveNWBPath(app, options.NWBPath);
            if strlength(nwb_path) == 0
                error('Methods:TransformerAutoId:NoNWB', ...
                    ['Transformer auto-ID currently requires an NWB file. ' ...
                     'Open an NWB directly or place a companion .nwb next to the current MAT file.']);
            end

            progress = Methods.TransformerAutoId.openProgressDialog(app);
            cleanup = onCleanup(@() Methods.TransformerAutoId.closeProgressDialog(progress)); %#ok<NASGU>

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
                'CheckpointPath', options.CheckpointPath, ...
                'ProgressFcn', @(message) Methods.TransformerAutoId.updateProgress(progress, message));

            Methods.TransformerAutoId.applyPredictions(app, predictions);
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

        function applyPredictions(app, predictions)
            if isempty(app.image_neurons) || app.image_neurons.num_neurons() < 1
                error('Methods:TransformerAutoId:NoNeurons', ...
                    'Run auto-detection before transformer auto-ID.');
            end
            required = {'neuron_idx', 'predicted_class', 'confidence'};
            for i = 1:numel(required)
                if ~ismember(required{i}, predictions.Properties.VariableNames)
                    error('Methods:TransformerAutoId:BadPredictions', ...
                        'Prediction CSV is missing %s.', required{i});
                end
            end

            n = app.image_neurons.num_neurons();
            prediction_to_neuron = Methods.TransformerAutoId.matchPredictionRows(app, predictions);
            for r = 1:height(predictions)
                idx = prediction_to_neuron(r);
                if idx < 1 || idx > n
                    continue
                end
                neuron = app.image_neurons.neurons(round(idx));
                neuron.deterministic_id = char(string(predictions.predicted_class(r)));
                neuron.rank = r;
                if ismember('top5_classes', predictions.Properties.VariableNames)
                    names = strsplit(char(string(predictions.top5_classes(r))), ',');
                    neuron.probabilistic_ids = names;
                end
                if ismember('top5_probs', predictions.Properties.VariableNames)
                    probs = str2double(strsplit(char(string(predictions.top5_probs(r))), ','));
                    neuron.probabilistic_probs = probs;
                else
                    neuron.probabilistic_probs = double(predictions.confidence(r));
                end
            end
        end

        function prediction_to_neuron = matchPredictionRows(app, predictions)
            n_predictions = height(predictions);
            prediction_to_neuron = zeros(n_predictions, 1);
            n = app.image_neurons.num_neurons();

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
                    for r = 1:n_predictions
                        delta = neuron_um - prediction_um(r, :);
                        distances = sqrt(sum(delta.^2, 2));
                        distances(~available) = inf;
                        [best_distance, best_idx] = min(distances);
                        if isfinite(best_distance) && best_distance <= max_distance_um
                            prediction_to_neuron(r) = best_idx;
                            available(best_idx) = false;
                        end
                    end

                    if any(prediction_to_neuron > 0)
                        return
                    end
                catch
                    prediction_to_neuron(:) = 0;
                end
            end

            if ismember('neuron_idx', predictions.Properties.VariableNames)
                for r = 1:n_predictions
                    idx = double(predictions.neuron_idx(r)) + 1;
                    if idx >= 1 && idx <= n
                        prediction_to_neuron(r) = round(idx);
                    end
                end
            end
        end

        function progress = openProgressDialog(app)
            progress = [];
            try
                progress = uiprogressdlg(app.CELL_ID, ...
                    'Title', 'Transformer Auto-ID', ...
                    'Message', 'Preparing transformer auto-ID...', ...
                    'Indeterminate', 'on', ...
                    'Cancelable', 'off');
                drawnow limitrate;
            catch
                progress = [];
            end
        end

        function updateProgress(progress, message)
            if isempty(progress) || ~isvalid(progress)
                return
            end
            progress.Message = char(string(message));
            drawnow limitrate;
        end

        function closeProgressDialog(progress)
            if isempty(progress) || ~isvalid(progress)
                return
            end
            try
                close(progress);
            catch
            end
        end
    end
end
