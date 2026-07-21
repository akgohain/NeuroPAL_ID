classdef MethodContract
    %METHODCONTRACT Validation boundary for external detector/ID adapters.

    methods (Static)
        function result = detection(result)
            if ~istable(result)
                error('Methods:MethodContract:DetectionNotTable', ...
                    'Detection results must be a MATLAB table.');
            end
            required = {'x_um', 'y_um', 'z_um', 'score'};
            Methods.MethodContract.requireColumns(result, required, 'detection');
            values = double(result{:, required});
            if any(~isfinite(values), 'all')
                error('Methods:MethodContract:NonFiniteDetection', ...
                    'Detection coordinates and scores must be finite.');
            end
            if any(result.score < 0 | result.score > 1)
                error('Methods:MethodContract:InvalidDetectionScore', ...
                    'Detection scores must lie in [0, 1].');
            end
        end

        function result = identity(result)
            if ~istable(result)
                error('Methods:MethodContract:IdentityNotTable', ...
                    'Identity results must be a MATLAB table.');
            end
            required = {'neuron_idx', 'predicted_class', 'confidence'};
            Methods.MethodContract.requireColumns(result, required, 'identity');
            if any(~isfinite(double(result.neuron_idx))) || ...
                    any(double(result.neuron_idx) < 1) || ...
                    any(mod(double(result.neuron_idx), 1) ~= 0)
                error('Methods:MethodContract:InvalidNeuronIndex', ...
                    'Identity neuron_idx values must be positive integers.');
            end
            confidence = double(result.confidence);
            if any(~isfinite(confidence)) || any(confidence < 0 | confidence > 1)
                error('Methods:MethodContract:InvalidIdentityConfidence', ...
                    'Identity confidence values must be finite and lie in [0, 1].');
            end
        end
    end

    methods (Static, Access = private)
        function requireColumns(result, required, kind)
            missing = setdiff(required, result.Properties.VariableNames, 'stable');
            if ~isempty(missing)
                error('Methods:MethodContract:MissingColumns', ...
                    '%s results are missing required columns: %s', ...
                    kind, strjoin(missing, ', '));
            end
        end
    end
end
