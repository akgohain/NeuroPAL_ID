classdef VideoPlayback < handle
    %VIDEOPLAYBACK Share one time control between the movie and activity view.
    properties
        View
        Panel
        Bar
        Controls
        RangeBar
        Compact = false
        Slider
        Play
        Previous
        Next
        Rate
        Loop
        First
        Last
        Events
        Status
        Clock
        Times = []
        Playing = false
        Worker
        Lifetime
        PreviousKey
        KeyCallback
    end
    methods
        function obj = VideoPlayback(view,parent)
            obj.View=view; c=view.Controller;
            obj.Panel=uigridlayout(parent,[4 1]); obj.Panel.Padding=[8 2 8 2];
            obj.Panel.RowHeight={30,0,42,12}; obj.Panel.RowSpacing=2;
            bar=uigridlayout(obj.Panel,[1 13]); bar.Padding=[0 0 0 0]; bar.ColumnSpacing=5;
            bar.ColumnWidth={28,64,28,42,70,52,100,55,'1x',88};
            obj.Previous=uibutton(bar,'Text','‹','Tooltip','Previous frame','ButtonPushedFcn',@(~,~) obj.step(-1));
            obj.Play=uibutton(bar,'Text','Play','ButtonPushedFcn',@(~,~) obj.toggle());
            obj.Next=uibutton(bar,'Text','›','Tooltip','Next frame','ButtonPushedFcn',@(~,~) obj.step(1));
            frame_label=uilabel(bar,'Text','Frame');
            c.Frame=uispinner(bar,'Limits',[1 max(2,c.Source.nt)],'Value',1,'Step',1);
            total_label=uilabel(bar,'Text',sprintf('/ %d',c.Source.nt));
            obj.Rate=uidropdown(bar,'Items',{'2 frames/s','5 frames/s','10 frames/s','20 frames/s'}, ...
                'ItemsData',[2 5 10 20],'Value',5,'ValueChangedFcn',@(~,~) obj.rateChanged());
            obj.Loop=uicheckbox(bar,'Text','Loop','ValueChangedFcn',@(~,~) obj.loopChanged());
            obj.First=uispinner(bar,'Limits',[1 max(2,c.Source.nt)],'Value',1,'ValueChangedFcn',@(~,~) obj.rangeChanged(1));
            to_label=uilabel(bar,'Text','to');
            obj.Last=uispinner(bar,'Limits',[1 max(2,c.Source.nt)],'Value',c.Source.nt,'ValueChangedFcn',@(~,~) obj.rangeChanged(2));
            obj.Status=uilabel(bar,'Text','','FontSize',11,'Tooltip','Achieved playback rate');
            around=uibutton(bar,'Text','Around current frame','ButtonPushedFcn',@(~,~) obj.around());
            obj.Bar=bar;
            obj.Controls={obj.Previous,obj.Play,obj.Next,frame_label,c.Frame,total_label,obj.Rate, ...
                obj.Loop,obj.First,to_label,obj.Last,obj.Status,around};
            obj.RangeBar=uigridlayout(obj.Panel,[1 6]); obj.RangeBar.Layout.Row=2;
            obj.RangeBar.Padding=[0 0 0 0]; obj.RangeBar.ColumnWidth={80,20,80,150,'1x',1};
            obj.RangeBar.Visible='off';
            indices=[9 10 11 13];
            for i=1:numel(indices)
                control=obj.Controls{indices(i)}; control.Parent=obj.RangeBar;
                control.Layout.Row=1; control.Layout.Column=i;
            end
            columns=[1 2 3 4 5 6 7 8 0 0 0 10 0];
            for i=[1:8 12], obj.Controls{i}.Layout.Row=1; obj.Controls{i}.Layout.Column=columns(i); end
            bar.RowHeight={30};
            parent.AutoResizeChildren='off'; parent.SizeChangedFcn=@(~,~) obj.resize();
            obj.Slider=uislider(obj.Panel,'Limits',[1 max(2,c.Source.nt)],'Value',1,'MinorTicks',[]);
            obj.Slider.Layout.Row=3;
            ticks=unique(round(linspace(1,c.Source.nt,min(5,c.Source.nt))));
            obj.Slider.MajorTicks=ticks; obj.Slider.MajorTickLabels=string(ticks);
            events_panel=uipanel(obj.Panel,'BorderType','none','AutoResizeChildren','off');
            events_panel.Layout.Row=4;
            obj.Events=uiaxes(events_panel); obj.Events.Toolbar.Visible='off';
            events_panel.SizeChangedFcn=@(~,~) Program.Helpers.fill_axes_parent(obj.Events);
            obj.Events.XLim=[.5 c.Source.nt+.5]; obj.Events.YLim=[0 1]; obj.Events.Visible='off';
            obj.Events.PositionConstraint='outerposition'; obj.Events.LooseInset=[0 0 0 0];
            % Leave time for navigation callbacks between movie frames.
            obj.Worker=timer('Name','NeuroPAL video playback','ExecutionMode','fixedSpacing', ...
                'Period',.2,'BusyMode','drop','TimerFcn',@(~,~) obj.tick());
            obj.Lifetime=addlistener(parent,'ObjectBeingDestroyed',@(~,~) delete(obj));
            obj.PreviousKey=c.App.CELL_ID.WindowKeyPressFcn;
            obj.KeyCallback=@(src,event) obj.key(src,event); c.App.CELL_ID.WindowKeyPressFcn=obj.KeyCallback;
        end
        function resize(obj)
            obj.Compact=obj.Panel.Parent.Position(3)<850;
            expanded=logical(obj.Loop.Value);
            height=double(expanded)*32;
            if obj.Panel.RowHeight{2}~=height
                obj.Panel.RowHeight{2}=height;
                obj.View.Body.RowHeight{3}=100+height;
            end
            obj.RangeBar.Visible=matlab.lang.OnOffSwitchState(expanded);
        end
        function loopChanged(obj)
            obj.stop(); obj.resize();
        end
        function connect(obj)
            obj.Slider.ValueChangingFcn=@(~,event) obj.request(event.Value);
            obj.Slider.ValueChangedFcn=@(src,event) obj.finish(src,event);
        end
        function finish(obj,src,event)
            value=src.Value;
            if (isstruct(event) && isfield(event,'Value')) || (isobject(event) && isprop(event,'Value')), value=event.Value; end
            % Keep the release position even if stopping a preview updates the slider.
            obj.View.FramePreview.cancel(); obj.View.navigate(value);
        end
        function request(obj,value)
            obj.stop(); obj.View.FramePreview.request(value);
        end
        function step(obj,delta)
            obj.View.navigate(obj.View.Controller.Frame.Value+delta);
        end
        function toggle(obj)
            c=obj.View.Controller;
            if obj.Playing, obj.stop(); return; end
            if c.Busy || c.Source.nt<2, return; end
            obj.View.Preview.cancel(); obj.View.FramePreview.cancel();
            if obj.Loop.Value && (c.Frame.Value<obj.First.Value || c.Frame.Value>=obj.Last.Value)
                obj.View.navigate(obj.First.Value);
            elseif c.Frame.Value>=c.Source.nt
                obj.View.navigate(1);
            end
            obj.Playing=true; obj.Play.Text='Pause'; obj.Clock=tic; obj.Times=[]; start(obj.Worker);
        end
        function stop(obj)
            obj.Playing=false;
            if ~isempty(obj.Worker) && isvalid(obj.Worker), stop(obj.Worker); end
            if ~isempty(obj.Play) && isvalid(obj.Play), obj.Play.Text='Play'; end
            if ~isempty(obj.Status) && isvalid(obj.Status), obj.Status.Text=''; end
        end
        function tick(obj)
            c=obj.View.Controller;
            if ~obj.Playing || c.Busy || ~isvalid(c.App) || c.App.TabGroup.SelectedTab~=c.App.VideoTrackingTab
                obj.stop(); return;
            end
            last=c.Source.nt; if obj.Loop.Value, last=obj.Last.Value; end
            frame=c.Frame.Value+1;
            if frame>last
                if obj.Loop.Value, frame=obj.First.Value;
                else, obj.stop(); return; end
            end
            try
                obj.View.navigate(frame,true); drawnow nocallbacks;
                obj.Times(end+1)=toc(obj.Clock);
                if numel(obj.Times)>21, obj.Times(1)=[]; end
                if numel(obj.Times)>1, obj.Status.Text=sprintf('%.1f fps',1/mean(diff(obj.Times))); end
            catch ME
                obj.stop(); c.Status.Text=ME.message;
            end
        end
        function rateChanged(obj)
            playing=obj.Playing; obj.stop(); obj.Worker.Period=1/obj.Rate.Value;
            if playing, obj.toggle(); end
        end
        function rangeChanged(obj,index)
            obj.stop(); n=obj.View.Controller.Source.nt;
            obj.First.Value=min(n,round(obj.First.Value)); obj.Last.Value=min(n,round(obj.Last.Value));
            if index==1, obj.First.Value=min(obj.First.Value,obj.Last.Value);
            else, obj.Last.Value=max(obj.First.Value,obj.Last.Value); end
        end
        function around(obj)
            obj.stop(); c=obj.View.Controller;
            obj.First.Value=max(1,c.Frame.Value-20); obj.Last.Value=min(c.Source.nt,c.Frame.Value+20); obj.Loop.Value=true; obj.resize();
        end
        function sync(obj)
            obj.Slider.Value=obj.View.Controller.Frame.Value; obj.resize();
        end
        function setBusy(obj,busy)
            if busy, obj.stop(); end
            enabled=matlab.lang.OnOffSwitchState(~busy && obj.View.Controller.Source.nt>1);
            handles={obj.Slider,obj.Play,obj.Previous,obj.Next,obj.Rate,obj.Loop,obj.First,obj.Last};
            for i=1:numel(handles), handles{i}.Enable=enabled; end
        end
        function key(obj,src,event)
            c=obj.View.Controller;
            if c.App.TabGroup.SelectedTab~=c.App.VideoTrackingTab
                if isa(obj.PreviousKey,'function_handle'), obj.PreviousKey(src,event);
                elseif iscell(obj.PreviousKey), feval(obj.PreviousKey{1},src,event,obj.PreviousKey{2:end}); end
                return;
            end
            focused=src.CurrentObject;
            if isa(focused,'matlab.ui.control.EditField') || isa(focused,'matlab.ui.control.NumericEditField') || ...
                    isa(focused,'matlab.ui.control.Spinner') || isa(focused,'matlab.ui.control.DropDown') || ...
                    isa(focused,'matlab.ui.control.TextArea') || isa(focused,'matlab.ui.control.Button')
                return;
            end
            if any(ismember(event.Modifier,{'control','command','alt'})), return; end
            step=1; if any(strcmp(event.Modifier,'shift')), step=10; end
            switch event.Key
                case 'space', obj.toggle();
                case 'leftarrow', obj.step(-step);
                case 'rightarrow', obj.step(step);
                case 'home', obj.View.navigate(1);
                case 'end', obj.View.navigate(c.Source.nt);
            end
        end
        function delete(obj)
            obj.stop();
            if ~isempty(obj.Worker) && isvalid(obj.Worker), delete(obj.Worker); end
            if ~isempty(obj.Lifetime) && isvalid(obj.Lifetime), delete(obj.Lifetime); end
            c=obj.View.Controller;
            if isvalid(c) && isvalid(c.App) && isvalid(c.App.CELL_ID) && isequal(c.App.CELL_ID.WindowKeyPressFcn,obj.KeyCallback)
                c.App.CELL_ID.WindowKeyPressFcn=obj.PreviousKey;
            end
        end
    end
end
