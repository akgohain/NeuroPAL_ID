classdef ImageSettings
    %IMAGESETTINGS Describe the recording without changing its pixel data.
    methods (Static)
        function value = get(c)
            value=getappdata(c.Grid,'image_metadata');
            if isempty(value)
                value=struct('channel_names',{repmat({''},1,c.Source.nc)},'frame_interval_seconds',[]);
                if isfield(c.Source,'frame_interval_seconds'), value.frame_interval_seconds=c.Source.frame_interval_seconds; end
            end
            if ~isfield(value,'spatial_units'), value.spatial_units='Pixels'; end
        end
        function build(c)
            window=getappdata(c.Grid,'image_settings_window');
            spacing=c.Spacing.Value; confirmed=c.Calibration.Value; label=c.Calibration.Text;
            delete(window.Children); window.Position(3:4)=[430 470];
            grid=uigridlayout(window,[10 2]); grid.Padding=[14 12 14 12]; grid.ColumnWidth={145,'1x'};
            grid.RowHeight={24,28,28,28,28,24,'1x',28,0,28}; grid.RowSpacing=6;
            heading=uilabel(grid,'Text','Spatial calibration','FontWeight','bold'); heading.Layout.Column=[1 2];
            uilabel(grid,'Text','X Y Z (µm)');
            c.Spacing=uieditfield(grid,'text','Value',spacing,'ValueChangedFcn',@(~,~) c.spacingChanged());
            c.Calibration=uicheckbox(grid,'Text',label,'Value',confirmed,'ValueChangedFcn',@(~,~) Tracking.ImageUnits.refresh(c)); c.Calibration.Layout.Column=[1 2];
            uilabel(grid,'Text','Acquisition timing');
            mode=uidropdown(grid,'Items',{'Interval (s/frame)','Rate (Hz)'},'ValueChangedFcn',@(~,~) Tracking.ImageSettings.syncTime(c));
            uilabel(grid,'Text','Value (blank = unknown)');
            time=uieditfield(grid,'text','Placeholder','Unknown','ValueChangedFcn',@(~,~) Tracking.ImageSettings.changeTime(c));
            heading=uilabel(grid,'Text','Channel names','FontWeight','bold'); heading.Layout.Column=[1 2];
            value=Tracking.ImageSettings.get(c);
            table=uitable(grid,'Data',[cellstr("C"+string((0:c.Source.nc-1)')) value.channel_names(:)], ...
                'ColumnName',{'Channel','Name'},'ColumnEditable',[false true],'ColumnWidth',{75,'auto'},'RowName',{}, ...
                'CellEditCallback',@(src,~) Tracking.ImageSettings.changeNames(c,src)); table.Layout.Column=[1 2];
            detail=uibutton(grid,'Text','File details ▸','ButtonPushedFcn',@(src,~) Tracking.ImageSettings.details(src)); detail.Layout.Column=[1 2];
            dtype='Unknown'; if isfield(c.Source,'dtype'), dtype=char(c.Source.dtype); end
            info=uitextarea(grid,'Editable','off','Value',{c.Source.file,sprintf('%d frames × %d channels × %d Z × %d Y × %d X', ...
                c.Source.nt,c.Source.nc,c.Source.nz,c.Source.ny,c.Source.nx),['Data type: ' dtype]});
            info.Layout.Column=[1 2]; info.Layout.Row=9; info.Visible='off'; detail.UserData=info;
            done=uibutton(grid,'Text','Done','ButtonPushedFcn',@(~,~) set(window,'Visible','off')); done.Layout.Row=10; done.Layout.Column=[1 2];
            setappdata(c.Grid,'image_metadata_controls',struct('mode',mode,'time',time,'names',table));
            Tracking.ImageSettings.syncTime(c);
        end
        function details(button)
            info=button.UserData; opened=strcmp(info.Visible,'off');
            info.Visible=matlab.lang.OnOffSwitchState(opened); info.Parent.RowHeight{9}=100*double(opened);
            window=info.Parent.Parent; window.Position(4)=470+100*double(opened);
            if opened, button.Text='File details ▾'; else, button.Text='File details ▸'; end
        end
        function syncTime(c)
            controls=getappdata(c.Grid,'image_metadata_controls'); value=Tracking.ImageSettings.get(c);
            interval=value.frame_interval_seconds;
            if isempty(interval), controls.time.Value=''; return; end
            if strcmp(controls.mode.Value,'Rate (Hz)'), interval=1/interval; end
            controls.time.Value=sprintf('%.10g',interval);
        end
        function changeTime(c)
            controls=getappdata(c.Grid,'image_metadata_controls'); value=Tracking.ImageSettings.get(c);
            input=strtrim(controls.time.Value); number=str2double(input);
            if isempty(input), value.frame_interval_seconds=[];
            elseif ~isfinite(number) || number<=0
                Tracking.ImageSettings.syncTime(c);
                uialert(getappdata(c.Grid,'image_settings_window'),'Enter a positive acquisition interval or rate. Leave blank if unknown.','Acquisition timing'); return;
            elseif strcmp(controls.mode.Value,'Rate (Hz)')
                interval=1/number;
                if ~isfinite(interval) || interval<=0
                    Tracking.ImageSettings.syncTime(c);
                    uialert(getappdata(c.Grid,'image_settings_window'),'This rate is outside the supported numeric range.','Acquisition timing'); return;
                end
                value.frame_interval_seconds=interval;
            else, value.frame_interval_seconds=number;
            end
            setappdata(c.Grid,'image_metadata',value); Tracking.ImageSettings.axis(c);
        end
        function changeNames(c,table)
            value=Tracking.ImageSettings.get(c); value.channel_names=cellfun(@(x) strtrim(char(string(x))),table.Data(:,2),'UniformOutput',false)';
            setappdata(c.Grid,'image_metadata',value); Tracking.ImageSettings.labels(c);
        end
        function labels(c)
            value=Tracking.ImageSettings.get(c); names=cellstr("C"+string(0:c.Source.nc-1));
            for i=1:c.Source.nc
                if ~isempty(value.channel_names{i}), names{i}=[names{i} ' · ' value.channel_names{i}]; end
            end
            Tracking.DetectionChannels.labels(c,names);
            handles={c.Channel,c.DetectionChannel,c.TrackingChannel,c.Analysis.Controls.signal};
            for i=1:numel(handles), selected=handles{i}.Value; handles{i}.Items=names; handles{i}.Value=selected; end
            selected=c.Analysis.Controls.reference.Value;
            c.Analysis.Controls.reference.Items=[{'None'} names]; c.Analysis.Controls.reference.Value=selected;
        end
        function axis(c)
            value=Tracking.ImageSettings.get(c); ax=c.Analysis.Axes;
            if isempty(value.frame_interval_seconds) || isempty(c.Analysis.Frames)
                ax.XTickLabelMode='auto'; xlabel(ax,'Frame');
            else
                ax.XTickLabel=compose('%.4g',(ax.XTick-1)*value.frame_interval_seconds); xlabel(ax,'Time (s from first frame)');
            end
        end
        function restore(c,value)
            if ~isfield(value,'channel_names') || numel(value.channel_names)~=c.Source.nc, return; end
            interval=value.frame_interval_seconds;
            if ~isempty(interval) && (~isscalar(interval) || ~isfinite(interval) || interval<=0), value.frame_interval_seconds=[]; end
            value.channel_names=cellstr(string(value.channel_names));
            if ~isfield(value,'spatial_units') || ~any(strcmp(value.spatial_units,{'Pixels','µm'})), value.spatial_units='Pixels'; end
            setappdata(c.Grid,'image_metadata',value); Tracking.ImageSettings.labels(c);
            controls=getappdata(c.Grid,'image_metadata_controls');
            if ~isempty(controls)
                controls.names.Data=[cellstr("C"+string((0:c.Source.nc-1)')) value.channel_names(:)]; Tracking.ImageSettings.syncTime(c);
            end
            Tracking.ImageUnits.refresh(c);
        end
    end
end
