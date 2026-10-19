classdef DetectionSettings
    %DETECTIONSETTINGS Keep optional detector score overrides with the session.
    methods (Static)
        function build(c,parent)
            c.Buttons.detectionSettings=uibutton(parent,'Text',char(9881), ...
                'Tooltip','Detection settings','ButtonPushedFcn',@(~,~) Tracking.DetectionSettings.open(c));
        end
        function value = get(c)
            value=getappdata(c.Grid,'detection_settings');
            if isempty(value), value=struct('use_model_default',true,'score_threshold',.5); end
        end
        function threshold = threshold(c)
            value=Tracking.DetectionSettings.get(c); threshold=NaN;
            if strcmpi(c.Detector.Value,'MoE') && ~value.use_model_default, threshold=value.score_threshold; end
        end
        function value = validate(value)
            if isempty(value), value=struct('use_model_default',true,'score_threshold',.5); end
            if ~isstruct(value) || ~isscalar(value) || ~isfield(value,'use_model_default') || ~isfield(value,'score_threshold') || ...
                    ~isscalar(value.use_model_default) || ~ismember(value.use_model_default,[false true]) || ...
                    ~isnumeric(value.score_threshold) || ~isreal(value.score_threshold) || ~isscalar(value.score_threshold) || ...
                    ~isfinite(value.score_threshold) || value.score_threshold<0 || value.score_threshold>1
                error('Tracking:DetectionSettings','Use the model default or a score threshold from 0 to 1.');
            end
            value.use_model_default=logical(value.use_model_default);
        end
        function restore(c,value)
            value=Tracking.DetectionSettings.validate(value);
            setappdata(c.Grid,'detection_settings',value); Tracking.DetectionSettings.refresh(c);
        end
        function open(c)
            if c.Busy, return; end
            c.View.Playback.stop(); window=getappdata(c.Grid,'detection_settings_window');
            if isempty(window) || ~isvalid(window)
                window=uifigure('Name','Detection settings','Position',[300 300 350 165]);
                window.CloseRequestFcn=@(src,~) set(src,'Visible','off');
                grid=uigridlayout(window,[3 2]); grid.Padding=[14 12 14 12];
                grid.RowHeight={28,28,32}; grid.ColumnWidth={'1x',90};
                defaults=uicheckbox(grid,'Text','Use model score threshold','Value',true, ...
                    'ValueChangedFcn',@(~,~) Tracking.DetectionSettings.change(c)); defaults.Layout.Column=[1 2];
                label=uilabel(grid,'Text','MoE score threshold');
                score=uispinner(grid,'Limits',[0 1],'Step',.05,'Value',.5,'ValueDisplayFormat','%.2f', ...
                    'ValueChangedFcn',@(~,~) Tracking.DetectionSettings.change(c));
                score.Tooltip=['Lower values retain more existing expert proposals. This cannot recover a neuron ' ...
                    'absent from every expert. A custom threshold has not been validated for biological accuracy.'];
                defaults.Tooltip='Applies to MoE. Spotiflow uses its packaged settings.';
                done=uibutton(grid,'Text','Done','ButtonPushedFcn',@(~,~) set(window,'Visible','off')); done.Layout.Column=[1 2];
                controls=struct('window',window,'defaults',defaults,'score',score,'label',label);
                setappdata(c.Grid,'detection_settings_window',window); setappdata(c.Grid,'detection_settings_controls',controls);
            end
            Tracking.DetectionSettings.refresh(c); window.Visible='on'; figure(window);
        end
        function change(c)
            if c.Busy, return; end
            controls=getappdata(c.Grid,'detection_settings_controls');
            Tracking.DetectionSettings.restore(c,struct('use_model_default',controls.defaults.Value,'score_threshold',controls.score.Value));
        end
        function refresh(c)
            controls=getappdata(c.Grid,'detection_settings_controls');
            if isempty(controls) || ~isvalid(controls.window), return; end
            value=Tracking.DetectionSettings.get(c); controls.defaults.Value=value.use_model_default;
            controls.score.Value=value.score_threshold; Tracking.DetectionSettings.setBusy(c,c.Busy);
        end
        function setBusy(c,busy)
            controls=getappdata(c.Grid,'detection_settings_controls');
            if isempty(controls) || ~isvalid(controls.window), return; end
            value=Tracking.DetectionSettings.get(c); supported=strcmpi(c.Detector.Value,'MoE');
            controls.defaults.Enable=matlab.lang.OnOffSwitchState(~busy && supported);
            controls.score.Enable=matlab.lang.OnOffSwitchState(~busy && supported && ~value.use_model_default);
        end
    end
end
