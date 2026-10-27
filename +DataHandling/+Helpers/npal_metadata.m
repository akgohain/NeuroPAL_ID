classdef npal_metadata
    %NPAL_METADATA Validate headers before changing the image views.
    methods (Static)
        function [info,prefs,worm] = normalize(info,prefs,worm,dims)
            if ~isstruct(info) || ~isscalar(info) || ~isstruct(prefs) || ~isscalar(prefs)
                error('DataHandling:NeuroPALImage:InvalidMetadata','Image info and prefs must be scalar structures.');
            end
            dims(end+1:4)=1;
            if ~isfield(info,'scale') || ~isnumeric(info.scale) || ~isreal(info.scale) || ...
                    numel(info.scale)~=3 || any(~isfinite(info.scale(:)) | info.scale(:)<=0)
                error('DataHandling:NeuroPALImage:InvalidMetadata', ...
                    'Image info.scale must contain three finite, positive voxel sizes in micrometers.');
            end
            info.scale=double(info.scale(:)');
            if any(~isfinite(info.scale.*double(dims(1:3))))
                error('DataHandling:NeuroPALImage:InvalidMetadata','Voxel sizes exceed the supported physical image extent.');
            end
            for name={'RGBW','DIC','GFP'}
                key=name{1};
                if ~isfield(prefs,key) || isempty(prefs.(key)), prefs.(key)=NaN; end
                value=prefs.(key);
                if ~isnumeric(value) || ~isreal(value) || ~isvector(value)
                    error('DataHandling:NeuroPALImage:InvalidMetadata','Image prefs.%s must contain channel numbers.',key);
                end
                value=double(value(:)');
                value(~isfinite(value) | value<1 | value>dims(4) | value~=round(value))=NaN;
                if strcmp(key,'RGBW')
                    value(end+1:4)=NaN; value=value(1:4);
                else
                    valid=value(isfinite(value)); value=NaN;
                    if ~isempty(valid), value=valid(1); end
                end
                prefs.(key)=value;
            end
            if ~isfield(prefs,'gamma') || isempty(prefs.gamma)
                prefs.gamma=.8;
                if isfield(info,'gamma') && ~isempty(info.gamma), prefs.gamma=info.gamma; end
            end
            value=prefs.gamma;
            if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || numel(value)>6 || ...
                    any(~isfinite(value(:)) | value(:)<0)
                error('DataHandling:NeuroPALImage:InvalidMetadata','Image gamma must contain up to six finite, nonnegative values.');
            end
            prefs.gamma=double(value(:));
            if ~isfield(prefs,'rotate') || isempty(prefs.rotate), prefs.rotate=struct(); end
            if ~isstruct(prefs.rotate) || ~isscalar(prefs.rotate)
                error('DataHandling:NeuroPALImage:InvalidMetadata','Image prefs.rotate must be a scalar structure.');
            end
            for name={'horizontal','vertical'}
                key=name{1};
                if ~isfield(prefs.rotate,key), prefs.rotate.(key)=false; end
                prefs.rotate.(key)=DataHandling.Helpers.npal_metadata.flag(prefs.rotate.(key),['rotate.' key]);
            end
            for name={'is_Z_LR','is_Z_flip'}
                key=name{1};
                if ~isfield(prefs,key), prefs.(key)=true; end
                prefs.(key)=DataHandling.Helpers.npal_metadata.flag(prefs.(key),key);
            end
            if ~isfield(prefs,'z_center'), prefs.z_center=ceil(dims(3)/2); end
            if ~isnumeric(prefs.z_center) || ~isreal(prefs.z_center) || ~isscalar(prefs.z_center) || ~isfinite(prefs.z_center)
                error('DataHandling:NeuroPALImage:InvalidMetadata','Image prefs.z_center must be a finite scalar.');
            end
            if isempty(worm), worm=struct(); end
            if ~isstruct(worm) || ~isscalar(worm)
                error('DataHandling:NeuroPALImage:InvalidMetadata','The worm description must be a scalar structure.');
            end
            defaults=struct('body','Whole Worm','age','Adult','sex','Unknown','strain','','notes','');
            if isfield(prefs,'body_part')
                defaults.body=prefs.body_part; prefs=rmfield(prefs,'body_part');
            end
            fields=fieldnames(defaults);
            for i=1:numel(fields)
                key=fields{i};
                if ~isfield(worm,key) || isempty(worm.(key)), worm.(key)=defaults.(key); end
                value=worm.(key);
                if strcmp(key,'notes') && (iscellstr(value) || isstring(value))
                    value=strjoin(cellstr(value(:)),newline);
                end
                if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
                        ~(isstring(value) && isscalar(value) && ~ismissing(value))
                    error('DataHandling:NeuroPALImage:InvalidMetadata','Worm %s must be text.',key);
                end
                worm.(key)=char(value);
            end
            sex=Annotations.Catalog.normalizeSex(worm.sex);
            if isempty(sex), sex='Unknown'; end
            worm.sex=sex;
        end
    end
    methods (Static, Access=private)
        function value = flag(value,name)
            if ~(isnumeric(value) || islogical(value)) || ~isreal(value) || ~isscalar(value) || ...
                    ~isfinite(value) || ~ismember(value,[0 1])
                error('DataHandling:NeuroPALImage:InvalidMetadata','Image prefs.%s must be true or false.',name);
            end
            value=logical(value);
        end
    end
end
