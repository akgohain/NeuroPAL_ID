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
        FrameCursor = []
    end
    methods
        function obj = ReferenceAnalysisView(c,tracking,activity,activity_display)
            obj.Controller=c;
            grid=uigridlayout(tracking,[11 2]); grid.RowHeight={24,20,30,30,30,26,0,4,34,28,'1x'};
            grid.Padding=[12 10 12 10]; grid.ColumnWidth={105,'1x'}; grid.RowSpacing=8; grid.Scrollable='on';
            heading=uilabel(grid,'Text','Tracking','FontWeight','bold'); heading.Layout.Row=1; heading.Layout.Column=[1 2];
            label=uilabel(grid,'Text','Frame range'); label.Layout.Row=2; label.Layout.Column=[1 2];
            range=uigridlayout(grid,[1 3]); range.Layout.Row=3; range.Layout.Column=[1 2];
            range.Padding=[0 0 0 0]; range.ColumnWidth={'1x',20,'1x'}; range.ColumnSpacing=6;
            c.First=uispinner(range,'Limits',[1 max(2,c.Source.nt)],'Value',1,'Tooltip','First frame to track and measure.');
            uilabel(range,'Text','to','HorizontalAlignment','center');
            c.Last=uispinner(range,'Limits',[1 max(2,c.Source.nt)],'Value',c.Source.nt,'Tooltip','Last frame to track and measure.');
            label=uilabel(grid,'Text','Reference frame'); label.Layout.Row=4;
            c.Reference=uispinner(grid,'Limits',[1 max(2,c.Source.nt)],'Value',1,'Tooltip','A frame containing accepted reference neurons.');
            c.Reference.Layout.Row=4; c.Reference.Layout.Column=2;
            items=cellstr("C"+string(0:c.Source.nc-1));
            label=uilabel(grid,'Text','Channel'); label.Layout.Row=5;
            c.TrackingChannel=uidropdown(grid,'Items',items,'ItemsData',0:c.Source.nc-1,'Value',0);
            c.TrackingChannel.Layout.Row=5; c.TrackingChannel.Layout.Column=2;
            advanced=uigridlayout(grid,[2 2]); advanced.Layout.Row=7; advanced.Layout.Column=[1 2];
            advanced.Padding=[0 0 0 0]; advanced.RowHeight={30,30}; advanced.RowSpacing=8; advanced.ColumnWidth={'1x',90}; advanced.Visible='off';
            uilabel(advanced,'Text','Frames per window'); c.WindowSize=uispinner(advanced,'Limits',[2 100],'Value',50);
            uilabel(advanced,'Text','Epochs per frame'); c.Epochs=uispinner(advanced,'Limits',[1 1000],'Value',40);
            c.Buttons.advanced=uibutton(grid,'Text','Advanced ▸','HorizontalAlignment','left', ...
                'ButtonPushedFcn',@(src,~) Tracking.VideoWorkspace.toggleAdvanced(c,src,advanced));
            c.Buttons.advanced.Layout.Row=6; c.Buttons.advanced.Layout.Column=[1 2];
            c.Buttons.track=uibutton(grid,'Text','Run ZephIR','ButtonPushedFcn',@(~,~) c.safe(@() c.track()));
            c.Buttons.track.Layout.Row=9; c.Buttons.track.Layout.Column=[1 2]; Tracking.VideoWorkspace.primary(c.Buttons.track,true);
            menu=uicontextmenu(c.App.CELL_ID);
            c.Buttons.resume=uimenu(menu,'Text','Resume tracking','MenuSelectedFcn',@(~,~) c.safe(@() c.track(true)));
            c.Buttons.progress=uimenu(menu,'Text','Load completed frames','MenuSelectedFcn',@(~,~) c.safe(@() c.loadProgress()));
            c.Buttons.openrun=uimenu(menu,'Text','Open tracking run…','Separator','on','MenuSelectedFcn',@(~,~) c.safe(@() c.openTracking()));
            c.Buttons.runOptions=uibutton(grid,'Text','Saved run ▾', ...
                'Tooltip','Open a saved run, resume tracking, or load completed windows.', ...
                'ButtonPushedFcn',@(src,~) Tracking.VideoWorkspace.openMenu(c,src,menu));
            c.Buttons.runOptions.Layout.Row=10; c.Buttons.runOptions.Layout.Column=[1 2];
            setappdata(c.Grid,'tracking_run_menu',menu);

            grid=uigridlayout(activity,[9 2]); grid.RowHeight={30,30,30,30,30,30,32,28,0};
            grid.Padding=[14 12 14 12]; grid.ColumnWidth={'1x',110}; grid.RowSpacing=8; grid.Scrollable='on';
            uilabel(grid,'Text','Signal channel'); obj.Controls.signal=uidropdown(grid,'Items',items,'ItemsData',0:c.Source.nc-1,'Value',0);
            uilabel(grid,'Text','Reference channel'); obj.Controls.reference=uidropdown(grid,'Items',[{'None'};items(:)],'ItemsData',[-1 0:c.Source.nc-1],'Value',-1);
            uilabel(grid,'Text','ROI radii X Y Z (px)'); obj.Controls.radius=uieditfield(grid,'text','Value','3 3 1');
            obj.Controls.background=uicheckbox(grid,'Text','Subtract local background','Value',true); obj.Controls.background.Layout.Column=[1 2];
            uilabel(grid,'Text','Baseline percentile'); obj.Controls.baseline=uispinner(grid,'Limits',[0 100],'Value',20);
            uilabel(grid,'Text','Motion warning (px)'); obj.Controls.motion=uispinner(grid,'Limits',[.1 1000],'Value',10);
            c.Buttons.activity=uibutton(grid,'Text','Extract activity','FontWeight','bold','ButtonPushedFcn',@(~,~) c.safe(@() c.extractActivity())); c.Buttons.activity.Layout.Column=[1 2];
            c.Buttons.export=uibutton(grid,'Text','Export activity + tracks…','ButtonPushedFcn',@(~,~) c.safe(@() c.exportActivity())); c.Buttons.export.Layout.Column=[1 2];
            obj.Controls.radius.Tooltip='Ellipsoidal sampling radii in X, Y and Z pixels. Uses the Tracking frame range.';
            obj.Controls.baseline.Tooltip='Percentile used for the fluorescence baseline over the Tracking frame range.';
            obj.Controls.motion.Tooltip='Per-frame displacement threshold recorded in exported quality flags.';
            obj.Coverage=uilabel(grid,'Text','','WordWrap','on','Visible','off'); obj.Coverage.Layout.Row=9; obj.Coverage.Layout.Column=[1 2];
            names=fieldnames(obj.Controls);
            for i=1:numel(names), obj.Controls.(names{i}).ValueChangedFcn=@(~,~) obj.refresh(); end
            c.First.ValueChangedFcn=@(~,~) obj.refresh(); c.Last.ValueChangedFcn=@(~,~) obj.refresh();

            obj.ActivityTab=activity_display;
            display=uigridlayout(activity_display,[2 1]); display.RowHeight={25,'1x'}; display.Padding=[6 6 6 3];
            header=uigridlayout(display,[1 5]); header.Padding=[0 0 0 0]; header.ColumnWidth={60,165,'1x',95,105};
            uilabel(header,'Text','Activity','FontWeight','bold');
            obj.Mode=uidropdown(header,'Tooltip','Click the trace to seek to a frame.','Items',{'ΔF/F','Raw fluorescence','Fluorescence','Reference fluorescence'},'UserData',false,'ValueChangedFcn',@(~,~) obj.render());
            uilabel(header,'Text','');
            uibutton(header,'Text','Population','Tag','activity_population_toggle','ButtonPushedFcn',@(~,~) obj.population());
            uibutton(header,'Text','Expand trace','ButtonPushedFcn',@(src,~) obj.expand(src));
            panel=uipanel(display,'AutoResizeChildren','off','BorderType','none');
            obj.Axes=uiaxes(panel); obj.Axes.Toolbar.Visible='off';
            panel.SizeChangedFcn=@(~,~) obj.fitAxes(); obj.fitAxes();
        end
        function population(obj)
            if obj.Controller.Busy, return; end
            obj.Mode.UserData=~logical(obj.Mode.UserData);
            obj.Mode.Enable=matlab.lang.OnOffSwitchState(~obj.Mode.UserData);
            button=findobj(obj.Mode.Parent,'Tag','activity_population_toggle');
            if obj.Mode.UserData, button.Text='Single neuron'; else, button.Text='Population'; end
            obj.render();
        end
        function expand(obj,src)
            body=obj.Controller.View.Body;
            if body.RowHeight{4}==210, body.RowHeight{4}=310; src.Text='Shrink trace';
            else, body.RowHeight{4}=210; src.Text='Expand trace'; end
        end
        function fitAxes(obj)
            Program.Helpers.fill_axes_parent(obj.Axes); obj.Axes.OuterPosition=[0 0 1 1];
        end
        function options = options(obj)
            radius=str2double(split(strtrim(string(obj.Controls.radius.Value))))';
            options=struct('radius_xyz',radius,'background',logical(obj.Controls.background.Value), ...
                'baseline_percentile',obj.Controls.baseline.Value,'signal_channel',obj.Controls.signal.Value, ...
                'reference_channel',obj.Controls.reference.Value,'max_step',obj.Controls.motion.Value, ...
                'frame_range',[obj.Controller.First.Value obj.Controller.Last.Value]);
        end
        function setBusy(obj,busy)
            state=matlab.lang.OnOffSwitchState(~busy); c=obj.Controller;
            handles=[{c.Reference;c.TrackingChannel;c.WindowSize;c.Epochs;obj.Mode};struct2cell(obj.Controls)];
            for i=1:numel(handles), handles{i}.Enable=state; end
            obj.Mode.Enable=matlab.lang.OnOffSwitchState(~busy && ~obj.Mode.UserData);
            if c.Source.nt==1, c.Reference.Enable='off'; c.First.Enable='off'; c.Last.Enable='off'; end
        end
        function refresh(obj)
            if ~obj.Controller.Busy, obj.Controller.render(); end
        end
        function showActivity(obj)
            obj.PlotKey={}; obj.render();
        end
        function render(obj)
            c=obj.Controller; file=fullfile(c.ActivityDirectory,'activity.h5');
            cleanup=onCleanup(@() Tracking.ImageSettings.axis(c));
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
            mode=obj.Mode.Value;
            if obj.Mode.UserData, mode='Population ΔF/F'; end
            identity=c.View.PreferredID;
            index=find(obj.IDs==identity,1);
            if isempty(index), index=1; identity=obj.IDs(1); end
            key={file,identity,mode,c.activityCurrent()};
            if strcmp(mode,'Population ΔF/F'), key{2}=[]; end
            if isequaln(obj.PlotKey,key) && isgraphics(obj.FrameCursor)
                obj.FrameCursor.Value=c.Frame.Value; return
            end
            if ~isempty(obj.Colorbar) && isvalid(obj.Colorbar), delete(obj.Colorbar); obj.Colorbar=[]; end
            cla(obj.Axes); hold(obj.Axes,'on');
            nt=numel(obj.Frames); population=strcmp(mode,'Population ΔF/F');
            switch mode
                case 'Population ΔF/F'
                    data=h5read(file,'/dff');
                    pixels=imagesc(obj.Axes,obj.Frames,[1 numel(obj.IDs)],data);
                    pixels.AlphaData=isfinite(data); pixels.ButtonDownFcn=@(~,~) obj.seek(true);
                    obj.Axes.YDir='reverse'; colormap(obj.Axes,parula(256));
                    ticks=unique(round(linspace(1,numel(obj.IDs),min(8,numel(obj.IDs)))));
                    obj.Axes.YTick=ticks; obj.Axes.YTickLabel=arrayfun(@(id) string(Tracking.NeuronNames.label(c,id)),obj.IDs(ticks)); ylabel(obj.Axes,'Neuron ID');
                    title(obj.Axes,'Population ΔF/F'); obj.Colorbar=colorbar(obj.Axes); obj.Colorbar.Label.String='ΔF/F';
                otherwise
                    dataset='/dff'; ylabel_text='ΔF/F';
                    if strcmp(mode,'Fluorescence'), dataset='/signal'; ylabel_text='Fluorescence (background corrected)'; end
                    if strcmp(mode,'Raw fluorescence')
                        dataset=sprintf('/raw/channel_%d',obj.ResultOptions.signal_channel); ylabel_text='Raw fluorescence';
                    elseif strcmp(mode,'Background')
                        dataset=sprintf('/background/channel_%d',obj.ResultOptions.signal_channel); ylabel_text='Background fluorescence';
                    elseif strcmp(mode,'Reference fluorescence')
                        dataset=''; ylabel_text='Reference fluorescence (raw)';
                        if obj.ResultOptions.reference_channel>=0, dataset=sprintf('/raw/channel_%d',obj.ResultOptions.reference_channel); end
                    end
                    if isempty(dataset), data=nan(1,nt);
                    else, data=double(h5read(file,dataset,[index 1],[1 nt])); end
                    curve=plot(obj.Axes,obj.Frames,data,'Color',[.15 .15 .15],'LineWidth',1.2,'Tag','activity_trace');
                    curve.ButtonDownFcn=@(~,~) obj.seek(false);
                    % Review flags live on the shared timeline instead of covering the trace.

                    obj.Axes.YDir='normal'; obj.Axes.YTickMode='auto'; obj.Axes.YTickLabelMode='auto';
                    ylabel(obj.Axes,ylabel_text); title(obj.Axes,Tracking.NeuronNames.label(c,identity,true));
                    if ~any(isfinite(data)), title(obj.Axes,sprintf('%s · no usable samples',Tracking.NeuronNames.label(c,identity,true))); end
            end
            if ~c.activityCurrent(), title(obj.Axes,'Measurements out of date — extract again'); end
            xlim(obj.Axes,[obj.Frames(1)-.5 obj.Frames(end)+.5]); xlabel(obj.Axes,'Frame');
            obj.FrameCursor=xline(obj.Axes,c.Frame.Value,'Color',[.5 .5 .5],'HitTest','off','Tag','activity_cursor');
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
            c.View.Playback.stop(); c.View.PreferredID=identity; c.Frame.Value=frame;
            row=find(c.Rows(:,1)==identity & c.Rows(:,2)==frame,1);
            if ~isempty(row), c.View.select(c.Rows(row,:),false);
            else, c.safe(@() c.render()); end
        end
        function value = session(obj)
            c=obj.Controller;
            value=struct('first',c.First.Value,'last',c.Last.Value,'reference',c.Reference.Value, ...
                'tracking_channel',c.TrackingChannel.Value,'window_size',c.WindowSize.Value,'epochs',c.Epochs.Value, ...
                'tracking_directory',c.TrackDirectory,'activity_directory',c.ActivityDirectory, ...
                'activity_current',c.activityCurrent(),'activity_options',obj.options(),'next_id',c.NextID, ...
                'detection_channel',c.DetectionChannel.Value,'detection_mode',c.DetectionMode.Value,'rgbw_channels',c.RGBW.Value, ...
                'detector',c.Detector.Value,'spacing_text',c.Spacing.Value,'calibration_confirmed',c.Calibration.Value);
            value.neuron_names=Tracking.NeuronNames.get(c);
            value.paired_reference=getappdata(c.Grid,'paired_reference_provenance');
            value.image_settings=Tracking.ImageSettings.get(c);
            value.detection_channels=Tracking.DetectionChannels.get(c);
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
            if isfield(value,'detector'), c.Detector.Value=value.detector; end
            if isfield(value,'spacing_text'), c.Spacing.Value=value.spacing_text; end
            if isfield(value,'calibration_confirmed'), c.Calibration.Value=value.calibration_confirmed; end
            if isfield(value,'detection_channel'), c.DetectionChannel.Value=value.detection_channel; end
            if isfield(value,'detection_mode')
                % Preserve the original joint RGBW path when opening older sessions.
                if strcmp(value.detection_mode,'RGBW') && ~any(strcmp(c.DetectionMode.Items,'RGBW'))
                    c.DetectionMode.Items=[c.DetectionMode.Items {'RGBW'}];
                end
                c.DetectionMode.Value=value.detection_mode;
            end
            if isfield(value,'detection_channels'), Tracking.DetectionChannels.restore(c,value.detection_channels); end
            if isfield(value,'rgbw_channels'), c.RGBW.Value=value.rgbw_channels; end
            c.View.detectionModeChanged();
            if isfield(value,'neuron_names'), Tracking.NeuronNames.set(c,value.neuron_names); end
            if isfield(value,'paired_reference'), setappdata(c.Grid,'paired_reference_provenance',value.paired_reference); end
            if isfield(value,'image_settings'), Tracking.ImageSettings.restore(c,value.image_settings); end
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
