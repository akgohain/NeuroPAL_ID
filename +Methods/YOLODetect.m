classdef YOLODetect
    %YOLODETECT Adapter for Swetha YOLO slice detection + 3D fusion.

    methods(Static)
        function [supervoxels, params] = detect(titlestr, data, scale_um_xyz, options)
            arguments
                titlestr
                data
                scale_um_xyz double
                options.Conf (1,1) double = 0.25
                options.ImgSize (1,1) double = 640
                options.BoxMinPx (1,1) double = 2
                options.BoxMaxPx (1,1) double = 80
                options.FuseMaxDz (1,1) double = 1
                options.IoUMin (1,1) double = 0.5
                options.ColorDotMin (1,1) double = 0.8
                options.DepthSanityRatioCap (1,1) double = 1.5
                options.Device (1,1) string = ""
                options.OutputDir (1,1) string = ""
                options.KeepArtifacts (1,1) logical = false
                options.WeightsPath (1,1) string = ""
                options.PythonExecutable (1,1) string = ""
                options.ColorReadoutData = []
            end

            progress = Methods.YOLODetect.openProgressDialog();
            cleanup = onCleanup(@() Methods.YOLODetect.closeProgressDialog(progress)); %#ok<NASGU>
            Methods.YOLODetect.updateProgress(progress, 'Preparing YOLO input...');

            response = Wrapper.runYoloCentroids(data, scale_um_xyz, ...
                'Conf', options.Conf, ...
                'ImgSize', options.ImgSize, ...
                'BoxMinPx', options.BoxMinPx, ...
                'BoxMaxPx', options.BoxMaxPx, ...
                'FuseMaxDz', options.FuseMaxDz, ...
                'IoUMin', options.IoUMin, ...
                'ColorDotMin', options.ColorDotMin, ...
                'DepthSanityRatioCap', options.DepthSanityRatioCap, ...
                'Device', options.Device, ...
                'OutputDir', options.OutputDir, ...
                'KeepArtifacts', options.KeepArtifacts, ...
                'WeightsPath', options.WeightsPath, ...
                'PythonExecutable', options.PythonExecutable, ...
                'ProgressFcn', @(message) Methods.YOLODetect.updateProgress(progress, message));

            params = Methods.YOLODetect.buildParams(response, 0, options);
            if ~isfield(response, 'centroids_yxz') || isempty(response.centroids_yxz)
                supervoxels = [];
                return
            end

            centroids = double(response.centroids_yxz);
            if isvector(centroids)
                centroids = reshape(centroids, 1, []);
            end
            centroids = centroids(:, 1:3);

            color_readout_data = Methods.YOLODetect.resolveColorReadoutData(data, options.ColorReadoutData);
            supervoxels = Methods.CellposeDetect.centroidsToSupervoxels(centroids, color_readout_data);
            params = Methods.YOLODetect.buildParams(response, size(supervoxels.positions, 1), options);
            if ~isfield(params, 'source_title')
                params.source_title = char(string(titlestr));
            end
        end

        function params = buildParams(response, num_supervoxels, options)
            params = struct();
            params.backend = 'yolo';
            params.k = num_supervoxels;
            params.detect_scale = 0;
            params.hnsz = [10, 10, 3];
            params.min_eig_thresh = 0;
            params.exclusion_radius = 0;
            params.conf = options.Conf;
            params.imgsz = options.ImgSize;
            params.box_min_px = options.BoxMinPx;
            params.box_max_px = options.BoxMaxPx;
            params.fuse_max_dz = options.FuseMaxDz;
            params.iou_min = options.IoUMin;
            params.color_dot_min = options.ColorDotMin;
            params.depth_sanity_ratio_cap = options.DepthSanityRatioCap;
            fields = {'weights', 'summary_path', 'fused_csv', 'fused_png', 'volume_npy', ...
                'raw_boxes', 'filtered_boxes', 'num_centroids'};
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(response, f)
                    params.(f) = response.(f);
                end
            end
        end

        function data = resolveColorReadoutData(data, override)
            if ~isempty(override)
                data = override;
            end
        end

        function progress = openProgressDialog()
            progress = Methods.MLProgress.open( ...
                "YOLO Detection", "Preparing YOLO detection...");
        end

        function updateProgress(progress, message)
            Methods.MLProgress.update(progress, string(message), []);
        end

        function closeProgressDialog(progress)
            Methods.MLProgress.close(progress);
        end
    end
end
