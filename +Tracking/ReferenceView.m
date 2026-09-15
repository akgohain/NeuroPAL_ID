classdef ReferenceView < handle
    %REFERENCEVIEW Display reference neurons with the shared image-view controls.
    properties
        Controller
        Projection
        NeuronList
        ListRows = zeros(0,8)
        Selection = []
        Position = cell(1,3)
        Labels
        SliceValue
        Preview
        AddMode = false
        DisplayKey = []
        DisplayMaximum = 1
        ProjectionPixels = []
        Summary
        ListKey = {}
        ProjectionKey = {}
    end
    methods
        function obj = ReferenceView(c)
            obj.Controller = c;
            c.Grid = uigridlayout(c.App.VideoTrackingTab,[3 2]);
            c.Grid.ColumnWidth = {'1x',310}; c.Grid.RowHeight = {34,'1x',24};
            c.Grid.Padding = [6 6 6 6]; c.Grid.ColumnSpacing = 6; c.Grid.RowSpacing = 4;
            toolbar = uigridlayout(c.Grid,[1 9]); toolbar.Layout.Column = [1 2];
            toolbar.Padding = [0 0 0 0];
            toolbar.ColumnWidth = {40,75,50,80,105,115,70,'1x',75};
            uilabel(toolbar,'Text','Frame');
            c.Frame = uispinner(toolbar,'Limits',[1 max(2,c.Source.nt)],'Value',1, ...
                'Step',1,'ValueChangedFcn',@(~,~) c.safe(@() c.render()));
            uilabel(toolbar,'Text','Channel');
            c.Channel = uidropdown(toolbar,'Items',cellstr("C"+string(0:c.Source.nc-1)), ...
                'ItemsData',0:c.Source.nc-1,'Value',0,'ValueChangedFcn',@(~,~) c.safe(@() c.render()));
            c.Detector = uidropdown(toolbar,'Items',{'MoE','Spotiflow'});
            c.Buttons.detect = uibutton(toolbar,'Text','Auto Detect','ButtonPushedFcn',@(~,~) c.safe(@() c.detect()));
            c.Buttons.cancel = uibutton(toolbar,'Text','Cancel','ButtonPushedFcn',@(~,~) c.cancel());
            uilabel(toolbar,'Text','');
            obj.Labels = uicheckbox(toolbar,'Text','Labels','Value',true,'ValueChangedFcn',@(~,~) obj.redraw());

            images = uigridlayout(c.Grid,[3 1]); images.Layout.Row = 2; images.Layout.Column = 1;
            images.RowHeight = {'2x',52,'1x'}; images.Padding = [0 0 0 0]; images.RowSpacing = 4;
            slice_panel = uipanel(images,'BorderType','line','AutoResizeChildren','off');
            c.Axes = uiaxes(slice_panel);
            c.Axes.Toolbar.Visible = 'off'; c.Axes.FontSize = c.App.XY.FontSize;
            slice_panel.SizeChangedFcn = @(~,~) obj.fitAxes(c.Axes);
            navigation = uigridlayout(images,[1 3]); navigation.Padding = [6 4 6 4];
            navigation.ColumnWidth = {20,'1x',65};
            uilabel(navigation,'Text','Z','FontWeight','bold');
            c.Slice = uislider(navigation);
            Program.Helpers.configure_navigation_zslider(c.Slice,c.Source.nz,ceil(c.Source.nz/2));
            obj.SliceValue = uispinner(navigation,'Limits',[1 max(2,c.Source.nz)], ...
                'Value',c.Slice.Value,'ValueChangedFcn',@(~,~) obj.enterSlice());
            projection_panel = uipanel(images,'Title','Maximum Intensity Projection','AutoResizeChildren','off');
            obj.Projection = uiaxes(projection_panel); obj.Projection.Toolbar.Visible = 'off';
            obj.Projection.FontSize = c.App.XY.FontSize;
            projection_panel.SizeChangedFcn = @(~,~) obj.fitAxes(obj.Projection);

            tabs = uitabgroup(c.Grid); tabs.Layout.Row = 2; tabs.Layout.Column = 2;
            neurons = uitab(tabs,'Title','Neurons');
            controls = uigridlayout(neurons,[7 2]); controls.Padding = [6 6 6 6];
            controls.RowHeight = {24,'1x',96,28,28,28,24};
            obj.Summary = uilabel(controls,'Text',''); obj.Summary.Layout.Column = [1 2];
            obj.NeuronList = uilistbox(controls,'Items',{},'ValueChangedFcn',@(~,~) obj.chooseList());
            obj.NeuronList.Layout.Row = 2; obj.NeuronList.Layout.Column = [1 2];
            coordinates = uigridlayout(controls,[3 2]); coordinates.Layout.Row = 3; coordinates.Layout.Column = [1 2];
            coordinates.ColumnWidth = {35,'1x'}; coordinates.Padding = [0 0 0 0];
            dimensions = [c.Source.nx,c.Source.ny,c.Source.nz];
            for i = 1:3
                names = {'X','Y','Z'};
                uilabel(coordinates,'Text',names{i});
                obj.Position{i} = uispinner(coordinates,'Limits',[1 max(2,dimensions(i))], ...
                    'Value',1,'Step',1,'ValueChangedFcn',@(~,~) obj.move(i));
            end
            c.Buttons.accept = uibutton(controls,'Text','Accept candidates','ButtonPushedFcn',@(~,~) c.safe(@() c.accept()));
            c.Buttons.discard = uibutton(controls,'Text','Discard candidates','ButtonPushedFcn',@(~,~) c.safe(@() c.discard()));
            c.Buttons.add = uibutton(controls,'Text','Add neuron','ButtonPushedFcn',@(~,~) obj.armAdd());
            c.Buttons.remove = uibutton(controls,'Text','Delete neuron','ButtonPushedFcn',@(~,~) c.safe(@() c.remove()));
            c.Buttons.load = uibutton(controls,'Text','Load seeds…','ButtonPushedFcn',@(~,~) c.safe(@() c.loadDialog()));
            c.Buttons.save = uibutton(controls,'Text','Save seeds…','ButtonPushedFcn',@(~,~) c.safe(@() c.saveDialog()));
            legend = uilabel(controls,'Text','Orange: candidate   Red: neuron','FontSize',10); legend.Layout.Column = [1 2];

            settings = uitab(tabs,'Title','Settings');
            settings_grid = uigridlayout(settings,[5 1]); settings_grid.RowHeight = {24,28,28,60,'1x'};
            uilabel(settings_grid,'Text','Voxel spacing X Y Z (µm)');
            c.Spacing = uieditfield(settings_grid,'text','Value','0.4 0.4 1.5','ValueChangedFcn',@(~,~) c.spacingChanged());
            c.Calibration = uicheckbox(settings_grid,'Text','Use assumed spacing','Value',false);
            if c.Source.spacing_measured
                c.Spacing.Value = num2str(c.Source.spacing_um_xyz(:)');
                c.Calibration.Text = 'Use measured spacing'; c.Calibration.Value = true;
            end
            uilabel(settings_grid,'Text','Single-channel model accuracy is unvalidated. Review detections before tracking.','WordWrap','on');
            tracking = uitab(tabs,'Title','Tracking');
            track_grid = uigridlayout(tracking,[4 2]); track_grid.RowHeight = {28,28,28,'1x'};
            uilabel(track_grid,'Text','First frame');
            c.First = uispinner(track_grid,'Limits',[1 max(2,c.Source.nt)],'Value',1);
            uilabel(track_grid,'Text','Last frame');
            c.Last = uispinner(track_grid,'Limits',[1 max(2,c.Source.nt)],'Value',min(3,c.Source.nt));
            c.Buttons.track = uibutton(track_grid,'Text','Track window','ButtonPushedFcn',@(~,~) c.safe(@() c.track()));
            c.Buttons.track.Layout.Column = [1 2];
            table_tab = uitab(tabs,'Title','Table');
            table_grid = uigridlayout(table_tab,[1 1]); table_grid.Padding = [0 0 0 0];
            c.Table = uitable(table_grid,'Data',c.Rows,'ColumnName',{'ID','Frame','X','Y','Z','Score','Channel'}, ...
                'ColumnWidth',{45,50,65,65,65,60,55},'ColumnEditable',[false false true true true false false], ...
                'CellEditCallback',@(~,event) c.safe(@() c.edit(event)), ...
                'CellSelectionCallback',@(~,event) obj.chooseTable(event));
            c.Status = uilabel(c.Grid,'Text',''); c.Status.Layout.Row = 3; c.Status.Layout.Column = [1 2];
            obj.Preview = Program.LatestSlicePreview(@(z) obj.preview(z), ...
                @(~,~) obj.redraw(),@() {c.Source.source_id,c.Frame.Value,c.Channel.Value,c.Busy},c.Grid);
            c.Slice.ValueChangingFcn = @(~,event) obj.Preview.request(event.Value);
            c.Slice.ValueChangedFcn = @(src,event) obj.Preview.finish(src,event);
            obj.fitAxes(c.Axes); obj.fitAxes(obj.Projection);
        end
        function delete(obj)
            if ~isempty(obj.Preview) && isvalid(obj.Preview), delete(obj.Preview); end
        end
        function fitAxes(~,ax)
            Program.Helpers.fill_axes_parent(ax);
            if isgraphics(ax)
                ax.OuterPosition = [0 0 1 1];
                daspect(ax,[1 1 1]);
            end
        end
        function redraw(obj)
            if ~obj.Controller.Busy, obj.Controller.render(); end
        end
        function enterSlice(obj)
            c = obj.Controller;
            if c.Busy, return; end
            c.Slice.Value = min(c.Source.nz,round(obj.SliceValue.Value)); obj.redraw();
        end
        function preview(obj,z)
            c = obj.Controller;
            if c.Busy || c.CacheFrame~=c.Frame.Value, return; end
            obj.render(z);
        end
        function render(obj,requested_z)
            c = obj.Controller;
            if nargin<2, requested_z = c.Slice.Value; end
            volume = c.frameData(); z = max(1,min(c.Source.nz,round(requested_z)));
            obj.SliceValue.Value = z;
            key = [c.CacheFrame,c.Channel.Value];
            if ~isequal(obj.DisplayKey,key)
                obj.DisplayMaximum = max(1,double(max(volume,[],'all')));
                obj.ProjectionPixels = obj.displayPixels(max(volume,[],3)); obj.DisplayKey = key;
            end
            obj.drawImage(c.Axes,obj.displayPixels(volume(:,:,z)));
            [~,name,extension] = fileparts(c.Source.file);
            title(c.Axes,sprintf('%s%s · Frame %d · C%d · Z %d',name,extension,c.Frame.Value,c.Channel.Value,z),'Interpreter','none');
            obj.updateList();
            obj.drawMarkers(c.Axes,c.Rows,false,z); obj.drawMarkers(c.Axes,c.Candidates,true,z);
            projection_key = {key,obj.ListRows,obj.Selection,obj.Labels.Value};
            if ~isequaln(obj.ProjectionKey,projection_key)
                obj.drawImage(obj.Projection,obj.ProjectionPixels);
                obj.drawMarkers(obj.Projection,c.Rows,false,[]); obj.drawMarkers(obj.Projection,c.Candidates,true,[]);
                obj.ProjectionKey = projection_key;
            end
            if ~isequaln(c.Table.Data,c.Rows), c.Table.Data = c.Rows; end
            c.Status.Text = sprintf('Frame %d / %d · C%d · %d neurons · %d candidates', ...
                c.Frame.Value,c.Source.nt,c.Channel.Value,size(c.Rows,1),size(c.Candidates,1));
        end
        function pixels = displayPixels(obj,plane)
            pixels = repmat(uint8(single(plane)*(255/obj.DisplayMaximum)),[1 1 3]);
        end
        function drawImage(obj,ax,pixels)
            c = obj.Controller;
            scale = [1 1];
            if c.Source.spacing_measured, scale = c.Source.spacing_um_xyz(1:2); end
            [image,configure] = Program.Helpers.main_slice_image(ax,pixels,scale,false);
            if configure
                obj.fitAxes(ax); ax.YDir = 'reverse';
                Program.Helpers.configure_image_axes_ticks(ax,size(pixels),scale,'XLim',[.5 c.Source.nx+.5],'YLim',[.5 c.Source.ny+.5]);
                if ~c.Source.spacing_measured
                    x_step = max(1,round(c.Source.nx/5,-1));
                    y_step = max(1,round(c.Source.ny/5,-1));
                    ax.XTick = unique([1 x_step:x_step:c.Source.nx]);
                    ax.YTick = unique([1 y_step:y_step:c.Source.ny]);
                    ax.XTickLabel = string(ax.XTick); ax.YTickLabel = string(ax.YTick);
                    xlabel(ax,'X (pixels)'); ylabel(ax,'Y (pixels)');
                end
            end
            hold(ax,'on');
            image.HitTest = 'on'; image.ButtonDownFcn = @(~,~) obj.imageClick(ax);
        end
        function drawMarkers(obj,ax,rows,pending,z)
            if isempty(rows), return; end
            c = obj.Controller;
            keep = rows(:,2)==c.Frame.Value & rows(:,7)==c.Channel.Value;
            if ~isempty(z), keep = keep & abs(rows(:,5)-z)<1.5; end
            rows = rows(keep,:); if isempty(rows), return; end
            palette = Neurons.Neuron.marker_palette(); color = palette.unassigned;
            if pending, color = palette.candidate; end
            prefs = Program.GUIPreferences.instance().neuron_dot;
            [size_scale,line_scale] = Program.GUIPreferences.neuron_marker_display_scales();
            sizes = repmat(prefs.marker.unselected,size(rows,1),1); colors = repmat(color,size(rows,1),1);
            if ~isempty(obj.Selection)
                selected = obj.Selection(1)==pending & rows(:,1)==obj.Selection(2) & rows(:,2)==obj.Selection(3);
                sizes(selected) = prefs.marker.selected; colors(selected,:) = repmat(palette.selected,sum(selected),1);
            end
            points = scatter(ax,rows(:,3),rows(:,4),sizes*size_scale,colors,'filled', ...
                'MarkerEdgeColor',c.App.neuron_marker.color.edge,'LineWidth',prefs.line*line_scale,'Tag','reference_neurons');
            points.ButtonDownFcn = @(~,~) obj.markerClick(ax,rows,pending);
            if obj.Labels.Value
                for i=1:size(rows,1)
                    label = sprintf('#%d',rows(i,1));
                    if pending, label = sprintf('%s?',label); end
                    if rows(i,3)<=c.Source.nx/2
                        label = sprintf('\\leftarrow%s',label); offset = 4; alignment = 'left';
                    else
                        label = sprintf('%s\\rightarrow',label); offset = -4; alignment = 'right';
                    end
                    text(ax,rows(i,3)+offset,rows(i,4),label,'Color',c.App.label_color, ...
                        'FontSize',c.App.label_fontsize,'FontWeight',c.App.label_fontweight, ...
                        'HorizontalAlignment',alignment,'HitTest','off','Clipping','on','Tag','reference_label');
                end
            end
        end
        function updateList(obj)
            c = obj.Controller;
            key = {c.Frame.Value,c.Channel.Value,c.Rows,c.Candidates,obj.Selection};
            if isequaln(obj.ListKey,key), return; end
            obj.ListRows = [c.Rows,zeros(size(c.Rows,1),1);c.Candidates,ones(size(c.Candidates,1),1)];
            obj.ListRows = obj.ListRows(obj.ListRows(:,2)==c.Frame.Value & obj.ListRows(:,7)==c.Channel.Value,:);
            count = size(obj.ListRows,1);
            obj.Summary.Text = sprintf('%d neurons · %d candidates',nnz(obj.ListRows(:,8)==0),nnz(obj.ListRows(:,8)==1));
            if count==0
                obj.NeuronList.Items = {}; obj.NeuronList.ItemsData = []; obj.Selection = [];
            else
                labels = cell(count,1);
                for i=1:count
                    kind = 'Neuron'; if obj.ListRows(i,8), kind = 'Candidate'; end
                    labels{i} = sprintf('%s %d   ·   Z %.1f',kind,obj.ListRows(i,1),obj.ListRows(i,5));
                end
                index = [];
                if ~isempty(obj.Selection)
                    index = find(obj.ListRows(:,8)==obj.Selection(1) & obj.ListRows(:,1)==obj.Selection(2) & obj.ListRows(:,2)==obj.Selection(3),1);
                end
                if isempty(index), index=1; end
                row = obj.ListRows(index,:); obj.Selection = [row(8),row(1),row(2)];
                set(obj.NeuronList,'Items',labels,'ItemsData',1:count,'Value',index);
                for i=1:3, obj.Position{i}.Value = row(i+2); end
            end
            obj.ListKey = {c.Frame.Value,c.Channel.Value,c.Rows,c.Candidates,obj.Selection};
            obj.setBusy(c.Busy);
        end
        function setBusy(obj,busy)
            state = matlab.lang.OnOffSwitchState(~busy);
            obj.Labels.Enable = state; obj.NeuronList.Enable = state;
            obj.SliceValue.Enable = matlab.lang.OnOffSwitchState(~busy && obj.Controller.Source.nz>1);
            for i=1:3
                obj.Position{i}.Enable = matlab.lang.OnOffSwitchState(~isempty(obj.ListRows) && ~busy);
            end
        end
        function chooseList(obj)
            c = obj.Controller;
            if c.Busy || isempty(obj.NeuronList.Value), return; end
            row = obj.ListRows(obj.NeuronList.Value,:);
            obj.select(row,row(8));
        end
        function chooseTable(obj,event)
            c = obj.Controller;
            if c.Busy || isempty(event.Indices), return; end
            row = c.Rows(event.Indices(1),:); obj.select(row,false);
        end
        function select(obj,row,pending)
            c = obj.Controller; obj.Selection = [pending,row(1),row(2)];
            c.Frame.Value = row(2); c.Channel.Value = row(7); c.Slice.Value = min(c.Source.nz,max(1,round(row(5))));
            c.safe(@() c.render());
        end
        function markerClick(obj,ax,rows,pending)
            if obj.Controller.Busy, return; end
            point = ax.CurrentPoint;
            [~,index] = min(sum((rows(:,3:4)-point(1,1:2)).^2,2));
            obj.select(rows(index,:),pending);
        end
        function armAdd(obj)
            if obj.Controller.Busy, return; end
            obj.AddMode = ~obj.AddMode;
            if obj.AddMode, obj.Controller.Buttons.add.Text = 'Click image…';
            else, obj.Controller.Buttons.add.Text = 'Add neuron'; end
        end
        function imageClick(obj,ax)
            c = obj.Controller; if c.Busy, return; end
            if obj.AddMode && ~isequal(ax,c.Axes), return; end
            c.Cursor = ax.CurrentPoint;
            if obj.AddMode
                obj.AddMode = false; c.Buttons.add.Text = 'Add neuron';
                c.safe(@() c.add());
            end
        end
        function move(obj,dimension)
            c = obj.Controller; if c.Busy || isempty(obj.Selection), return; end
            bounds = [c.Source.nx,c.Source.ny,c.Source.nz]; value = obj.Position{dimension}.Value;
            if value<1 || value>bounds(dimension), obj.redraw(); return; end
            pending = obj.Selection(1);
            if pending, rows = c.Candidates; else, rows = c.Rows; end
            index = find(rows(:,1)==obj.Selection(2) & rows(:,2)==obj.Selection(3),1);
            if isempty(index), return; end
            rows(index,dimension+2) = value; rows(index,6)=1;
            if pending, c.Candidates=rows;
            else
                c.Rows=rows; c.Origins(sprintf('%d:%d',rows(index,1),rows(index,2)))='reviewed';
            end
            if dimension==3, c.Slice.Value=round(value); end
            obj.redraw();
        end
        function removeSelection(obj)
            c = obj.Controller; if isempty(obj.Selection), return; end
            if obj.Selection(1)
                c.Candidates(c.Candidates(:,1)==obj.Selection(2) & c.Candidates(:,2)==obj.Selection(3),:)=[];
            else
                c.Rows(c.Rows(:,1)==obj.Selection(2) & c.Rows(:,2)==obj.Selection(3),:)=[];
            end
            obj.Selection=[]; c.render();
        end
    end
end
