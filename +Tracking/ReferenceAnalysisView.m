classdef ReferenceAnalysisView < handle
    %REFERENCEANALYSISVIEW Review tracking runs and fluorescence measurements.
    properties
        Controller
        Tabs
        ActivityTab
        Axes
        Mode
        Controls = struct()
        ResultKey = ''
        Frames = []
        IDs = []
        PlotKey = {}
        Coverage
        Colorbar = []
        ResultOptions = struct()
    end
    methods
        function obj = ReferenceAnalysisView(c,tabs,lower_tabs)
            obj.Controller=c; obj.Tabs=lower_tabs;
            tracking=uitab(tabs,'Title','Tracking');
            grid=uigridlayout(tracking,[10 2]); grid.RowHeight={28,28,28,28,28,28,28,28,28,55};
            uilabel(grid,'Text','First frame'); c.First=uispinner(grid,'Limits',[1 max(2,c.Source.nt)],'Value',1);
            uilabel(grid,'Text','Last frame'); c.Last=uispinner(grid,'Limits',[1 max(2,c.Source.nt)],'Value',c.Source.nt);
            uilabel(grid,'Text','Reference frame'); c.Reference=uispinner(grid,'Limits',[1 max(2,c.Source.nt)],'Value',1);
            items=cellstr("C"+string(0:c.Source.nc-1));
            uilabel(grid,'Text','Tracking channel'); c.TrackingChannel=uidropdown(grid,'Items',items,'ItemsData',0:c.Source.nc-1,'Value',0);
            uilabel(grid,'Text','Frames per window'); c.WindowSize=uispinner(grid,'Limits',[2 100],'Value',50);
            uilabel(grid,'Text','Epochs per frame'); c.Epochs=uispinner(grid,'Limits',[1 1000],'Value',40);
            c.Buttons.track=uibutton(grid,'Text','Run ZephIR','ButtonPushedFcn',@(~,~) c.safe(@() c.track())); c.Buttons.track.Layout.Column=[1 2];
            c.Buttons.resume=uibutton(grid,'Text','Resume tracking','ButtonPushedFcn',@(~,~) c.safe(@() c.track(true)));
            c.Buttons.progress=uibutton(grid,'Text','Load progress','ButtonPushedFcn',@(~,~) c.safe(@() c.loadProgress()));
            c.Buttons.openrun=uibutton(grid,'Text','Open tracking run…','ButtonPushedFcn',@(~,~) c.safe(@() c.openTracking())); c.Buttons.openrun.Layout.Column=[1 2];
            note=uilabel(grid,'Text','Completed windows are saved. Cancel and resume without restarting the recording.','WordWrap','on'); note.Layout.Column=[1 2];

            activity=uitab(tabs,'Title','Activity');
            grid=uigridlayout(activity,[10 2]); grid.RowHeight={28,28,28,28,28,28,28,28,60,50};
            uilabel(grid,'Text','Signal channel'); obj.Controls.signal=uidropdown(grid,'Items',items,'ItemsData',0:c.Source.nc-1,'Value',0);
            uilabel(grid,'Text','Reference channel'); obj.Controls.reference=uidropdown(grid,'Items',[{'None'};items(:)],'ItemsData',[-1 0:c.Source.nc-1],'Value',-1);
            uilabel(grid,'Text','ROI radii X Y Z (px)'); obj.Controls.radius=uieditfield(grid,'text','Value','3 3 1');
            obj.Controls.background=uicheckbox(grid,'Text','Subtract local background','Value',true); obj.Controls.background.Layout.Column=[1 2];
            uilabel(grid,'Text','Baseline percentile'); obj.Controls.baseline=uispinner(grid,'Limits',[0 100],'Value',20);
            uilabel(grid,'Text','Motion warning (px)'); obj.Controls.motion=uispinner(grid,'Limits',[.1 1000],'Value',10);
            c.Buttons.activity=uibutton(grid,'Text','Extract activity','ButtonPushedFcn',@(~,~) c.safe(@() c.extractActivity())); c.Buttons.activity.Layout.Column=[1 2];
            c.Buttons.export=uibutton(grid,'Text','Export activity + tracks…','ButtonPushedFcn',@(~,~) c.safe(@() c.exportActivity())); c.Buttons.export.Layout.Column=[1 2];
            note=uilabel(grid,'Text','Uses the Tracking frame range. ROI sizes are in pixels. Missing or excluded observations remain gaps.','WordWrap','on'); note.Layout.Column=[1 2];
            obj.Coverage=uilabel(grid,'Text','','WordWrap','on'); obj.Coverage.Layout.Column=[1 2];
            names=fieldnames(obj.Controls);
            for i=1:numel(names), obj.Controls.(names{i}).ValueChangedFcn=@(~,~) obj.refresh(); end
            c.First.ValueChangedFcn=@(~,~) obj.refresh(); c.Last.ValueChangedFcn=@(~,~) obj.refresh();

            obj.ActivityTab=uitab(lower_tabs,'Title','Activity');
            display=uigridlayout(obj.ActivityTab,[2 1]); display.RowHeight={25,'1x'}; display.Padding=[3 3 3 3];
            obj.Mode=uidropdown(display,'Tooltip','Click a trace to seek to its frame. Orange points have quality flags; details are in quality.csv.','Items',{'ΔF/F','Raw fluorescence','Background','Fluorescence','Reference fluorescence','Ratio ΔF/F','Population ΔF/F'},'ValueChangedFcn',@(~,~) obj.render());
            panel=uipanel(display,'AutoResizeChildren','off','BorderType','none');
            obj.Axes=uiaxes(panel); obj.Axes.Toolbar.Visible='off';
            panel.SizeChangedFcn=@(~,~) obj.fitAxes(); obj.fitAxes();
        end
        function fitAxes(obj)
            Program.Helpers.fill_axes_parent(obj.Axes); obj.Axes.OuterPosition=[0 0 1 1];
        end
        function options = options(obj)
            options=struct('radius_xyz',sscanf(obj.Controls.radius.Value,'%f')','background',logical(obj.Controls.background.Value), ...
                'baseline_percentile',obj.Controls.baseline.Value,'signal_channel',obj.Controls.signal.Value, ...
                'reference_channel',obj.Controls.reference.Value,'max_step',obj.Controls.motion.Value, ...
                'frame_range',[obj.Controller.First.Value obj.Controller.Last.Value]);
        end
        function setBusy(obj,busy)
            state=matlab.lang.OnOffSwitchState(~busy); c=obj.Controller;
            handles=[{c.Reference;c.TrackingChannel;c.WindowSize;c.Epochs;obj.Mode};struct2cell(obj.Controls)];
            for i=1:numel(handles), handles{i}.Enable=state; end
            if c.Source.nt==1, c.Reference.Enable='off'; c.First.Enable='off'; c.Last.Enable='off'; end
        end
        function refresh(obj)
            if ~obj.Controller.Busy, obj.Controller.render(); end
        end
        function showActivity(obj)
            obj.Tabs.SelectedTab=obj.ActivityTab; obj.PlotKey={}; obj.render();
        end
        function render(obj)
            c=obj.Controller; file=fullfile(c.ActivityDirectory,'activity.h5');
            count=numel(unique(c.Rows(:,1))); total=max(1,c.Last.Value-c.First.Value+1)*max(1,count);
            present=nnz(c.Rows(:,2)>=c.First.Value & c.Rows(:,2)<=c.Last.Value);
            obj.Coverage.Text=sprintf('%d neurons · %.1f%% coordinate coverage in the selected range',count,100*present/total);
            if isempty(c.ActivityDirectory) || ~isfile(file)
                if ~isequal(obj.PlotKey,{'empty'})
                    obj.ResultKey='';
                    if ~isempty(obj.Colorbar) && isvalid(obj.Colorbar), delete(obj.Colorbar); obj.Colorbar=[]; end
                    cla(obj.Axes); title(obj.Axes,'Extract activity to view traces'); xlabel(obj.Axes,'Frame');
                    obj.PlotKey={'empty'};
                end
                return
            end
            if ~strcmp(obj.ResultKey,file)
                obj.Frames=double(h5read(file,'/frame')); obj.IDs=double(h5read(file,'/neuron_id'));
                record=jsondecode(fileread(fullfile(c.ActivityDirectory,'analysis.json'))); obj.ResultOptions=record.options;
                obj.ResultKey=file; obj.PlotKey={};
            end
            identity=c.View.PreferredID;
            index=find(obj.IDs==identity,1);
            if isempty(index), index=1; identity=obj.IDs(1); end
            key={file,identity,c.Frame.Value,obj.Mode.Value,c.activityCurrent()};
            if isequaln(obj.PlotKey,key), return; end
            if ~isempty(obj.Colorbar) && isvalid(obj.Colorbar), delete(obj.Colorbar); obj.Colorbar=[]; end
            cla(obj.Axes); hold(obj.Axes,'on');
            nt=numel(obj.Frames); population=strcmp(obj.Mode.Value,'Population ΔF/F');
            switch obj.Mode.Value
                case 'Population ΔF/F'
                    data=h5read(file,'/dff');
                    pixels=imagesc(obj.Axes,obj.Frames,[1 numel(obj.IDs)],data);
                    pixels.AlphaData=isfinite(data); pixels.ButtonDownFcn=@(~,~) obj.seek(true);
                    obj.Axes.YDir='reverse'; colormap(obj.Axes,parula(256));
                    ticks=unique(round(linspace(1,numel(obj.IDs),min(8,numel(obj.IDs)))));
                    obj.Axes.YTick=ticks; obj.Axes.YTickLabel=string(obj.IDs(ticks)); ylabel(obj.Axes,'Neuron ID');
                    title(obj.Axes,'Population ΔF/F'); obj.Colorbar=colorbar(obj.Axes); obj.Colorbar.Label.String='ΔF/F';
                otherwise
                    dataset='/dff'; ylabel_text='ΔF/F';
                    if strcmp(obj.Mode.Value,'Fluorescence'), dataset='/signal'; ylabel_text='Fluorescence (background corrected)'; end
                    if strcmp(obj.Mode.Value,'Ratio ΔF/F'), dataset='/ratio_dff'; ylabel_text='Ratio ΔF/F'; end
                    if strcmp(obj.Mode.Value,'Raw fluorescence')
                        dataset=sprintf('/raw/channel_%d',obj.ResultOptions.signal_channel); ylabel_text='Raw fluorescence';
                    elseif strcmp(obj.Mode.Value,'Background')
                        dataset=sprintf('/background/channel_%d',obj.ResultOptions.signal_channel); ylabel_text='Background fluorescence';
                    elseif strcmp(obj.Mode.Value,'Reference fluorescence')
                        dataset=''; ylabel_text='Reference fluorescence (raw)';
                        if obj.ResultOptions.reference_channel>=0, dataset=sprintf('/raw/channel_%d',obj.ResultOptions.reference_channel); end
                    end
                    if isempty(dataset), data=nan(1,nt);
                    else, data=double(h5read(file,dataset,[index 1],[1 nt])); end
                    curve=plot(obj.Axes,obj.Frames,data,'Color',[.15 .15 .15],'LineWidth',1.2,'Tag','activity_trace');
                    curve.ButtonDownFcn=@(~,~) obj.seek(false);
                    flags=h5read(file,'/quality_flags',[index 1],[1 nt]); bad=flags~=0 & isfinite(data);
                    scatter(obj.Axes,obj.Frames(bad),data(bad),16,[.8 .4 0],'filled','HitTest','off');
                    obj.Axes.YDir='normal'; obj.Axes.YTickMode='auto'; obj.Axes.YTickLabelMode='auto';
                    ylabel(obj.Axes,ylabel_text); title(obj.Axes,sprintf('Neuron %d',identity));
                    if ~any(isfinite(data)), title(obj.Axes,sprintf('Neuron %d · no usable samples',identity)); end
            end
            if ~c.activityCurrent(), title(obj.Axes,'Measurements out of date — extract again'); end
            xlim(obj.Axes,[obj.Frames(1)-.5 obj.Frames(end)+.5]); xlabel(obj.Axes,'Frame');
            xline(obj.Axes,c.Frame.Value,'Color',[.5 .5 .5],'HitTest','off');
            obj.Axes.ButtonDownFcn=@(~,~) obj.seek(population); hold(obj.Axes,'off'); obj.PlotKey=key;
        end
        function seek(obj,population)
            c=obj.Controller; if c.Busy, return; end
            point=obj.Axes.CurrentPoint;
            [~,index]=min(abs(obj.Frames-point(1,1))); frame=obj.Frames(index);
            identity=c.View.PreferredID;
            if population
                row=min(numel(obj.IDs),max(1,round(point(1,2)))); identity=obj.IDs(row);
            end
            c.View.PreferredID=identity; c.Frame.Value=frame;
            row=find(c.Rows(:,1)==identity & c.Rows(:,2)==frame,1);
            if ~isempty(row), c.View.select(c.Rows(row,:),false);
            else, c.safe(@() c.render()); end
        end
        function value = session(obj)
            c=obj.Controller;
            value=struct('first',c.First.Value,'last',c.Last.Value,'reference',c.Reference.Value, ...
                'tracking_channel',c.TrackingChannel.Value,'window_size',c.WindowSize.Value,'epochs',c.Epochs.Value, ...
                'tracking_directory',c.TrackDirectory,'activity_directory',c.ActivityDirectory, ...
                'activity_current',c.activityCurrent(),'activity_options',obj.options(),'next_id',c.NextID);
        end
        function restoreTracking(obj,parameters)
            c=obj.Controller; c.First.Value=parameters.frame_range(1)+1; c.Last.Value=parameters.frame_range(2)+1;
            c.Reference.Value=parameters.reference_frame+1; c.TrackingChannel.Value=parameters.channel;
            c.WindowSize.Value=parameters.window_size; c.Epochs.Value=parameters.epochs;
        end
        function restoreSession(obj,value)
            c=obj.Controller;
            c.First.Value=value.first; c.Last.Value=value.last; c.Reference.Value=value.reference;
            c.TrackingChannel.Value=value.tracking_channel; c.WindowSize.Value=value.window_size; c.Epochs.Value=value.epochs;
            c.TrackDirectory=value.tracking_directory; c.ActivityDirectory=value.activity_directory;
            if isfield(value,'next_id'), c.NextID=max(c.NextID,value.next_id); end
            options=value.activity_options;
            obj.Controls.signal.Value=options.signal_channel; obj.Controls.reference.Value=options.reference_channel;
            obj.Controls.radius.Value=num2str(options.radius_xyz(:)'); obj.Controls.background.Value=options.background;
            obj.Controls.baseline.Value=options.baseline_percentile; obj.Controls.motion.Value=options.max_step;
            if value.activity_current
                c.ActivityRows=c.Rows; c.ActivityExcluded=c.Excluded; c.ActivitySettings=obj.options();
            else
                c.ActivityRows=[]; c.ActivityExcluded=[]; c.ActivitySettings=struct();
            end
        end
    end
end
