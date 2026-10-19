classdef MoEDetect
    %MOEDETECT Fold-00 nonlinear ensemble, without annotations.
    methods (Static)
        function [supervoxels, params] = detect(titlestr, data, scale_um_xyz, options)
            arguments
                titlestr
                data
                scale_um_xyz double
                options.InputMode (1,1) string = "rgbw"
                options.SelectedChannels double = []
                options.MergeRadiusUm (1,1) double = 2
                options.ScoreThreshold (1,1) double = NaN
                options.BundlePath (1,1) string = ""
                options.PythonExecutable (1,1) string = ""
                options.DatasetID (1,1) string = "unknown"
                options.Device (1,1) string = "cpu"
                options.OutputDir (1,1) string = ""
                options.KeepArtifacts (1,1) logical = true
                options.ColorReadoutData = []
                options.JobToken (1,1) string = ""
            end
            progress = Methods.MLProgress.open("Nonlinear MoE", "Checking model bundle...");
            if ~isempty(progress), progress.Cancelable = 'on'; end
            cleanup = onCleanup(@() Methods.MLProgress.close(progress));
            if options.InputMode=="multi_channel"
                detector=@(varargin) Wrapper.runMoECentroids(varargin{:}, ...
                    'BundlePath',options.BundlePath,'PythonExecutable',options.PythonExecutable, ...
                    'DatasetID',options.DatasetID,'Device',options.Device,'KeepArtifacts',options.KeepArtifacts);
                response=Wrapper.runMultiChannelCentroids(data,options.SelectedChannels,scale_um_xyz, ...
                    'JobToken',options.JobToken,'DetectFcn',detector,'OutputDir',options.OutputDir, ...
                    'MergeRadiusUm',options.MergeRadiusUm, ...
                    'ScoreThreshold',options.ScoreThreshold, ...
                    'ProgressFcn',Methods.MLProgress.callback(progress), ...
                    'CancelFcn',@() Methods.MoEDetect.cancelled(progress));
            else
                response = Wrapper.runMoECentroids(data, scale_um_xyz, ...
                    'InputMode',options.InputMode,'JobToken', options.JobToken, ...
                    'ScoreThreshold',options.ScoreThreshold, ...
                    'BundlePath', options.BundlePath, 'PythonExecutable', options.PythonExecutable, ...
                    'DatasetID', options.DatasetID, 'Device', options.Device, ...
                    'OutputDir', options.OutputDir, 'KeepArtifacts', options.KeepArtifacts, ...
                    'ProgressFcn', Methods.MLProgress.callback(progress), ...
                    'CancelFcn', @() Methods.MoEDetect.cancelled(progress));
            end
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
