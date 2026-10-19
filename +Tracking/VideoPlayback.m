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
        Status
        Clock
        Times = []
        Playing = false
        Worker
        Lifetime
        Window
        Parent
        PreviousResize
        ResizeCallback
        Disposing = false
        PreviousKey
        KeyCallback
    end
    methods
        function obj = VideoPlayback(view,parent)
            obj.View=view; c=view.Controller;
            obj.Window=c.App.CELL_ID; obj.Parent=parent;
            obj.Panel=uigridlayout(parent,[3 1]); obj.Panel.Padding=[8 2 8 2];
            obj.Panel.RowHeight={30,0,42}; obj.Panel.RowSpacing=2;
            bar=uigridlayout(obj.Panel,[1 13]); bar.Padding=[0 0 0 0]; bar.ColumnSpacing=5;
            bar.ColumnWidth={0,64,0,42,70,52,85,30,55,0,'1x'};
            obj.Previous=uibutton(bar,'Text','‹','Visible','off','Tooltip','Previous frame','ButtonPushedFcn',@(~,~) obj.step(-1));
            obj.Play=uibutton(bar,'Text','Play','ButtonPushedFcn',@(~,~) obj.toggle());
            obj.Next=uibutton(bar,'Text','›','Visible','off','Tooltip','Next frame','ButtonPushedFcn',@(~,~) obj.step(1));
            frame_label=uilabel(bar,'Text','Frame','HorizontalAlignment','right');
            c.Frame=uispinner(bar,'Limits',[1 max(2,c.Source.nt)],'Value',1,'Step',1);
            total_label=uilabel(bar,'Text',sprintf('/ %d',c.Source.nt));
            obj.Rate=uidropdown(bar,'Items',{'1','2','5','10','15','20', ...
                '30','60','90','120','144','240'},'Editable','on','Value','5','UserData',5, ...
                'Tooltip','Choose a preset or type a rate (0.1–240 FPS). Playback follows this rate; display frames are skipped if rendering falls behind.', ...
                'ValueChangedFcn',@(~,~) obj.rateChanged());
            rate_label=uilabel(bar,'Text','FPS');
            rate_label.Layout.Row=1; rate_label.Layout.Column=8;
            obj.Loop=uicheckbox(bar,'Text','Loop','ValueChangedFcn',@(~,~) obj.loopChanged());
            obj.First=uispinner(bar,'Limits',[1 max(2,c.Source.nt)],'Value',1,'ValueChangedFcn',@(~,~) obj.rangeChanged(1));
            to_label=uilabel(bar,'Text','to');
            obj.Last=uispinner(bar,'Limits',[1 max(2,c.Source.nt)],'Value',c.Source.nt,'ValueChangedFcn',@(~,~) obj.rangeChanged(2));
            obj.Status=uilabel(bar,'Text','','FontSize',11,'HorizontalAlignment','right','Tooltip','Displayed frames per second. Playback skips display frames when needed to keep the requested speed.');
            around=uibutton(bar,'Text','Around current frame','Tooltip','Set the loop to 20 frames before and after the current frame.','ButtonPushedFcn',@(~,~) obj.around());
            obj.Bar=bar;
            obj.Controls={obj.Previous,obj.Play,obj.Next,frame_label,c.Frame,total_label,obj.Rate, ...
                obj.Loop,obj.First,to_label,obj.Last,obj.Status,around};
            obj.RangeBar=uigridlayout(bar,[1 4]); obj.RangeBar.Layout.Row=1; obj.RangeBar.Layout.Column=10;
            obj.RangeBar.Padding=[0 0 0 0]; obj.RangeBar.ColumnSpacing=5; obj.RangeBar.ColumnWidth={80,20,80,150};
            obj.RangeBar.Visible='off';
            indices=[9 10 11 13];
            for i=1:numel(indices)
                control=obj.Controls{indices(i)}; control.Parent=obj.RangeBar;
                control.Layout.Row=1; control.Layout.Column=i;
            end
            columns=[1 2 3 4 5 6 7 9 0 0 0 11 0];
            for i=[1:8 12], obj.Controls{i}.Layout.Row=1; obj.Controls{i}.Layout.Column=columns(i); end
            bar.RowHeight={30};
            obj.PreviousResize=parent.SizeChangedFcn;
            obj.ResizeCallback=@(~,~) Tracking.VideoPlayback.resizeIfAlive(obj);
            parent.AutoResizeChildren='off'; parent.SizeChangedFcn=obj.ResizeCallback;
            obj.Slider=uislider(obj.Panel,'Limits',[1 max(2,c.Source.nt)],'Value',1,'MinorTicks',[]);
            obj.Slider.Layout.Row=3;
            ticks=unique(round(linspace(1,c.Source.nt,min(5,c.Source.nt))));
            obj.Slider.MajorTicks=ticks; obj.Slider.MajorTickLabels=string(ticks);
            % Leave time for navigation callbacks between movie frames.
            obj.Worker=timer('Name','NeuroPAL video playback','ExecutionMode','fixedSpacing', ...
                'Period',.01,'BusyMode','drop','TimerFcn',@(~,~) Tracking.VideoPlayback.tickIfAlive(obj));
            obj.Lifetime=addlistener(parent,'ObjectBeingDestroyed',@(~,~) Tracking.VideoPlayback.deleteIfAlive(obj));
            obj.PreviousKey=obj.Window.WindowKeyPressFcn;
            previous=obj.PreviousKey;
            obj.KeyCallback=@(src,event) Tracking.VideoPlayback.dispatchKey(obj,previous,src,event);
            obj.Window.WindowKeyPressFcn=obj.KeyCallback;
        end
        function resize(obj)
            width=obj.Panel.Parent.Position(3); obj.Compact=width<1000;
            expanded=logical(obj.Loop.Value);
            % Reveal loop bounds inline without moving the image or timeline.
            if obj.Compact
                columns={0,60,0,38,65,48,72,28,52,0,'1x'};
                ranges={65,16,65,95}; label='Around here';
            else
                columns={0,64,0,42,70,52,85,30,55,0,'1x'};
                ranges={80,20,80,150}; label='Around current frame';
            end
            if expanded, columns{10}=sum([ranges{:}])+15; end
            if ~isequal(obj.Bar.ColumnWidth,columns), obj.Bar.ColumnWidth=columns; end
            if ~isequal(obj.RangeBar.ColumnWidth,ranges), obj.RangeBar.ColumnWidth=ranges; end
            obj.Controls{13}.Text=label;
            obj.RangeBar.Visible=matlab.lang.OnOffSwitchState(expanded);
            obj.Status.Visible=matlab.lang.OnOffSwitchState(~expanded || width>=950);
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
            obj.Worker.UserData=c.Frame.Value;
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
            if obj.View.Rendering, return; end
            clock=obj.Clock; last=c.Source.nt; if obj.Loop.Value, last=obj.Last.Value; end
            % Follow elapsed time rather than accumulating frame render delays.
            frame=obj.Worker.UserData+floor(toc(clock)*obj.Rate.UserData);
            finished=~obj.Loop.Value && frame>=last;
            if obj.Loop.Value
                frame=obj.First.Value+mod(frame-obj.First.Value,last-obj.First.Value+1);
            else
                frame=min(frame,last);
            end
            if frame==c.Frame.Value
                if finished, obj.stop(); end
                return;
            end
            try
                obj.View.navigate(frame,true); drawnow nocallbacks;
                if ~obj.Playing || obj.Clock~=clock, return; end
                obj.Times(end+1)=toc(clock);
                if numel(obj.Times)>21, obj.Times(1)=[]; end
                if numel(obj.Times)>1, obj.Status.Text=sprintf('Display: %.1f fps',1/mean(diff(obj.Times))); end
                if finished, obj.stop(); end
            catch ME
                obj.stop(); c.Status.Text=ME.message;
            end
        end
        function rateChanged(obj)
            rate=str2double(strtrim(obj.Rate.Value));
            if ~isfinite(rate) || rate<.1 || rate>240
                obj.Rate.Value=sprintf('%g',obj.Rate.UserData); return;
            end
            obj.Rate.UserData=rate; obj.Rate.Value=sprintf('%g',rate);
            playing=obj.Playing; obj.stop(); obj.Worker.Period=.01;
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
            c=obj.liveController();
            if isempty(c) || c.App.TabGroup.SelectedTab~=c.App.VideoTrackingTab
                Tracking.VideoPlayback.invokeKey(obj.PreviousKey,src,event);
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
            if obj.Disposing, return; end
            obj.Disposing=true;
            % The view/controller may already be invalid while construction unwinds.
            if ~isempty(obj.Window) && isvalid(obj.Window) && strcmp(obj.Window.BeingDeleted,'off') && ...
                    isequal(obj.Window.WindowKeyPressFcn,obj.KeyCallback)
                obj.Window.WindowKeyPressFcn=obj.PreviousKey;
            end
            if ~isempty(obj.Parent) && isvalid(obj.Parent) && strcmp(obj.Parent.BeingDeleted,'off') && ...
                    isequal(obj.Parent.SizeChangedFcn,obj.ResizeCallback)
                obj.Parent.SizeChangedFcn=obj.PreviousResize;
            end
            obj.stop();
            if ~isempty(obj.Worker) && isvalid(obj.Worker), delete(obj.Worker); end
            if ~isempty(obj.Lifetime) && isvalid(obj.Lifetime), delete(obj.Lifetime); end
            if ~isempty(obj.Panel) && isvalid(obj.Panel), delete(obj.Panel); end
        end
    end
    methods (Access=private)
        function c=liveController(obj)
            c=[];
            try
                view=obj.View;
                if isempty(view) || (isa(view,'handle') && ~isvalid(view)), return; end
                candidate=view.Controller;
                if isempty(candidate) || (isa(candidate,'handle') && ~isvalid(candidate)), return; end
                app=candidate.App;
                if isempty(app) || (isa(app,'handle') && ~isvalid(app)), return; end
                if isempty(app.CELL_ID) || ~isvalid(app.CELL_ID), return; end
                c=candidate;
            catch
                % A partially constructed view has no live keyboard owner.
            end
        end
    end
    methods (Static)
        function dispatchKey(obj,previous,src,event)
            if ~isempty(obj) && isvalid(obj) && ~obj.Disposing
                obj.key(src,event);
            else
                % A newer dispatcher may still retain this callback in its chain.
                Tracking.VideoPlayback.invokeKey(previous,src,event);
            end
        end
        function invokeKey(callback,src,event)
            if isa(callback,'function_handle'), callback(src,event);
            elseif iscell(callback), feval(callback{1},src,event,callback{2:end});
            elseif ischar(callback), evalin('base',callback); end
        end
        function resizeIfAlive(obj)
            if ~isempty(obj) && isvalid(obj) && ~obj.Disposing && ...
                    ~isempty(obj.Panel) && isvalid(obj.Panel) && isvalid(obj.Panel.Parent) && ...
                    strcmp(obj.Panel.Parent.BeingDeleted,'off')
                obj.resize();
            end
        end
        function tickIfAlive(obj)
            if isempty(obj) || ~isvalid(obj) || obj.Disposing, return; end
            if isempty(obj.liveController()), obj.stop(); else, obj.tick(); end
        end
        function deleteIfAlive(obj)
            if ~isempty(obj) && isvalid(obj) && ~obj.Disposing, delete(obj); end
        end
    end
end
