classdef VideoWorkspace
    %VIDEOWORKSPACE Build the detection, tracking and review workspace.
    methods (Static)
        function build(v)
            c=v.Controller;
            c.Grid=uigridlayout(c.App.VideoTrackingTab,[6 1]);
            c.Grid.RowHeight={0,32,32,0,'1x',22}; c.Grid.Padding=[10 6 10 4]; c.Grid.RowSpacing=6;
            uilabel(c.Grid,'Text','','Visible','off');
            steps=uigridlayout(c.Grid,[1 5]); steps.Padding=[0 0 0 0]; steps.ColumnSpacing=6; steps.ColumnWidth={140,140,140,'1x',110};
            names={'','Detect','Track','Review','Activity & export'};
            for i=2:4
                v.Stages{i}=uibutton(steps,'Text',names{i},'ButtonPushedFcn',@(~,~) v.setStage(i));
            end
            c.Buttons.reset=uibutton(steps,'Text','Reset session','ButtonPushedFcn',@(~,~) Tracking.SessionReset.confirm(c));
            c.Buttons.reset.Layout.Column=5;
            toolbar=uigridlayout(c.Grid,[1 13]); toolbar.Padding=[0 0 0 0]; toolbar.ColumnSpacing=5;
            toolbar.ColumnWidth={32,85,52,85,95,110,0,130,70,90,75,'1x',80};
            uilabel(toolbar,'Text','View');
            v.DisplayMode=uidropdown(toolbar,'Items',{'Slice','Slab','MIP'},'Value','Slab','ValueChangedFcn',@(~,~) v.changeView());
            uilabel(toolbar,'Text','Channel');
            c.Channel=uidropdown(toolbar,'Items',cellstr("C"+string(0:c.Source.nc-1)),'ItemsData',0:c.Source.nc-1, ...
                'Value',0,'ValueChangedFcn',@(~,~) v.changeView());
            v.Contrast=Tracking.DisplayContrast(v,toolbar);
            settings_button=uibutton(toolbar,'Text','Image settings…','ButtonPushedFcn',@(~,~) v.openSettings());
            setappdata(c.Grid,'image_settings_button',settings_button);
            v.Labels=uicheckbox(toolbar,'Text','Labels','Visible','off','Value',true,'ValueChangedFcn',@(~,~) v.redraw());
            v.LabelMode=uidropdown(toolbar,'Items',{'No labels','Selected label','Sparse labels','All labels'},'ItemsData',{'None','Selected','Sparse','All'},'Value','Selected','ValueChangedFcn',@(~,~) v.changeLabels());
            v.Trails=uicheckbox(toolbar,'Text','Trail','Value',true,'ValueChangedFcn',@(~,~) v.redraw());
            v.XYZ=uicheckbox(toolbar,'Text','XYZ views','ValueChangedFcn',@(~,~) v.redraw());
            Tracking.ImageUnits.build(c,toolbar);
            uilabel(toolbar,'Text','');
            c.Buttons.cancel=uibutton(toolbar,'Text','Cancel job','ButtonPushedFcn',@(~,~) c.cancel());

            v.Body=uigridlayout(c.Grid,[4 2]); v.Body.Layout.Row=5;
            v.Body.RowHeight={'1x',42,86,210}; v.Body.ColumnWidth={'1x',310};
            v.Body.Padding=[0 0 0 0]; v.Body.RowSpacing=6; v.Body.ColumnSpacing=12;
            v.ImageGrid=uigridlayout(v.Body,[1 2]); v.ImageGrid.Layout.Row=1; v.ImageGrid.Layout.Column=1;
            v.ImageGrid.Padding=[0 0 0 0]; v.ImageGrid.ColumnWidth={'1x',0};
            host=uigridlayout(v.ImageGrid,[1 1]); host.Padding=[0 0 0 0];
            v.SlicePanel=uipanel(host,'BorderType','none','AutoResizeChildren','off');
            v.SlicePanel.Layout.Row=1; v.SlicePanel.Layout.Column=1;
            c.Axes=uiaxes(v.SlicePanel); c.Axes.Toolbar.Visible='off'; c.Axes.FontSize=c.App.XY.FontSize;
            v.SlicePanel.SizeChangedFcn=@(~,~) v.fitAxes(c.Axes);
            v.ProjectionPanel=uipanel(host,'BorderType','none','AutoResizeChildren','off','Visible','off');
            v.ProjectionPanel.Layout.Row=1; v.ProjectionPanel.Layout.Column=1;
            v.Projection=uiaxes(v.ProjectionPanel); v.Projection.Toolbar.Visible='off'; v.Projection.FontSize=c.App.XY.FontSize;
            v.ProjectionPanel.SizeChangedFcn=@(~,~) v.fitAxes(v.Projection);
            v.OrthogonalPanel=uigridlayout(v.ImageGrid,[3 1]); v.OrthogonalPanel.Padding=[0 0 0 0]; v.OrthogonalPanel.Visible='off';
            for i=1:3
                panel=uipanel(v.OrthogonalPanel,'AutoResizeChildren','off','BorderType','none');
                v.Orthogonal{i}=uiaxes(panel); v.Orthogonal{i}.Toolbar.Visible='off';
                panel.SizeChangedFcn=@(~,~) v.fitAxes(v.Orthogonal{i});
            end
            depth=uigridlayout(v.Body,[1 5]); depth.Layout.Row=2; depth.Layout.Column=1;
            depth.Padding=[8 3 8 3]; depth.ColumnWidth={15,'1x',65,100,90};
            uilabel(depth,'Text','Z'); c.Slice=uislider(depth);
            Program.Helpers.configure_navigation_zslider(c.Slice,c.Source.nz,ceil(c.Source.nz/2));
            v.SliceValue=uispinner(depth,'Limits',[1 max(2,c.Source.nz)],'Value',c.Slice.Value,'ValueChangedFcn',@(~,~) v.enterSlice());
            v.Follow=uicheckbox(depth,'Text','Follow neuron','ValueChangedFcn',@(~,~) v.redraw());
            v.ShowROI=uicheckbox(depth,'Text','ROI outline','Value',true,'ValueChangedFcn',@(~,~) v.redraw());
            transport=uipanel(v.Body,'BorderType','none'); transport.Layout.Row=3; transport.Layout.Column=1;
            v.Playback=Tracking.VideoPlayback(v,transport);
            activity_display=uipanel(v.Body,'BorderType','none'); activity_display.Layout.Row=4; activity_display.Layout.Column=1;
            inspector=uigridlayout(v.Body,[1 1]); inspector.Padding=[0 0 0 0]; inspector.Layout.Row=[1 4]; inspector.Layout.Column=2;
            for i=2:5
                v.Panels{i}=uipanel(inspector,'BorderType','none','Visible','off');
                v.Panels{i}.Layout.Row=1; v.Panels{i}.Layout.Column=1;
            end

            settings_window=uifigure('Name','Image settings','Position',[300 300 350 175],'Visible','off', ...
                'CloseRequestFcn',@(src,~) set(src,'Visible','off'));
            setappdata(c.Grid,'image_settings_window',settings_window);
            setup=uigridlayout(settings_window,[4 1]); setup.Padding=[14 12 14 12]; setup.RowHeight={24,28,28,28};
            uilabel(setup,'Text','Voxel spacing X Y Z (µm)');
            c.Spacing=uieditfield(setup,'text','Value','0.4 0.4 1.5','ValueChangedFcn',@(~,~) c.spacingChanged());
            c.Calibration=uicheckbox(setup,'Text','Use assumed spacing','Value',false);
            if c.Source.spacing_measured
                c.Spacing.Value=num2str(c.Source.spacing_um_xyz(:)'); c.Calibration.Text='Use measured spacing'; c.Calibration.Value=true;
            end
            uibutton(setup,'Text','Done','ButtonPushedFcn',@(~,~) set(settings_window,'Visible','off'));
            c.Buttons.load=uimenu(c.App.OpenMenu.Parent,'Text','Load tracking session…','Separator','on', ...
                'MenuSelectedFcn',@(~,~) c.safe(@() c.loadDialog()));
            c.Buttons.save=uimenu(c.App.OpenMenu.Parent,'Text','Save tracking session…', ...
                'MenuSelectedFcn',@(~,~) c.safe(@() c.saveDialog()));
            setappdata(c.Grid,'tracking_session_menus',{c.Buttons.load,c.Buttons.save});

            detection=uigridlayout(v.Panels{2},[10 2]); detection.Padding=[12 10 12 10];
            detection.ColumnWidth={75,'1x'}; detection.RowSpacing=8; detection.Scrollable='on';
            detection.RowHeight={24,30,30,28,6,34,30,30,0,'1x'};
            heading=uilabel(detection,'Text','Detection','FontWeight','bold'); heading.Layout.Column=[1 2];
            uilabel(detection,'Text','Method'); c.Detector=uidropdown(detection,'Items',{'MoE','Spotiflow'});
            uilabel(detection,'Text','Input');
            c.DetectionMode=uidropdown(detection,'Items',{'Single channel','Multi-channel'},'Value','Single channel','ValueChangedFcn',@(~,~) v.detectionModeChanged());
            uilabel(detection,'Text','Channels');
            c.DetectionChannel=uidropdown(detection,'Items',cellstr("C"+string(0:c.Source.nc-1)),'ItemsData',0:c.Source.nc-1,'Value',0);
            c.DetectionChannel.Layout.Row=4; c.DetectionChannel.Layout.Column=2;
            c.RGBW=uieditfield(detection,'text','Value','0 1 2 3','Tooltip','Channel indices in R G B W order','Visible','off');
            c.RGBW.Layout.Row=4; c.RGBW.Layout.Column=2;
            Tracking.DetectionChannels.build(c,detection);
            v.DetectionSummary=uilabel(detection,'Text','','Visible','off');
            v.DetectionSummary.Layout.Row=5; v.DetectionSummary.Layout.Column=[1 2];
            c.Buttons.detect=uibutton(detection,'Text','Auto Detect','FontWeight','bold','ButtonPushedFcn',@(~,~) c.safe(@() c.detect()));
            c.Buttons.detect.Layout.Row=6; c.Buttons.detect.Layout.Column=[1 2];
            Tracking.VideoWorkspace.primary(c.Buttons.detect,true);
            actions=uigridlayout(detection,[1 2]); actions.Layout.Row=7; actions.Layout.Column=[1 2]; actions.Padding=[0 0 0 0];
            c.Buttons.accept=uibutton(actions,'Text','Accept candidates','ButtonPushedFcn',@(~,~) c.safe(@() c.accept()));
            c.Buttons.accept.Layout.Column=[1 2];
            c.Buttons.continueTracking=uibutton(detection,'Text','Continue to tracking →', ...
                'ButtonPushedFcn',@(~,~) c.continueTracking());
            c.Buttons.continueTracking.Layout.Row=8; c.Buttons.continueTracking.Layout.Column=[1 2];

            if isfield(c.Source,'neuropal')
                c.Buttons.paired=uibutton(detection,'Text','NeuroPAL reference…','ButtonPushedFcn',@(~,~) c.safe(@() Tracking.NeuroPALReference.open(c)));
                c.Buttons.paired.Layout.Row=9; c.Buttons.paired.Layout.Column=[1 2]; detection.RowHeight{9}=28;
            end

            review=uigridlayout(v.Panels{4},[6 2]); review.Padding=[12 10 12 10]; review.RowSpacing=6;
            review.Scrollable='on';
            review.RowHeight={24,'1x',32,28,28,24};
            v.Summary=uilabel(review,'Text','Review tracks','FontWeight','bold'); v.Summary.Layout.Column=[1 2];
            v.Review=Tracking.VideoReview(v);
            v.NeuronList=uilistbox(review,'Items',{},'ValueChangedFcn',@(~,~) v.chooseList());
            v.NeuronList.Layout.Row=2; v.NeuronList.Layout.Column=[1 2];
            coordinates=uigridlayout(review,[1 6]); coordinates.Layout.Row=3; coordinates.Layout.Column=[1 2];
            coordinates.ColumnWidth={12,'1x',12,'1x',12,'1x'}; coordinates.Padding=[0 0 0 0]; coordinates.ColumnSpacing=4;
            dimensions=[c.Source.nx,c.Source.ny,c.Source.nz]; names={'X','Y','Z'};
            for i=1:3
                uilabel(coordinates,'Text',names{i});
                v.Position{i}=uispinner(coordinates,'Limits',[.5 dimensions(i)+.5],'Value',1,'Step',1,'ValueChangedFcn',@(~,~) v.move(i));
            end
            c.Buttons.correct=uibutton(review,'Text','Correct center','ButtonPushedFcn',@(~,~) v.armCorrect());
            c.Buttons.correct.Layout.Row=4; c.Buttons.correct.Layout.Column=1;
            v.Review.Undo=uibutton(review,'Text','Undo edit','ButtonPushedFcn',@(~,~) v.Review.undo());
            v.Review.Undo.Layout.Row=4; v.Review.Undo.Layout.Column=2;
            v.Review.Confirm=uibutton(review,'Text','Confirm frame','ButtonPushedFcn',@(~,~) v.Review.confirm());
            v.Review.Confirm.Layout.Row=5; v.Review.Confirm.Layout.Column=1;
            menu=uicontextmenu(c.App.CELL_ID);
            c.Buttons.rename=uimenu(menu,'Text','Edit neuron name…','MenuSelectedFcn',@(~,~) Tracking.NeuronNames.edit(c));
            c.Buttons.add=uimenu(menu,'Text','Add neuron','Separator','on','MenuSelectedFcn',@(~,~) v.armAdd());
            c.Buttons.remove=uimenu(menu,'Text','Delete track','MenuSelectedFcn',@(~,~) c.safe(@() c.remove()));
            c.Buttons.coordinates=uimenu(menu,'Text','Coordinate table…','Separator','on','MenuSelectedFcn',@(~,~) v.openTable());
            c.Buttons.neuronActions=uibutton(review,'Text','Neuron actions ▾', ...
                'ButtonPushedFcn',@(src,~) Tracking.VideoWorkspace.neuronMenu(c,src,menu));
            c.Buttons.neuronActions.Layout.Row=5; c.Buttons.neuronActions.Layout.Column=2;
            setappdata(c.Grid,'neuron_actions_menu',menu);
            v.Exclude=uicheckbox(review,'Text','Exclude from activity', ...
                'Tooltip','Exclude the selected neuron in this frame. Other frames are kept.', ...
                'ValueChangedFcn',@(~,~) v.exclude());
            v.Exclude.Layout.Row=6; v.Exclude.Layout.Column=[1 2];
            table_panel=uipanel(c.Grid,'Visible','off'); table_panel.Layout.Row=6;
            c.Table=uitable(table_panel,'Data',c.Rows,'ColumnName',{'ID','Frame','X','Y','Z','Score','Channel'}, ...
                'ColumnEditable',[false false true true true false false], ...
                'CellEditCallback',@(~,event) c.safe(@() c.edit(event)), ...
                'CellSelectionCallback',@(~,event) v.chooseTable(event));
            c.Analysis=Tracking.ReferenceAnalysisView(c,v.Panels{3},v.Panels{5},activity_display);
            Tracking.VideoWorkspace.mergeReview(v);
            Tracking.ImageSettings.build(c);
            c.Status=uilabel(c.Grid,'Text',''); c.Status.Layout.Row=6;
            v.Preview=Program.LatestSlicePreview(@(z) v.preview(z),@(~,~) v.redraw(), ...
                @() {c.Source.source_id,c.Frame.Value,c.Channel.Value,c.Busy},c.Grid);
            v.FramePreview=Program.LatestSlicePreview(@(t) v.navigate(t),@(src,~) v.navigate(src.Value), ...
                @() {c.Source.source_id,c.Busy},c.Grid);
            c.Frame.ValueChangingFcn=@(~,event) v.Playback.request(event.Value);
            c.Frame.ValueChangedFcn=@(src,event) v.Playback.finish(src,event);
            c.Slice.ValueChangingFcn=@(~,event) v.previewRequest(event.Value);
            c.Slice.ValueChangedFcn=@(src,event) v.finishSlice(src,event);
            v.Playback.connect(); v.fitAxes(c.Axes); v.fitAxes(v.Projection); v.setStage(2);
        end
        function mergeReview(v)
            c=v.Controller; review=v.Panels{4}; activity=v.Panels{5};
            merged=uipanel(review.Parent,'BorderType','none'); merged.Layout.Row=1; merged.Layout.Column=1;
            grid=uigridlayout(merged,[5 1]); grid.Padding=[12 10 12 0]; grid.RowSpacing=8;
            grid.RowHeight={'1x',1,28,34,30}; grid.Scrollable='on';
            review.Parent=grid; review.Layout.Row=1; review.Layout.Column=1; review.Visible='on';
            review.Children.Padding=[0 10 0 10];
            divider=uipanel(grid,'BorderType','none','BackgroundColor',[.8 .8 .8]); divider.Layout.Row=2;
            window=uifigure('Name','Activity settings','Position',[300 300 380 260],'Visible','off', ...
                'CloseRequestFcn',@(src,~) set(src,'Visible','off'));
            host=uigridlayout(window,[1 1]); host.Padding=[0 0 0 0];
            activity.Parent=host; activity.Layout.Row=1; activity.Layout.Column=1; activity.Visible='on';
            setappdata(c.Grid,'activity_settings_window',window);
            c.Buttons.activitySettings=uibutton(grid,'Text','Activity settings…', ...
                'ButtonPushedFcn',@(~,~) Tracking.VideoWorkspace.openActivitySettings(c));
            c.Buttons.activitySettings.Layout.Row=3;
            activity_grid=c.Analysis.Controls.signal.Parent; activity_grid.RowHeight{7}=0; activity_grid.RowHeight{8}=0;
            c.Buttons.activity.Parent=grid; c.Buttons.activity.Layout.Row=4; c.Buttons.activity.Layout.Column=1;
            Tracking.VideoWorkspace.primary(c.Buttons.activity,true);
            footer=uigridlayout(grid,[1 2]); footer.Layout.Row=5; footer.Padding=[0 0 0 0]; footer.ColumnSpacing=6;
            c.Buttons.saveSession=uibutton(footer,'Text','Save session…','ButtonPushedFcn',@(~,~) c.safe(@() c.saveDialog()));
            c.Buttons.export.Parent=footer; c.Buttons.export.Layout.Row=1; c.Buttons.export.Layout.Column=2;
            c.Buttons.export.Text='Export…'; c.Buttons.export.Tooltip='Export activity and tracks together.';
            v.Panels{4}=merged;
        end
        function openActivitySettings(c)
            if c.Busy, return; end
            c.View.Playback.stop(); window=getappdata(c.Grid,'activity_settings_window');
            window.Visible='on'; figure(window);
        end
        function toggleAdvanced(c,src,panel)
            if c.Busy, return; end
            opened=strcmp(panel.Visible,'off'); panel.Visible=matlab.lang.OnOffSwitchState(opened);
            if opened, panel.Parent.RowHeight{7}=68; src.Text='Advanced ▾';
            else, panel.Parent.RowHeight{7}=0; src.Text='Advanced ▸'; end
        end
        function openMenu(c,src,menu)
            if c.Busy, return; end
            c.View.Playback.stop(); position=getpixelposition(src,true);
            open(menu,round(position(1)),round(position(2)));
        end
        function neuronMenu(c,src,menu)
            if c.Busy, return; end
            if c.View.AddMode, c.View.armAdd(); return; end
            Tracking.VideoWorkspace.openMenu(c,src,menu);
        end
        function primary(button,selected)
            if selected
                button.BackgroundColor=[.24 .24 .24]; button.FontColor=[1 1 1]; button.FontWeight='bold';
            else
                button.BackgroundColor=[.94 .94 .94]; button.FontColor=[.15 .15 .15]; button.FontWeight='normal';
            end
        end
        function refreshActions(c,busy)
            names={'detect','accept','track','resume','progress','openrun','runOptions','advanced', ...
                'activity','export','add','remove','correct','rename','coordinates','neuronActions','saveSession','activitySettings','paired'};
            for i=1:numel(names)
                if isfield(c.Buttons,names{i}), c.Buttons.(names{i}).Enable=matlab.lang.OnOffSwitchState(~busy); end
            end
            selected=~isempty(c.View.Selection); accepted=selected && ~c.View.Selection(1);
            for name={'remove','correct'}, c.Buttons.(name{1}).Enable=matlab.lang.OnOffSwitchState(~busy && selected); end
            c.Buttons.rename.Enable=matlab.lang.OnOffSwitchState(~busy && accepted);
            c.Buttons.accept.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(c.Candidates));
            c.Buttons.resume.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(c.TrackDirectory));
            c.Buttons.progress.Enable=c.Buttons.resume.Enable;
            c.Buttons.export.Enable=matlab.lang.OnOffSwitchState(~busy && c.activityCurrent());
            if c.View.AddMode, c.Buttons.neuronActions.Text='Cancel add';
            else, c.Buttons.neuronActions.Text='Neuron actions ▾'; end
            Tracking.VideoWorkspace.primary(c.Buttons.detect,isempty(c.Candidates));
            Tracking.VideoWorkspace.primary(c.Buttons.accept,~isempty(c.Candidates));
        end
    end
end
