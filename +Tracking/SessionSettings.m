classdef SessionSettings
    %SESSIONSETTINGS Validate saved settings before changing a live workflow.
    methods (Static)
        function validate(c,value)
            required={'first','last','reference','tracking_channel','window_size','epochs', ...
                'tracking_directory','activity_directory','activity_current','activity_options'};
            if ~isstruct(value) || ~isscalar(value) || ~all(isfield(value,required))
                error('Tracking:SessionSettings','The saved session is missing required settings.');
            end
            for name={'first','last','reference'}
                Tracking.SessionSettings.number(value.(name{1}),1,c.Source.nt,true,name{1});
            end
            Tracking.SessionSettings.number(value.tracking_channel,0,c.Source.nc-1,true,'tracking channel');
            Tracking.SessionSettings.number(value.window_size,2,100,true,'tracking window');
            Tracking.SessionSettings.number(value.epochs,1,1000,true,'epochs');
            Tracking.SessionSettings.number(value.activity_current,0,1,true,'activity state');
            for name={'tracking_directory','activity_directory'}
                Tracking.SessionSettings.text(value.(name{1}),name{1});
            end
            if isfield(value,'next_id'), Tracking.SessionSettings.number(value.next_id,1,2^32-1,true,'next neuron ID'); end
            if isfield(value,'detector') && ~any(strcmp(value.detector,c.Detector.Items))
                error('Tracking:SessionSettings','The saved detector is unavailable.');
            end
            if isfield(value,'detection_mode') && ~any(strcmp(value.detection_mode,{'Single channel','Multi-channel','RGBW'}))
                error('Tracking:SessionSettings','The saved detection input mode is unavailable.');
            end
            if isfield(value,'detection_channel'), Tracking.SessionSettings.number(value.detection_channel,0,c.Source.nc-1,true,'detection channel'); end
            if isfield(value,'detection_settings'), Tracking.DetectionSettings.validate(value.detection_settings); end
            if isfield(value,'detection_channels'), Tracking.DetectionChannels.validate(c,value.detection_channels); end
            if isfield(value,'reference_frames') && ~isempty(value.reference_frames), Tracking.ReferenceFrames.validate(c,value.reference_frames); end
            if isfield(value,'neuron_names'), Tracking.NeuronNames.validate(value.neuron_names); end
            for name={'spacing_text','rgbw_channels'}
                if isfield(value,name{1}), Tracking.SessionSettings.text(value.(name{1}),name{1}); end
            end
            if isfield(value,'calibration_confirmed'), Tracking.SessionSettings.number(value.calibration_confirmed,0,1,true,'calibration state'); end
            if isfield(value,'image_settings')
                settings=value.image_settings;
                if ~isstruct(settings) || ~isscalar(settings) || ~isfield(settings,'channel_names') || ...
                        ~isfield(settings,'frame_interval_seconds') || numel(settings.channel_names)~=c.Source.nc
                    error('Tracking:SessionSettings','The saved image settings do not match this recording.');
                end
                names=string(settings.channel_names);
                if any(ismissing(names),'all') || any(strlength(names)>128,'all')
                    error('Tracking:SessionSettings','Invalid saved channel names.');
                end
                if ~isempty(settings.frame_interval_seconds)
                    Tracking.SessionSettings.number(settings.frame_interval_seconds,realmin,Inf,false,'frame interval');
                end
            end
            options=value.activity_options;
            if ~isstruct(options) || ~isscalar(options) || ~all(isfield(options, ...
                    {'radius_xyz','background','baseline_percentile','signal_channel','reference_channel','max_step'}))
                error('Tracking:SessionSettings','The saved activity settings are incomplete.');
            end
            if ~isnumeric(options.radius_xyz) || numel(options.radius_xyz)~=3 || any(~isfinite(options.radius_xyz(:)) | options.radius_xyz(:)<=0 | options.radius_xyz(:)>50)
                error('Tracking:SessionSettings','The saved ROI radii must contain three positive pixel values, at most 50 each.');
            end
            Tracking.SessionSettings.number(options.background,0,1,true,'background state');
            Tracking.SessionSettings.number(options.baseline_percentile,0,100,false,'baseline percentile');
            Tracking.SessionSettings.number(options.signal_channel,0,c.Source.nc-1,true,'signal channel');
            Tracking.SessionSettings.number(options.reference_channel,-1,c.Source.nc-1,true,'reference channel');
            Tracking.SessionSettings.number(options.max_step,.1,1000,false,'motion threshold');
        end
        function tracking(c,value)
            if ~isstruct(value) || ~isscalar(value) || ~all(isfield(value,{'frame_range','reference_frame','channel','window_size','epochs'})) || numel(value.frame_range)~=2
                error('Tracking:SessionSettings','Invalid tracking checkpoint settings.');
            end
            for i=1:2, Tracking.SessionSettings.number(value.frame_range(i),0,c.Source.nt-1,true,'tracking range'); end
            Tracking.SessionSettings.number(value.reference_frame,value.frame_range(1),value.frame_range(2),true,'tracking reference');
            Tracking.SessionSettings.number(value.channel,0,c.Source.nc-1,true,'tracking channel');
            Tracking.SessionSettings.number(value.window_size,2,100,true,'tracking window');
            Tracking.SessionSettings.number(value.epochs,1,1000,true,'epochs');
        end
    end
    methods (Static, Access=private)
        function number(value,low,high,whole,name)
            if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ~isreal(value) || ~isfinite(value) || value<low || value>high || (whole && value~=round(value))
                error('Tracking:SessionSettings','Invalid saved %s.',name);
            end
        end
        function text(value,name)
            if ~(ischar(value) && (isrow(value) || isempty(value))) && ~(isstring(value) && isscalar(value) && ~ismissing(value))
                error('Tracking:SessionSettings','Invalid saved %s.',name);
            end
        end
    end
end
