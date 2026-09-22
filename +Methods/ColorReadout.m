classdef ColorReadout
    %COLORREADOUT Sample volume z-scores without storing a normalized volume.
    properties (SetAccess = private)
        Data
        Channels
        Average = []
        Deviation = []
    end
    methods
        function obj = ColorReadout(data, channels)
            obj.Data = data;
            if nargin < 2, channels = 1:size(data,4); end
            obj.Channels = channels;
        end

        function varargout = size(obj, varargin)
            dims = [size(obj.Data,1), size(obj.Data,2), size(obj.Data,3), numel(obj.Channels)];
            if ~isempty(varargin)
                requested = varargin{1};
                dims(end+1:max(requested)) = 1;
                varargout{1} = dims(requested);
            elseif nargout <= 1
                varargout{1} = dims;
            else
                dims(end+1:nargout) = 1;
                for i = 1:nargout-1, varargout{i} = dims(i); end
                varargout{nargout} = prod(dims(nargout:end));
            end
        end

        function patch = subcube(obj, position, radius)
            % Normalize only the requested patch; keep edge padding at zero.
            radius = round(radius);
            [y,x,z] = ndgrid(position(1)+(-radius(1):radius(1)), ...
                position(2)+(-radius(2):radius(2)), position(3)+(-radius(3):radius(3)));
            positions = [y(:), x(:), z(:)];
            dims = size(obj);
            inside = all(positions >= 1 & positions <= dims(1:3), 2);
            colors = zeros(size(positions,1), dims(4));
            colors(inside,:) = obj.sample(positions(inside,:));
            patch = reshape(colors, [2*radius+1, dims(4)]);
        end

        function colors = sample(obj, positions)
            dims = size(obj);
            colors = zeros(size(positions, 1), dims(4));
            if isempty(positions), return; end
            indices = sub2ind(dims(1:3), positions(:,1), positions(:,2), positions(:,3));
            obj = obj.prepare();
            count = prod(dims(1:3));
            for channel = 1:dims(4)
                if isnan(obj.Channels(channel))
                    colors(:,channel) = NaN;
                    continue
                end
                offset = (obj.Channels(channel)-1)*count;
                colors(:,channel) = (double(obj.Data(offset+indices))-obj.Average(channel)) / obj.Deviation(channel);
            end
        end

        function obj = prepare(obj)
            % Reuse channel statistics across patches from the same image.
            if ~isempty(obj.Average), return; end
            count = size(obj.Data,1)*size(obj.Data,2)*size(obj.Data,3);
            obj.Average = nan(1,numel(obj.Channels));
            obj.Deviation = nan(1,numel(obj.Channels));
            chunk = 2^20;
            for channel = 1:numel(obj.Channels)
                if isnan(obj.Channels(channel))
                    continue
                end
                offset = (obj.Channels(channel)-1)*count;
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
                obj.Average(channel) = average;
                obj.Deviation(channel) = deviation;
            end
        end
    end
end
