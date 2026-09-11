classdef ColorReadout
    %COLORREADOUT Sample volume z-scores without storing a normalized volume.
    properties (SetAccess = private)
        Data
    end
    methods
        function obj = ColorReadout(data)
            obj.Data = data;
        end

        function varargout = size(obj, varargin)
            [varargout{1:nargout}] = size(obj.Data, varargin{:});
        end

        function colors = sample(obj, positions)
            dims = size(obj.Data);
            dims(end+1:4) = 1;
            colors = zeros(size(positions, 1), dims(4));
            if isempty(positions), return; end
            indices = sub2ind(dims(1:3), positions(:,1), positions(:,2), positions(:,3));
            count = prod(dims(1:3));
            chunk = 2^20;
            for channel = 1:dims(4)
                offset = (channel-1)*count;
                total = 0;
                valid_count = 0;
                for first = 1:chunk:count
                    values = double(obj.Data(offset+(first:min(first+chunk-1,count))));
                    values = values(~isnan(values));
                    total = total + sum(values);
                    valid_count = valid_count + numel(values);
                end
                average = total / valid_count;
                squared = 0;
                for first = 1:chunk:count
                    values = double(obj.Data(offset+(first:min(first+chunk-1,count))));
                    values = values(~isnan(values));
                    squared = squared + sum((values-average).^2);
                end
                deviation = sqrt(squared / max(valid_count-1,1));
                colors(:,channel) = (double(obj.Data(offset+indices))-average)/deviation;
            end
        end
    end
end
