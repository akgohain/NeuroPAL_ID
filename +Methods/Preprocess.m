classdef Preprocess < handle
    %PREPROCESS preprocesssing tools for NeuroPAL images
    
    properties
        
    end
    
    methods(Static)
        
        function obj = instance()
             persistent instance
             if isempty(instance)
                obj = AutoDetect();
                instance = obj;
             else
                obj = instance;
             end
        end
      
        function thresh = threshold_frame(video, method, sensitivity)
        % Thresholding multi-color volume
        %
        % Amin Nejat
            thresh = 0*video;

            for ch = 1: size(video, 4)
                vol = squeeze(video(:,:,:,ch,:));
                if strcmp(method, 'adaptive')
                    BW = imbinarize(vol/max(vol(:)), 'adaptive', 'Sensitivity', sensitivity);
                    vol(~BW) = 0;
                    vol = imclearborder(vol);
                    thresh(:,:,:,ch,:) = vol;
                elseif strcmp(method, 'global')
                    BW = imbinarize(vol/max(vol(:)), 'global');
                    vol(~BW) = 0;
                    vol = imclearborder(vol);
                    thresh(:,:,:,ch,:) = vol;
                elseif strcmp(method, 'otsu')
                    vol(vol < graythresh(vol(:))) = 0;
                    thresh(:,:,:,ch,:) = vol;
                elseif strcmp(method, 'fixed')
                    vol(vol < sensitivity) = 0;
                    thresh(:,:,:,ch,:) = vol;
                end
            end

        end
        
       function decimated = decimate_frame(video, new_size, method)
        % decimating a multi-dimensional array
        % DECIMATED = DECIMATE_FRAME(VIDEO, NEW_SIZE, METHOD) decimates the
        % multi-dimensional array VIDEO to size specified by NEW_SIZE. METHOD
        % options are:
        %   'linear'
        %   'nearest'
        %
        % See also RUN_FRAMES
        %
        % Amin Nejat
            new_size = round(new_size);
            new_size = new_size(1: 3);
            decimated = nan(new_size(1), new_size(2), new_size(3), size(video, 4));
            for ch = 1: size(video, 4)
                decimated(:, :, :, ch) = imresize3(video(:, :, :, ch), new_size, method);
            end
       end
       
       function hmvideo = histmatch_frame(video)
        % matching the histogram of the intensities for different colors to
        % normalize different color channels for better visualization
        % Amin Nejat
            hmvideo = zeros(size(video));
            exprand = exprnd(1, 1, numel(find(video > 0)));

            for ch = 1: size(video, 4)
                vol = squeeze(video(:,:,:,ch,:));
                posvol = vol(vol > 0);

                result = vol;
                result(vol > 0) = imhistmatchn(posvol(:)/max(posvol(:)), exprand/max(exprand(:)), 100000);
                hmvideo(:,:,:,ch,:) = reshape(result, size(vol));
            end
       end

       function nvideo = normalize_frame(video, background_percentile, max_percentile)
        % Normalize each channel with percentile-based black/white points.
            if nargin < 2
                percentiles = Methods.Preprocess.normalize_percentile_defaults();
            else
                if nargin < 3
                    max_percentile = [];
                end
                percentiles = Methods.Preprocess.validate_normalize_percentiles( ...
                    background_percentile, max_percentile);
            end

            background_percentile = percentiles(1);
            max_percentile = percentiles(2);
            nvideo = zeros(size(video), 'like', video);

            for ch = 1:size(video, 4)
                data = double(video(:,:,:,ch,:));
                finite_mask = isfinite(data);
                if ~any(finite_mask(:))
                    continue
                end

                data(~finite_mask) = 0;
                finite_vals = data(finite_mask);
                background_val = prctile(finite_vals, background_percentile);
                data = data - background_val;
                data(data < 0) = 0;

                foreground_vals = data(finite_mask);
                foreground_vals = foreground_vals(foreground_vals > 0);
                if isempty(foreground_vals)
                    continue
                end

                max_val = prctile(foreground_vals, max_percentile);
                if ~isfinite(max_val) || max_val <= 0
                    continue
                end

                data(data > max_val) = max_val;
                normalized = data / max_val;
                if isfloat(video)
                    nvideo(:,:,:,ch,:) = cast(normalized, class(video));
                else
                    scale = double(intmax(class(video)));
                    nvideo(:,:,:,ch,:) = cast(round(scale * normalized), class(video));
                end
            end
       end

       function percentiles = normalize_percentile_defaults()
            percentiles = [1, 99.9];
       end

       function percentiles = validate_normalize_percentiles(background_percentile, max_percentile)
            defaults = Methods.Preprocess.normalize_percentile_defaults();
            if nargin < 1 || isempty(background_percentile)
                background_percentile = defaults(1);
            end
            if nargin < 2 || isempty(max_percentile)
                max_percentile = defaults(2);
            end

            percentiles = [double(background_percentile), double(max_percentile)];
            if numel(percentiles) ~= 2 || any(~isfinite(percentiles)) || ...
                    percentiles(1) < 0 || percentiles(1) >= 100 || ...
                    percentiles(2) <= 0 || percentiles(2) > 100
                error('NeuroPAL:NormalizePercentiles', ...
                    'Background percentile must be at least 0 and less than 100. Max percentile must be greater than 0 and at most 100.');
            end
       end
        
       function volume = area_filter(volume, point, threshold, dim)
        % Heuristic filter for removing objects in a multi-color volume.
        %
        % Amin Nejat
            point = round(point);

            g = volume(:,:,:,dim);
            g(g < threshold) = 0;
            a = bwlabeln(g,26);

            mask = logical(0*a);
            mask(a == a(point(1), point(2), point(3))) = 1;
            mask = repmat(mask, 1,1,1,size(volume,4));
            volume(mask) = 0;

       end

        function zvideo = zscore_frame(video)
        % Z-scoring different color channels of the multi-color multi-dimensional
        % video. The colors must be in the 4th dimension. 
        %
        % Amin Nejat
            zvideo = zeros(size(video));
            for ch = 1: size(video,4)
                data = double(video(:,:,:,ch,:));
                zvideo(:,:,:,ch,:) = (data-nanmean(data(:)))/nanstd(data(:));
            end
        end
        
        function rho = filter_frame(frame, filter)
        % applying a filter to multi-color RGB image
        % Amin Nejat
            rho = 0*frame;
            for ch = 1: size(frame, 4)
                D = squeeze(frame(:, :, :, ch));
                rho(:, :, :, ch) =  imfilter(D, filter, 'same');
            end
        end
        
        
        
        function mask =  filter_small_artifacts(data, filter_color)
        % Generate marks for filtering artifacts smaller than neurons. 
        % Input: 
        %        data: data to filter
        %        filter_color: color of small artifacts 
        % Output:      
        %        green_mask: 2D matrix showing pixels to be filtered
        % Ruoxi Sun
        
            if filter_color == "red" 
                data_color = data(:,:,:,1);
            elseif filter_color == "green"
                data_color = data(:,:,:,2);
            elseif filter_color == "blue"
                data_color = data(:,:,:,3);
            else
                error('colors have to be red, green, blue')
            end
      
            %green = data(:,:,:,2); 
            data_color = imgaussfilt(data_color, .7); 
            thre = prctile( data_color(:) , 99 ); 
            BW = (data_color>thre);
            
            % connected components
            CC = bwconncomp(BW); 
            if CC.NumObjects==0
                mask=false(size(data_color));
                return;
            end
 
            stats = regionprops3(BW, 'Volume', 'Centroid', 'BoundingBox', 'ConvexVolume'); 
            stats = table2array(stats); 
            % filter by size
            idx = find(stats(:,1)<130);
            % generate the filtering mask 
            CC1 = CC;
            CC1.PixelIdxList = CC.PixelIdxList(idx); 
            CC1.NumObjects = length(CC.PixelIdxList(idx));
            LL = labelmatrix(CC1);
            mask = (LL>0); 
        end
            
            
       function [green_mask, green_square] =  filter_gut(data)
        % Generate marks for filtering gut (big green area) 
        % Input: 
        %        data: data to filter 
        % Output:      
        %        green_mask: convex hall over gut area 
        %        green_square: square over gut area 
        % Ruoxi Sun
           
            %green
            green = data(:,:,:,2); 
            green1 = imgaussfilt(green, .7); 
            thre = prctile(green1(:), 99); 
            thre = max(thre, 2.8);
            BW = (green1>thre);  
            %red
            red = data(:,:,:,1); 
            red1 = imgaussfilt(red, .7); 
            thre = prctile(red1(:), 99); 
            BW = BW.*(red1<thre);  
            %blue
            blue = data(:,:,:,3); 
            blue1 = imgaussfilt(blue, .7); 
            thre = prctile(blue1(:), 99); 
            thre = max(thre, 2.8);
            BW = logical(BW.*(blue1<thre));  

            CC = bwconncomp(BW); 
            if CC.NumObjects==0
                green_mask=false(size(green));
                green_square=false(size(green));
                return;
            end
            % filter by size and convex hall size  
            stats = regionprops3(BW, 'Volume', 'Centroid', 'BoundingBox', 'ConvexVolume'); 
            ConvexImage = regionprops3(BW, 'ConvexImage');
            stats = table2array(stats); 

            idx = find(stats(:,1)>1900 & stats(:,11)>6000);
            % big green objects on later frames are more likely to be filtered out 
            idx_end = find(stats(:,1)>1000 & stats(:,4)>size(data,3)-13 & stats(:,11)>1700);
            idx1 = union(idx, idx_end);
            select = stats(idx1,:); 

            green_mask = false(size(green));
            green_square = false(size(green));
            for i = 1:size(select,1)
                 tmp = table2array(ConvexImage(idx1(i),1));
                 xrange = round(select(i,5):select(i,5)+select(i,8)-1);
                 yrange = round(select(i,6):select(i,6)+select(i,9)-1);
                 zrange = round(select(i,7):select(i,7)+select(i,10)-1);
                 green_mask(yrange, xrange, zrange) = permute(tmp{:}, [1,2,3]);
                 green_square(yrange, xrange, zrange) = 1; 
            end
       end
        
                
        function [data_filter, mask] = filter_gut_lysosomes(data, mask_only)
        % filtering gut cells (big green artifacts) and lysosomes (small blue artifacts)
        % Input: 
        %        data: data to filter (z scored)
        % Output:
        %        data_filter: data after filtering
        %        mask: 2D matrix showing pixels filtered
        % Ruoxi Sun

            if nargin < 2, mask_only = false; end
            if isempty(data) || ~isnumeric(data) || ~isreal(data) || ...
                    ndims(data)>4 || size(data,4)<3
                error('NeuroPAL:ArtifactRGB', 'Automatic artifact removal requires a red, green and blue image volume.');
            end

            % generate masks to filter out
            % lysosomes        
            mask_g  =  Methods.Preprocess.filter_small_artifacts(data, 'green');  
            mask_b  =  Methods.Preprocess.filter_small_artifacts(data, 'blue'); 
            % gut
            [green_mask, green_square] =  Methods.Preprocess.filter_gut(data);   
            mask = logical(green_square) | mask_g | mask_b;
            data_filter = [];
            if mask_only, return; end
            square_cat = repmat(green_square,[1,1,1,size(data,4)]);
            
            % filter
            g = data(:,:,:,2);
            b = data(:,:,:,3);
            g(mask_g==1) = 0; 
            b(mask_b==1) = 0;
            data_filter = data;
            data_filter(:,:,:,2) = g; 
            data_filter(:,:,:,3) = b; 
            data_filter(square_cat==1) = 0; 

        end
        
        function mask = automatic_artifact_mask(data, rgb)
            % Use the current source pixels, without an all-channel z-score cache.
            if isempty(data) || ~(isnumeric(data) || islogical(data)) || ~isreal(data) || ndims(data)>4
                error('NeuroPAL:ArtifactImage', 'Open a NeuroPAL image volume before removing artifacts.');
            end
            if nargin<2, rgb=1:3; end
            if ~isnumeric(rgb) || numel(rgb)~=3 || numel(unique(rgb))~=3 || ...
                    any(~isfinite(rgb) | rgb<1 | rgb~=round(rgb) | rgb>size(data,4))
                error('NeuroPAL:ArtifactRGB', 'Automatic removal needs three distinct red, green and blue source channels. Use manual removal for one or two channels.');
            end
            if size(data,3)<2
                error('NeuroPAL:ArtifactDepth', 'Automatic removal requires a volume with at least two Z slices. Use manual removal for a single image plane.');
            end
            count=double(size(data,1))*size(data,2)*size(data,3);
            if count*3*4>512*2^20
                error('NeuroPAL:ArtifactMemory', 'This volume is too large for automatic artifact removal. Crop or downsample the image, or use manual removal.');
            end
            readout=Methods.ColorReadout(data,rgb); readout=readout.prepare();
            normalized=zeros(size(data,1),size(data,2),size(data,3),3,'single');
            chunk=2^20;
            for channel=1:3
                offset=(rgb(channel)-1)*count;
                for first=1:chunk:count
                    indices=first:min(first+chunk-1,count);
                    values=single(data(offset+indices));
                    if any(~isfinite(values))
                        error('NeuroPAL:ArtifactIntensity', 'The selected image channels contain nonfinite values. Clean the image before automatic removal.');
                    end
                    if isfinite(readout.Deviation(channel)) && readout.Deviation(channel)>0
                        normalized((channel-1)*count+indices)= ...
                            (values-single(readout.Average(channel)))/single(readout.Deviation(channel));
                    end
                end
            end
            [~,mask]=Methods.Preprocess.filter_gut_lysosomes(normalized,true);
        end

        function projection = manual_artifact_projection(data, layout)
            % Keep RGB projections distinct from volumes with a channel axis.
            if nargin<2, layout='YXZC'; end
            if isempty(data) || ~(isnumeric(data) || islogical(data)) || ~isreal(data)
                error('NeuroPAL:ArtifactImage', 'Open a NeuroPAL image volume before removing artifacts.');
            end
            switch upper(char(layout))
                case 'YXZC'
                    if ndims(data)>4
                        error('NeuroPAL:ArtifactLayout', 'Choose one image volume, not a time series, for manual artifact removal.');
                    end
                    channels=size(data,4);
                    projection=reshape(max(data,[],3),size(data,1),size(data,2),channels);
                case 'YXC'
                    if ndims(data)>3
                        error('NeuroPAL:ArtifactLayout', 'The manual preview must be a two-dimensional grayscale or RGB image.');
                    end
                    channels=size(data,3); projection=data;
                otherwise
                    error('NeuroPAL:ArtifactLayout', 'Use YXZC for an image volume or YXC for its display projection.');
            end
            if channels>4
                error('NeuroPAL:ArtifactChannels', 'Select at most four display channels for the manual artifact preview.');
            end
            if channels==1
                projection=repmat(projection,1,1,3);
            elseif channels==2
                projection=cat(3,projection,zeros(size(data,1),size(data,2),'like',data));
            else
                projection=projection(:,:,1:3);
            end
        end

        function mask = manual_artifact_removal(data, layout)
            %MANUAL_ARTIFACT_REMOVAL manually remove image artifacts.
            if nargin<2, layout='YXZC'; end
            projection=Methods.Preprocess.manual_artifact_projection(data,layout);

            % Draw the max projection.
            fig=uifigure('Name','Manually Remove Artifacts','Tag','ManualArtifactRemoval');
            cleanup=onCleanup(@() Methods.Preprocess.close_artifact_figure(fig));
            grid=uigridlayout(fig,[1 1]); grid.Padding=[0 0 0 0];
            ax=uiaxes(grid); image(ax,projection);
            
            % Correct the aspect ratio.
            fig.WindowState='maximized';
            axis(ax,'image');
            daspect(ax,[1,1,1]);
            ax.YDir='reverse';
            ax.Visible = 'off';
            ax.Toolbar.Visible='off';
            drawnow;
            
            % Get the artifact polygon.
            try
                h = drawpolygon(ax, 'FaceAlpha',0);
            catch ME
                if ~isgraphics(fig), mask=[]; return; end
                rethrow(ME);
            end
            
            % Generate the polygon mask.
            mask = [];
            if ~isempty(h) && isvalid(h) && size(h.Position,1)>=3
                mask = poly2mask(h.Position(:,1), h.Position(:,2), ...
                    size(data,1), size(data,2));
            end
        end

        function close_artifact_figure(fig)
            if isgraphics(fig), delete(fig); end
        end

    end
end
