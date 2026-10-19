classdef DetectionChannels
    %DETECTIONCHANNELS Select arbitrary source channels for independent detection.
    methods (Static)
        function build(c,parent)
            panel=uigridlayout(parent,[2 2]); panel.Layout.Row=4; panel.Layout.Column=2;
            panel.Padding=[0 0 0 0]; panel.RowHeight={'1x',28}; panel.ColumnWidth={'1x',65}; panel.Visible='off';
            enabled=false(c.Source.nc,1); enabled(1:min(2,c.Source.nc))=true;
            table=uitable(panel,'Data',[num2cell(enabled) cellstr("C"+string((0:c.Source.nc-1)'))], ...
                'ColumnName',{'Use','Channel'},'ColumnEditable',[true false],'ColumnWidth',{40,'auto'},'RowName',{});
            table.Layout.Column=[1 2];
            uilabel(panel,'Text','Merge (µm)');
            radius=uieditfield(panel,'numeric','Limits',[0 Inf],'Value',2, ...
                'Tooltip','Merge cross-channel centers within this physical distance. Keeps the strongest center; never merges two detections from the same channel.');
            setappdata(c.Grid,'detection_channels',struct('panel',panel,'table',table,'radius',radius));
        end
        function value = get(c)
            controls=getappdata(c.Grid,'detection_channels');
            value=struct('channels',find(cell2mat(controls.table.Data(:,1)))'-1,'merge_radius_um',controls.radius.Value);
        end
        function validate(c,value)
            if ~isstruct(value) || ~isscalar(value) || ~isfield(value,'channels') || ~isfield(value,'merge_radius_um') || ~isnumeric(value.channels) || ~isreal(value.channels)
                error('Tracking:Channels','Invalid saved detection channel settings.');
            end
            indices=double(value.channels(:)');
            if any(~isfinite(indices) | indices<0 | indices>=c.Source.nc | indices~=round(indices)) || numel(unique(indices))~=numel(indices)
                error('Tracking:Channels','Saved detection channels are outside this recording.');
            end
            if ~isnumeric(value.merge_radius_um) || ~isreal(value.merge_radius_um) || ~isscalar(value.merge_radius_um) || ~isfinite(value.merge_radius_um) || value.merge_radius_um<0
                error('Tracking:Channels','Invalid saved merge distance.');
            end
        end
        function restore(c,value)
            Tracking.DetectionChannels.validate(c,value);
            controls=getappdata(c.Grid,'detection_channels'); indices=double(value.channels(:)');
            controls.table.Data(:,1)=num2cell(ismember((0:c.Source.nc-1)',indices)); controls.radius.Value=value.merge_radius_um;
        end
        function labels(c,names)
            controls=getappdata(c.Grid,'detection_channels');
            if ~isempty(controls), controls.table.Data(:,2)=names(:); end
        end
        function mode(c)
            controls=getappdata(c.Grid,'detection_channels'); multi=strcmp(c.DetectionMode.Value,'Multi-channel');
            legacy=strcmp(c.DetectionMode.Value,'RGBW');
            controls.panel.Visible=matlab.lang.OnOffSwitchState(multi);
            c.DetectionChannel.Visible=matlab.lang.OnOffSwitchState(~multi && ~legacy); c.RGBW.Visible=matlab.lang.OnOffSwitchState(legacy);
            if multi, c.DetectionChannel.Parent.RowHeight{4}=150; else, c.DetectionChannel.Parent.RowHeight{4}=28; end
        end
        function setBusy(c,busy)
            controls=getappdata(c.Grid,'detection_channels');
            state='on'; if busy, state='off'; end
            controls.table.Enable=state; controls.radius.Enable=state;
        end
    end
end
