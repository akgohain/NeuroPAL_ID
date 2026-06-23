classdef YOLODetect
    %YOLODETECT Adapter for Swetha YOLO slice detection + 3D fusion.

    methods(Static)
        function [supervoxels, params] = detect(titlestr, data, scale_um_xyz, options)
            arguments
                titlestr
                data
                scale_um_xyz double
                options.Conf (1,1) double = 0.60
                options.ImgSize (1,1) double = 512
                options.BoxMinPx (1,1) double = 6
                options.BoxMaxPx (1,1) double = 120
                options.FuseMaxDz (1,1) double = 1
                options.IoUMin (1,1) double = 0.5
                options.PLo (1,1) double = 0.5
                options.PHi (1,1) double = 99.5
                options.ColorMatch (1,1) logical = false
                options.ColorDotMin (1,1) double = 0.8
                options.DepthSanityRatioCap (1,1) double = 2.0
                options.Device (1,1) string = ""
                options.OutputDir (1,1) string = ""
                options.KeepArtifacts (1,1) logical = false
                options.WeightsPath (1,1) string = ""
                options.PythonExecutable (1,1) string = ""
                options.ColorReadoutData = []
                options.LogFcn = []
            end

            Methods.YOLODetect.log(options.LogFcn, ...
                'YOLODetect.detect entered: title="%s", data=%s, scale=[%s], conf=%.3f, box=[%.1f %.1f], output="%s", keep_artifacts=%d', ...
                char(string(titlestr)), Methods.YOLODetect.arraySummary(data), ...
                Methods.YOLODetect.numvecSummary(scale_um_xyz), options.Conf, ...
                options.BoxMinPx, options.BoxMaxPx, char(options.OutputDir), options.KeepArtifacts);

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
                'PLo', options.PLo, ...
                'PHi', options.PHi, ...
                'ColorMatch', options.ColorMatch, ...
                'ColorDotMin', options.ColorDotMin, ...
                'DepthSanityRatioCap', options.DepthSanityRatioCap, ...
                'Device', options.Device, ...
                'OutputDir', options.OutputDir, ...
                'KeepArtifacts', options.KeepArtifacts, ...
                'WeightsPath', options.WeightsPath, ...
                'PythonExecutable', options.PythonExecutable, ...
                'ProgressFcn', @(message) Methods.YOLODetect.updateProgress(progress, message));

            Methods.YOLODetect.log(options.LogFcn, ...
                'YOLO wrapper response: fields=[%s], centroids_yxz=%s, raw_boxes=%s, filtered_boxes=%s, summary="%s"', ...
                strjoin(fieldnames(response), ', '), ...
                Methods.YOLODetect.responseFieldSummary(response, 'centroids_yxz'), ...
                Methods.YOLODetect.responseScalarSummary(response, 'raw_boxes'), ...
                Methods.YOLODetect.responseScalarSummary(response, 'filtered_boxes'), ...
                Methods.YOLODetect.responseScalarSummary(response, 'summary_path'));

            params = Methods.YOLODetect.buildParams(response, 0, options);
            if ~isfield(response, 'centroids_yxz') || isempty(response.centroids_yxz)
                Methods.YOLODetect.log(options.LogFcn, ...
                    'YOLO wrapper returned no centroids_yxz; returning empty supervoxels.');
                supervoxels = [];
                return
            end

            centroids = double(response.centroids_yxz);
            if isvector(centroids)
                centroids = reshape(centroids, 1, []);
            end
            centroids = centroids(:, 1:3);
            Methods.YOLODetect.log(options.LogFcn, ...
                'YOLO centroids parsed: %d rows, first_rows=%s', ...
                size(centroids, 1), Methods.YOLODetect.previewRows(centroids, 5));

            color_readout_data = Methods.YOLODetect.resolveColorReadoutData(data, options.ColorReadoutData);
            Methods.YOLODetect.log(options.LogFcn, ...
                'YOLO color readout resolved: %s', Methods.YOLODetect.arraySummary(color_readout_data));
            supervoxels = Methods.CellposeDetect.centroidsToSupervoxels(centroids, color_readout_data);
            params = Methods.YOLODetect.buildParams(response, size(supervoxels.positions, 1), options);
            Methods.YOLODetect.log(options.LogFcn, ...
                'YOLO supervoxels built: positions=%s, first_positions=%s', ...
                Methods.YOLODetect.arraySummary(supervoxels.positions), ...
                Methods.YOLODetect.previewRows(supervoxels.positions, 5));
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
            params.p_lo = options.PLo;
            params.p_hi = options.PHi;
            params.color_dot_min = options.ColorDotMin;
            params.depth_sanity_ratio_cap = options.DepthSanityRatioCap;
            params.color_match = options.ColorMatch;
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

        function log(log_fcn, varargin)
            if isempty(log_fcn) || ~isa(log_fcn, 'function_handle')
                return
            end
            try
                log_fcn(sprintf(varargin{:}));
            catch
            end
        end

        function text = arraySummary(value)
            try
                dims = size(value);
                text = sprintf('%s [%s]', class(value), Methods.YOLODetect.numvecSummary(dims));
            catch
                text = '<unavailable>';
            end
        end

        function text = numvecSummary(value)
            if isempty(value)
                text = '';
                return
            end
            text = strjoin(arrayfun(@(v) sprintf('%g', v), double(value(:))', ...
                'UniformOutput', false), 'x');
        end

        function text = responseFieldSummary(response, field_name)
            if ~isfield(response, field_name)
                text = '<missing>';
                return
            end
            value = response.(field_name);
            if isempty(value)
                text = '<empty>';
                return
            end
            text = Methods.YOLODetect.arraySummary(value);
        end

        function text = responseScalarSummary(response, field_name)
            if ~isfield(response, field_name)
                text = '<missing>';
                return
            end
            value = response.(field_name);
            if isnumeric(value) || islogical(value)
                text = mat2str(value);
            else
                text = char(string(value));
            end
        end

        function text = previewRows(values, max_rows)
            if isempty(values)
                text = '<empty>';
                return
            end
            n_rows = min(size(values, 1), max_rows);
            preview = values(1:n_rows, :);
            text = mat2str(preview, 4);
        end
    end
end
