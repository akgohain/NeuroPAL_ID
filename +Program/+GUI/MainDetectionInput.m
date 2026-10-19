classdef MainDetectionInput
    %MAINDETECTIONINPUT Select detector channels separately from display toggles.
    methods (Static)
        function build(app,parent)
            grid=uigridlayout(parent,[1 7]); grid.Layout.Row=2; grid.Layout.Column=1;
            grid.Padding=[0 0 0 0]; grid.ColumnWidth={75,135,130,150,110,80,'1x'};
            uilabel(grid,'Text','MoE input');
            mode=uidropdown(grid,'Items',{'RGBW','Single channel','Multi-channel'}, ...
                'Tooltip','RGBW uses the four mapped channels. Display checkboxes do not select detector inputs.');
            channels_label=uilabel(grid,'Text','Channels (1-based)');
            channels=uieditfield(grid,'text','Value','1','Tooltip','Enter source channel numbers separated by spaces.');
            merge_label=uilabel(grid,'Text','Merge radius (µm)');
            merge=uispinner(grid,'Limits',[0 100],'Value',2,'Tooltip','Merge detections from different channels within this physical distance.');
            uilabel(grid,'Text','');
            controls=struct('mode',mode,'channels',channels,'source','','merge',merge,'merge_label',merge_label,'channels_label',channels_label);
            setappdata(app.CELL_ID,'main_detection_input',controls);
            mode.ValueChangedFcn=@(~,~) Program.GUI.MainDetectionInput.refresh(app);
            Program.GUI.MainDetectionInput.refresh(app);
        end
        function refresh(app)
            controls=getappdata(app.CELL_ID,'main_detection_input');
            if isempty(controls), return; end
            if ~strcmp(controls.source,app.image_file)
                controls.source=app.image_file; controls.channels.Value='1'; controls.mode.Value='RGBW';
                controls.channels.Enable='off'; setappdata(app.CELL_ID,'main_detection_input',controls);
            end
            backend=Program.GUIPreferences.get_detection_backend();
            enabled=strcmp(backend,'detection_moe') && ~isempty(app.image_data);
            controls.mode.Enable=matlab.lang.OnOffSwitchState(enabled);
            controls.channels.Enable=matlab.lang.OnOffSwitchState(enabled && ~strcmp(controls.mode.Value,'RGBW'));
            controls.channels.Visible=matlab.lang.OnOffSwitchState(~strcmp(controls.mode.Value,'RGBW'));
            controls.channels_label.Visible=controls.channels.Visible;
            multi=enabled && strcmp(controls.mode.Value,'Multi-channel');
            controls.merge.Visible=matlab.lang.OnOffSwitchState(multi); controls.merge_label.Visible=controls.merge.Visible;
            controls.merge.Enable=matlab.lang.OnOffSwitchState(multi);
        end
        function [mode,channels,radius] = get(app)
            radius=2; mode='rgbw'; channels=double(app.image_prefs.RGBW(:)');
            controls=getappdata(app.CELL_ID,'main_detection_input');
            if ~isempty(controls)
                radius=controls.merge.Value;
                if strcmp(controls.mode.Value,'Single channel'), mode='single_channel';
                elseif strcmp(controls.mode.Value,'Multi-channel'), mode='multi_channel'; end
                if ~strcmp(mode,'rgbw')
                    channels=str2double(split(strtrim(string(controls.channels.Value))))';
                end
            end
            if isempty(channels) || any(~isfinite(channels) | channels~=round(channels) | channels<1 | channels>size(app.image_data,4)) || numel(unique(channels))~=numel(channels)
                error('Methods:DetectionChannels','Enter distinct source channel numbers within this image.');
            end
            if strcmp(mode,'rgbw') && numel(channels)~=4
                error('Methods:DetectionChannels','Assign four distinct RGBW channels in the image settings.');
            elseif strcmp(mode,'single_channel') && numel(channels)~=1
                error('Methods:DetectionChannels','Select one channel for Single channel input.');
            elseif strcmp(mode,'multi_channel') && numel(channels)<2
                error('Methods:DetectionChannels','Select at least two channels for Multi-channel input.');
            end
        end
    end
end
