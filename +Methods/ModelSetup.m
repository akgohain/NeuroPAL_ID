classdef ModelSetup
    %MODELSETUP Check model files before staging images or changing annotations.

    methods (Static)
        function detection(method, params)
            if nargin < 2, params = struct(); end
            switch char(string(method))
                case 'nn'
                    Methods.NNDetect.instance();
                case 'cellpose'
                    if ~strcmpi(Methods.ModelSetup.value(params, 'mode', 'cellpose'), 'stub')
                        Methods.ModelSetup.cellpose(Methods.ModelSetup.value(params, 'model_path', ''));
                    end
                case 'yolo'
                    Methods.ModelSetup.yolo(Methods.ModelSetup.value(params, 'weights_path', ''));
                case {'spotiflow_supervised', 'detection_moe'}
                    Methods.ModelSetup.bundle(method, Methods.ModelSetup.value(params, 'bundle_path', ''));
            end
        end

        function readiness = bundle(method, bundle_path)
            readiness = Methods.MethodBundle.inspect(method, bundle_path);
            if readiness.ready, return; end
            switch char(string(method))
                case 'detection_moe'
                    identifier = 'Wrapper:MoEBundleUnavailable';
                case 'spotiflow_supervised'
                    identifier = 'Wrapper:SpotiflowBundleUnavailable';
                case 'crf_cellid_2'
                    identifier = 'Wrapper:CRFID2BundleUnavailable';
                otherwise
                    identifier = 'Methods:MethodBundle:NotReady';
            end
            error(identifier, '%s\n\nBundle: %s', readiness.summary, readiness.bundle_path);
        end

        function [repo_dir, checkpoint_path] = transformer(repo_option, checkpoint_option, script_name)
            if nargin < 3, script_name = 'run_app_volume_inference.py'; end
            [repo_dir, checkpoint_path] = Wrapper.resolveTransformerAssets(repo_option, checkpoint_option);
            if ~isfile(checkpoint_path) && ~isfolder(checkpoint_path)
                error('Wrapper:MissingTransformerCheckpoint', 'GAT checkpoint path not found: %s', checkpoint_path);
            end
            [ok, attributes] = fileattrib(checkpoint_path);
            if ok, checkpoint_path = attributes.Name; end
            run_dir = checkpoint_path;
            weights = checkpoint_path;
            if isfolder(checkpoint_path)
                % The Python loader selects best_model.pt for a run directory.
                weights = fullfile(checkpoint_path, 'best_model.pt');
            else
                run_dir = fileparts(checkpoint_path);
            end
            Methods.ModelSetup.requireFile(weights, 'Wrapper:MissingTransformerWeights', 'GAT weights');
            config_path = fullfile(run_dir, 'train_config.json');
            Methods.ModelSetup.requireFile(config_path, 'Wrapper:MissingTransformerConfig', 'GAT training configuration');
            try
                config = jsondecode(fileread(config_path));
                if ~isstruct(config) || ~isscalar(config)
                    error('Methods:ModelSetup:Config', 'Expected one configuration object.');
                end
            catch ME
                error('Wrapper:InvalidTransformerConfig', 'Cannot read %s: %s', config_path, ME.message);
            end
            Methods.ModelSetup.requireFile(fullfile(repo_dir, script_name), ...
                'Wrapper:MissingTransformerRepo', 'GAT inference script');
        end

        function path_value = yolo(path_value)
            if strlength(strtrim(string(path_value))) == 0
                profile = Runtime.Discovery.profile('yolo');
                path_value = profile.weights;
            end
            path_value = Methods.ModelSetup.requireFile(path_value, 'Wrapper:MissingYoloWeights', 'YOLO weights');
        end

        function path_value = cellpose(path_value)
            path_value = strtrim(char(string(path_value)));
            if isempty(path_value)
                profile = Runtime.Discovery.profile('cellpose'); path_value = profile.weights;
            end
            if any(strcmpi(path_value, {'cpsam', 'cyto', 'cyto2', 'nuclei'}))
                error('Wrapper:MissingCellposeModel', ...
                    'Choose downloaded Cellpose weights in Tools > Models & runtimes. Model checks never download weights implicitly.');
            end
            if isempty(path_value)
                error('Wrapper:MissingCellposeModel','Choose Cellpose weights in Tools > Models & runtimes.');
            end
            % An explicit missing path must not select a different model.
            path_value = Methods.ModelSetup.requireFile(path_value, 'Wrapper:MissingCellposeModel', 'Cellpose weights');
        end

        function path_value = neuralNetwork()
            path_value = which(Methods.NNDetect.NN_model);
            if isempty(path_value), path_value = Methods.NNDetect.NN_model; end
            path_value = Methods.ModelSetup.requireFile(path_value, 'Methods:NNDetect:MissingModel', 'Neural-network weights');
            if exist('DAGNetwork','class')~=8 || (~isdeployed && ~license('test','Neural_Network_Toolbox'))
                error('Methods:NNDetect:MissingToolbox', ...
                    'DAGNetwork support or its Deep Learning Toolbox license is unavailable.');
            end
        end

        function path_value = requireFile(path_value, identifier, description)
            path_value = char(string(path_value));
            if isempty(path_value) || ~isfile(path_value)
                error(identifier, '%s file not found: %s', description, path_value);
            end
            [ok, attributes] = fileattrib(path_value);
            if ok, path_value = attributes.Name; end
            info = dir(path_value);
            if isempty(info) || info(1).bytes == 0
                error(identifier, '%s file is empty: %s', description, path_value);
            end
            fid = fopen(path_value, 'r');
            if fid < 0
                error(identifier, '%s file cannot be read: %s', description, path_value);
            end
            fclose(fid);
        end
    end

    methods (Static, Access = private)
        function result = value(params, name, fallback)
            result = fallback;
            if isfield(params, name), result = params.(name); end
        end
    end
end
