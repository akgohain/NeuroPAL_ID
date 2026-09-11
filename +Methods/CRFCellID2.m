classdef CRFCellID2
    %CRFCELLID2 App-facing request/import layer for CRF Cell-ID 2.0.

    methods (Static)
        function predictions = run(app, options)
            arguments
                app
                options.BundlePath (1,1) string = ""
                options.OutputDir (1,1) string = ""
                options.KeepArtifacts (1,1) logical = false
            end
            job = Program.HeavyJob.acquire('CRF auto-ID');
            job_cleanup = onCleanup(@() delete(job));
            input_context = Program.Helpers.main_job_context(app, true);
            if isempty(app.image_neurons) || app.image_neurons.num_neurons() < 1
                error('Methods:CRFCellID2:NoNeurons', ...
                    'Run auto-detection before CRF Cell-ID 2.0.');
            end

            positions = double(app.image_neurons.get_positions());
            neurons = app.image_neurons.neurons;
            colors = zeros(numel(neurons), 4);
            for i = 1:numel(neurons)
                value = double(neurons(i).color_readout(:)');
                if isempty(value)
                    value = double(neurons(i).color(:)');
                end
                value = value(1:min(4, numel(value)));
                colors(i, 1:numel(value)) = value;
            end

            predictions = Wrapper.runCRFID2AutoID(positions, colors, app.image_um_scale', ...
                'BundlePath', options.BundlePath, ...
                'OutputDir', options.OutputDir, ...
                'KeepArtifacts', options.KeepArtifacts);
            Program.Helpers.assert_main_job_context(app, input_context);
            Methods.TransformerAutoId.applyPredictions(app, predictions);
            Methods.TransformerAutoId.refreshAppUI(app);
        end
    end
end
