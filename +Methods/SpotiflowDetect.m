classdef SpotiflowDetect
    %SPOTIFLOWDETECT NeuroPAL app adapter for a packaged Spotiflow model.

    methods (Static)
        function [supervoxels, params] = detect(titlestr, data, scale_um_xyz, options)
            arguments
                titlestr
                data
                scale_um_xyz double
                options.BundlePath (1,1) string = ""
                options.PythonExecutable (1,1) string = ""
                options.ProbabilityThreshold (1,1) double = NaN
                options.MinimumDistance (1,1) double = 1
                options.Device (1,1) string = "auto"
                options.OutputDir (1,1) string = ""
                options.KeepArtifacts (1,1) logical = true
                options.ColorReadoutData = []
            end

            progress = Methods.MLProgress.open( ...
                "Spotiflow Detection", "Preparing Spotiflow request...");
            cleanup = onCleanup(@() Methods.MLProgress.close(progress));
            response = Wrapper.runSpotiflowCentroids(data, scale_um_xyz, ...
                'BundlePath', options.BundlePath, ...
                'PythonExecutable', options.PythonExecutable, ...
                'ProbabilityThreshold', options.ProbabilityThreshold, ...
                'MinimumDistance', options.MinimumDistance, ...
                'Device', options.Device, ...
                'OutputDir', options.OutputDir, ...
                'KeepArtifacts', options.KeepArtifacts, ...
                'ProgressFcn', @(message) Methods.MLProgress.update(progress, string(message), []));

            params = struct( ...
                'backend', 'spotiflow_supervised', ...
                'k', 0, ...
                'source_title', char(string(titlestr)), ...
                'bundle_path', char(options.BundlePath));
            if isfield(response, 'policy')
                params.policy = response.policy;
            end
            if isfield(response, 'source_revision')
                params.source_revision = response.source_revision;
            end
            if isfield(response, 'model_manifest_sha256')
                params.model_manifest_sha256 = response.model_manifest_sha256;
            end
            if isfield(response, 'predictions_csv')
                params.predictions_csv = response.predictions_csv;
            end
            if ~isfield(response, 'centroids_yxz') || isempty(response.centroids_yxz)
                supervoxels = [];
                return
            end
            centroids = double(response.centroids_yxz);
            if isvector(centroids)
                centroids = reshape(centroids, 1, []);
            end
            readout = options.ColorReadoutData;
            if isempty(readout)
                readout = data;
            end
            supervoxels = Methods.CellposeDetect.centroidsToSupervoxels(centroids(:, 1:3), readout);
            params.k = size(supervoxels.positions, 1);
        end
    end
end
