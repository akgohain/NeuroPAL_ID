classdef MoEDetect
    %MOEDETECT Experimental fold-00 nonlinear ensemble, without annotations.
    methods (Static)
        function [supervoxels, params] = detect(titlestr, data, scale_um_xyz, options)
            arguments
                titlestr
                data
                scale_um_xyz double
                options.BundlePath (1,1) string = ""
                options.PythonExecutable (1,1) string = ""
                options.DatasetID (1,1) string = "unknown"
                options.Device (1,1) string = "cpu"
                options.OutputDir (1,1) string = ""
                options.KeepArtifacts (1,1) logical = true
                options.ColorReadoutData = []
            end
            progress = Methods.MLProgress.open("Nonlinear MoE", "Checking model bundle...");
            if ~isempty(progress), progress.Cancelable = 'on'; end
            cleanup = onCleanup(@() Methods.MLProgress.close(progress));
            response = Wrapper.runMoECentroids(data, scale_um_xyz, ...
                'BundlePath', options.BundlePath, 'PythonExecutable', options.PythonExecutable, ...
                'DatasetID', options.DatasetID, 'Device', options.Device, ...
                'OutputDir', options.OutputDir, 'KeepArtifacts', options.KeepArtifacts, ...
                'ProgressFcn', Methods.MLProgress.callback(progress), ...
                'CancelFcn', @() Methods.MoEDetect.cancelled(progress));
            params = response;
            params.backend = 'detection_moe';
            params.source_title = char(string(titlestr));
            params.bundle_path = char(options.BundlePath);
            params.k = response.num_centroids;
            supervoxels = [];
            if response.num_centroids == 0, return; end
            readout = options.ColorReadoutData;
            if isempty(readout), readout = data; end
            supervoxels = Methods.CellposeDetect.centroidsToSupervoxels(response.centroids_yxz, readout);
            % Sample colors at integer voxels, retain subpixel detector coordinates.
            supervoxels.positions = response.centroids_yxz;
        end

        function value = cancelled(progress)
            value = ~isempty(progress) && (~isvalid(progress) || progress.CancelRequested);
        end
    end
end
