classdef DisplayContrast < handle
    %DISPLAYCONTRAST Keep a separate display range for each video channel.
    properties
        View
        Panel
        Button
        Black
        White
        BlackSlider
        WhiteSlider
        Auto
        Note
        Ranges
        Bounds
        Preview
    end
    methods
        function obj = DisplayContrast(view,toolbar)
            obj.View = view; c = view.Controller;
            obj.Ranges = nan(c.Source.nc,2); obj.Bounds = obj.Ranges;
            obj.Button = uibutton(toolbar,'Text','Contrast…','ButtonPushedFcn',@(~,~) obj.toggle());
            obj.Panel = uigridlayout(c.Grid,[3 5]);
            obj.Panel.Layout.Row = 4; obj.Panel.Layout.Column = 1;
            obj.Panel.ColumnWidth = {'1x',80,'1x',80,90};
            obj.Panel.RowHeight = {24,24,18}; obj.Panel.Padding = [6 4 6 4];
            obj.Panel.RowSpacing = 2; obj.Panel.Visible = 'off';
            uilabel(obj.Panel,'Text','Black level');
            obj.Black = uieditfield(obj.Panel,'numeric','ValueChangedFcn',@(src,~) obj.setLevel(1,src.Value));
            uilabel(obj.Panel,'Text','White level');
            obj.White = uieditfield(obj.Panel,'numeric','Value',1,'ValueChangedFcn',@(src,~) obj.setLevel(2,src.Value));
            obj.Auto = uibutton(obj.Panel,'Text','Auto once','Tooltip','Set this channel’s contrast from the current volume and keep it fixed across frames.','ButtonPushedFcn',@(~,~) obj.autoOnce());
            obj.BlackSlider = uislider(obj.Panel,'Limits',[0 1000],'MajorTicks',[],'MinorTicks',[]);
            obj.BlackSlider.Layout.Row = 2; obj.BlackSlider.Layout.Column = [1 2];
            obj.WhiteSlider = uislider(obj.Panel,'Limits',[0 1000],'MajorTicks',[],'MinorTicks',[],'Value',1000);
            obj.WhiteSlider.Layout.Row = 2; obj.WhiteSlider.Layout.Column = [3 4];
            obj.Note = uilabel(obj.Panel,'Text','Display only · fixed across frames','FontSize',11);
            obj.Note.Layout.Row = 3; obj.Note.Layout.Column = [1 5];
            sliders = {obj.BlackSlider,obj.WhiteSlider}; obj.Preview = cell(1,2);
            for i=1:2
                obj.Preview{i} = Program.LatestSlicePreview(@(value) obj.slide(i,value), ...
                    @(src,~) obj.slide(i,src.Value), ...
                    @() {c.Frame.Value,c.Channel.Value,c.Busy,obj.Bounds},obj.Panel);
                sliders{i}.ValueChangingFcn = @(~,event) obj.Preview{i}.request(event.Value);
                sliders{i}.ValueChangedFcn = @(src,event) obj.Preview{i}.finish(src,event);
            end
        end
        function delete(obj)
            for i=1:numel(obj.Preview)
                if ~isempty(obj.Preview{i}) && isvalid(obj.Preview{i}), delete(obj.Preview{i}); end
            end
        end
        function toggle(obj)
            c = obj.View.Controller;
            if strcmp(obj.Panel.Visible,'on')
                obj.Panel.Visible = 'off'; c.Grid.RowHeight{4} = 0;
            else
                c.Grid.RowHeight{4} = 78; obj.Panel.Visible = 'on';
            end
        end
        function range = getRange(obj,volume)
            channel = obj.View.Controller.Channel.Value+1;
            if any(isnan(obj.Ranges(channel,:)))
                obj.Ranges(channel,:) = Tracking.DisplayContrast.autoRange(volume);
                if isinteger(volume)
                    obj.Bounds(channel,:) = [double(intmin(class(volume))),double(intmax(class(volume)))];
                elseif islogical(volume)
                    obj.Bounds(channel,:) = [0 1];
                else
                    obj.Bounds(channel,:) = obj.Ranges(channel,:);
                end
            end
            range = obj.Ranges(channel,:); obj.sync();
        end
        function sync(obj)
            channel = obj.View.Controller.Channel.Value+1;
            range = obj.Ranges(channel,:); bounds = obj.Bounds(channel,:);
            if any(isnan(range)), return; end
            obj.Black.Value = range(1); obj.White.Value = range(2);
            obj.BlackSlider.Value = max(0,min(1000,1000*(range(1)-bounds(1))/diff(bounds)));
            obj.WhiteSlider.Value = max(0,min(1000,1000*(range(2)-bounds(1))/diff(bounds)));
            obj.Note.Text = sprintf('C%d · Display only · fixed across frames',channel-1);
        end
        function slide(obj,index,value)
            channel = obj.View.Controller.Channel.Value+1; bounds = obj.Bounds(channel,:);
            obj.setLevel(index,bounds(1)+value*diff(bounds)/1000);
        end
        function setLevel(obj,index,value)
            c = obj.View.Controller;
            for i=1:2, obj.Preview{i}.cancel(); end
            if c.Busy || ~isfinite(value), obj.sync(); return; end
            channel = c.Channel.Value+1; range = obj.Ranges(channel,:);
            if (index==1 && value>=range(2)) || (index==2 && value<=range(1))
                obj.sync(); return;
            end
            range(index) = value; obj.Ranges(channel,:) = range;
            obj.Bounds(channel,:) = [min(obj.Bounds(channel,1),range(1)),max(obj.Bounds(channel,2),range(2))];
            obj.View.redraw();
        end
        function autoOnce(obj)
            c = obj.View.Controller; if c.Busy, return; end
            for i=1:2, obj.Preview{i}.cancel(); end
            channel = c.Channel.Value+1;
            range = Tracking.DisplayContrast.autoRange(c.frameData());
            obj.Ranges(channel,:) = range;
            obj.Bounds(channel,:) = [min(obj.Bounds(channel,1),range(1)),max(obj.Bounds(channel,2),range(2))];
            obj.View.redraw();
        end
        function setBusy(obj,busy)
            state = matlab.lang.OnOffSwitchState(~busy);
            handles = {obj.Black,obj.White,obj.BlackSlider,obj.WhiteSlider,obj.Auto};
            for i=1:numel(handles), handles{i}.Enable = state; end
            if busy
                for i=1:2, obj.Preview{i}.cancel(); end
            end
        end
    end
    methods (Static)
        function range = autoRange(volume)
            % Inspect the current volume once, without retaining image data.
            low = double(min(volume,[],'all','omitnan'));
            high = double(max(volume,[],'all','omitnan'));
            if isempty(low) || ~isfinite(low), low = 0; end
            if isempty(high) || ~isfinite(high), high = 1; end
            low = min(0,low);
            if high<=low, high = low+max(1,eps(low)); end
            range = [low high];
        end
        function pixels = pixels(plane,range)
            pixels = uint8((double(plane)-range(1))*(255/diff(range)));
            pixels = repmat(pixels,[1 1 3]);
        end
    end
end
