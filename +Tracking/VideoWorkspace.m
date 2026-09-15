classdef VideoWorkspace
    %VIDEOWORKSPACE Build the recording, detection, tracking and review workspace.
    methods (Static)
        function build(v)
            c=v.Controller;
            c.Grid=uigridlayout(c.App.VideoTrackingTab,[6 1]);
            c.Grid.RowHeight={24,32,32,0,'1x',22}; c.Grid.Padding=[10 6 10 4]; c.Grid.RowSpacing=6;
            [~,name,extension]=fileparts(c.Source.file);
            source=uilabel(c.Grid,'Text',sprintf('%s%s  ·  %d frames  ·  %d channels  ·  %d Z slices',name,extension,c.Source.nt,c.Source.nc,c.Source.nz));
            source.Tooltip=c.Source.file; source.FontColor=[.4 .4 .4]; source.FontSize=11;
            steps=uigridlayout(c.Grid,[1 5]); steps.Padding=[0 0 0 0]; steps.ColumnSpacing=6; steps.ColumnWidth={140,140,140,140,170};
            names={'Recording','Detect','Track','Review','Activity & export'};
            for i=1:5
                v.Stages{i}=uibutton(steps,'Text',names{i},'ButtonPushedFcn',@(~,~) v.setStage(i));
            end
            toolbar=uigridlayout(c.Grid,[1 11]); toolbar.Padding=[0 0 0 0]; toolbar.ColumnSpacing=5;
            toolbar.ColumnWidth={32,85,52,85,95,0,130,90,90,'1x',80};
            uilabel(toolbar,'Text','View');
            v.DisplayMode=uidropdown(toolbar,'Items',{'Slice','Slab','MIP'},'Value','Slab','ValueChangedFcn',@(~,~) v.changeView());
            uilabel(toolbar,'Text','Channel');
            c.Channel=uidropdown(toolbar,'Items',cellstr("C"+string(0:c.Source.nc-1)),'ItemsData',0:c.Source.nc-1, ...
                'Value',0,'ValueChangedFcn',@(~,~) v.changeView());
            v.Contrast=Tracking.DisplayContrast(v,toolbar);
            v.Labels=uicheckbox(toolbar,'Text','Labels','Visible','off','Value',true,'ValueChangedFcn',@(~,~) v.redraw());
            v.LabelMode=uidropdown(toolbar,'Items',{'No labels','Selected label','Sparse labels','All labels'},'ItemsData',{'None','Selected','Sparse','All'},'Value','Selected','ValueChangedFcn',@(~,~) v.changeLabels());
            v.Trails=uicheckbox(toolbar,'Text','Trail','Value',true,'ValueChangedFcn',@(~,~) v.redraw());
            v.XYZ=uicheckbox(toolbar,'Text','XYZ views','ValueChangedFcn',@(~,~) v.redraw());
            uilabel(toolbar,'Text','');
            c.Buttons.cancel=uibutton(toolbar,'Text','Cancel job','ButtonPushedFcn',@(~,~) c.cancel());

            v.Body=uigridlayout(c.Grid,[4 2]); v.Body.Layout.Row=5;
            v.Body.RowHeight={'1x',42,100,210}; v.Body.ColumnWidth={'1x',310};
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
            for i=1:5
                v.Panels{i}=uipanel(inspector,'BorderType','line','Visible','off');
                v.Panels{i}.Layout.Row=1; v.Panels{i}.Layout.Column=1;
            end

            setup=uigridlayout(v.Panels{1},[10 1]); setup.Padding=[10 10 10 10];
            setup.RowHeight={26,42,26,28,28,42,28,28,28,'1x'};
            uilabel(setup,'Text','Recording setup','FontWeight','bold');
            uilabel(setup,'Text',sprintf('%d × %d × %d voxels\n%d frames · %d channels',c.Source.nx,c.Source.ny,c.Source.nz,c.Source.nt,c.Source.nc),'WordWrap','on');
            uilabel(setup,'Text','Voxel spacing X Y Z (µm)');
            c.Spacing=uieditfield(setup,'text','Value','0.4 0.4 1.5','ValueChangedFcn',@(~,~) c.spacingChanged());
            c.Calibration=uicheckbox(setup,'Text','Use assumed spacing','Value',false);
            if c.Source.spacing_measured
                c.Spacing.Value=num2str(c.Source.spacing_um_xyz(:)'); c.Calibration.Text='Use measured spacing'; c.Calibration.Value=true;
            end
            uilabel(setup,'Text','Choose detection, tracking and activity channels independently in each stage.','WordWrap','on');
            c.Buttons.load=uibutton(setup,'Text','Load saved session…','ButtonPushedFcn',@(~,~) c.safe(@() c.loadDialog()));
            c.Buttons.save=uibutton(setup,'Text','Save session…','ButtonPushedFcn',@(~,~) c.safe(@() c.saveDialog()));
            uibutton(setup,'Text','Continue to detection','ButtonPushedFcn',@(~,~) v.setStage(2));

            detection=uigridlayout(v.Panels{2},[9 2]); detection.Padding=[12 10 12 10];
            detection.ColumnWidth={75,'1x'}; detection.RowSpacing=10;
            detection.RowHeight={28,28,28,28,38,32,28,28,'1x'};
            heading=uilabel(detection,'Text','Detect reference neurons','FontWeight','bold'); heading.Layout.Column=[1 2];
            uilabel(detection,'Text','Method'); c.Detector=uidropdown(detection,'Items',{'MoE','Spotiflow'});
            uilabel(detection,'Text','Input');
            c.DetectionMode=uidropdown(detection,'Items',{'Single channel','RGBW'},'Value','Single channel','ValueChangedFcn',@(~,~) v.detectionModeChanged());
            uilabel(detection,'Text','Channels');
            c.DetectionChannel=uidropdown(detection,'Items',cellstr("C"+string(0:c.Source.nc-1)),'ItemsData',0:c.Source.nc-1,'Value',0);
            c.DetectionChannel.Layout.Row=4; c.DetectionChannel.Layout.Column=2;
            c.RGBW=uieditfield(detection,'text','Value','0 1 2 3','Tooltip','Channel indices in R G B W order','Visible','off');
            c.RGBW.Layout.Row=4; c.RGBW.Layout.Column=2;
            v.DetectionSummary=uilabel(detection,'Text','Choose a reference frame with the time slider.','WordWrap','on','FontColor',[.4 .4 .4]);
            v.DetectionSummary.Layout.Row=5; v.DetectionSummary.Layout.Column=[1 2];
            c.Buttons.detect=uibutton(detection,'Text','Auto Detect','FontWeight','bold','ButtonPushedFcn',@(~,~) c.safe(@() c.detect()));
            c.Buttons.detect.Layout.Row=6; c.Buttons.detect.Layout.Column=[1 2];
            actions=uigridlayout(detection,[1 2]); actions.Layout.Row=7; actions.Layout.Column=[1 2]; actions.Padding=[0 0 0 0];
            c.Buttons.accept=uibutton(actions,'Text','Accept candidates','ButtonPushedFcn',@(~,~) c.safe(@() c.accept()));
            c.Buttons.discard=uibutton(actions,'Text','Discard','ButtonPushedFcn',@(~,~) c.safe(@() c.discard()));
            actions=uigridlayout(detection,[1 2]); actions.Layout.Row=8; actions.Layout.Column=[1 2]; actions.Padding=[0 0 0 0];
            uibutton(actions,'Text','Review seeds','ButtonPushedFcn',@(~,~) v.setStage(4));
            uibutton(actions,'Text','Continue to tracking','ButtonPushedFcn',@(~,~) v.setStage(3));

            review=uigridlayout(v.Panels{4},[11 2]); review.Padding=[12 10 12 10]; review.RowSpacing=6;
            review.Scrollable='on';
            review.RowHeight={24,28,28,32,'1x',32,28,28,28,24,28};
            v.Summary=uilabel(review,'Text','Review tracks','FontWeight','bold'); v.Summary.Layout.Column=[1 2];
            v.Review=Tracking.VideoReview(v,review);
            v.NeuronList=uilistbox(review,'Items',{},'ValueChangedFcn',@(~,~) v.chooseList());
            v.NeuronList.Layout.Row=5; v.NeuronList.Layout.Column=[1 2];
            coordinates=uigridlayout(review,[1 6]); coordinates.Layout.Row=6; coordinates.Layout.Column=[1 2];
            coordinates.ColumnWidth={12,'1x',12,'1x',12,'1x'}; coordinates.Padding=[0 0 0 0]; coordinates.ColumnSpacing=4;
            dimensions=[c.Source.nx,c.Source.ny,c.Source.nz]; names={'X','Y','Z'};
            for i=1:3
                uilabel(coordinates,'Text',names{i});
                v.Position{i}=uispinner(coordinates,'Limits',[1 max(2,dimensions(i))],'Value',1,'Step',1,'ValueChangedFcn',@(~,~) v.move(i));
            end
            c.Buttons.add=uibutton(review,'Text','Add neuron','ButtonPushedFcn',@(~,~) v.armAdd()); c.Buttons.add.Layout.Row=7;
            c.Buttons.remove=uibutton(review,'Text','Delete track','ButtonPushedFcn',@(~,~) c.safe(@() c.remove())); c.Buttons.remove.Layout.Row=7; c.Buttons.remove.Layout.Column=2;
            v.Review.Confirm=uibutton(review,'Text','Confirm frame','ButtonPushedFcn',@(~,~) v.Review.confirm()); v.Review.Confirm.Layout.Row=8; v.Review.Confirm.FontWeight='bold';
            v.Review.Undo=uibutton(review,'Text','Undo edit','ButtonPushedFcn',@(~,~) v.Review.undo()); v.Review.Undo.Layout.Row=8; v.Review.Undo.Layout.Column=2;
            uibutton(review,'Text','Correct center','ButtonPushedFcn',@(~,~) v.armCorrect());
            uibutton(review,'Text','Save session…','ButtonPushedFcn',@(~,~) c.safe(@() c.saveDialog()));
            v.Exclude=uicheckbox(review,'Text','Exclude this observation from activity','ValueChangedFcn',@(~,~) v.exclude());
            v.Exclude.Layout.Row=10; v.Exclude.Layout.Column=[1 2];
            uibutton(review,'Text','Coordinate table…','ButtonPushedFcn',@(~,~) v.openTable());
            table_panel=uipanel(c.Grid,'Visible','off'); table_panel.Layout.Row=6;
            c.Table=uitable(table_panel,'Data',c.Rows,'ColumnName',{'ID','Frame','X','Y','Z','Score','Channel'}, ...
                'ColumnEditable',[false false true true true false false], ...
                'CellEditCallback',@(~,event) c.safe(@() c.edit(event)), ...
                'CellSelectionCallback',@(~,event) v.chooseTable(event));
            c.Analysis=Tracking.ReferenceAnalysisView(c,v.Panels{3},v.Panels{5},activity_display);
            c.Status=uilabel(c.Grid,'Text',''); c.Status.Layout.Row=6;
            v.Preview=Program.LatestSlicePreview(@(z) v.preview(z),@(~,~) v.redraw(), ...
                @() {c.Source.source_id,c.Frame.Value,c.Channel.Value,c.Busy},c.Grid);
            v.FramePreview=Program.LatestSlicePreview(@(t) v.navigate(t),@(src,~) v.navigate(src.Value), ...
                @() {c.Source.source_id,c.Busy},c.Grid);
            c.Frame.ValueChangingFcn=@(~,event) v.Playback.request(event.Value);
            c.Frame.ValueChangedFcn=@(src,event) v.Playback.finish(src,event);
            c.Slice.ValueChangingFcn=@(~,event) v.previewRequest(event.Value);
            c.Slice.ValueChangedFcn=@(src,event) v.finishSlice(src,event);
            v.Playback.connect(); v.fitAxes(c.Axes); v.fitAxes(v.Projection); v.setStage(1);
        end
    end
end
