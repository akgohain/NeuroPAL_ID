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
        FramePreview
        IndexedRows = []
        FrameIndices = {}
        TableRows = []
        AddMode = false
        DisplayKey = []
        DisplayMaximum = 1
        DisplayMinimum = 0
        Contrast
        ProjectionPixels = []
        Summary
        ListKey = {}
        ProjectionKey = {}
        LabelMode
        PreferredID = 1
        Exclude
        ShowROI
        Playback
        Review
        Panels = cell(1,5)
        Stages = cell(1,5)
        Stage = 1
        Body
        DisplayMode
        DetectionSummary
        Trails
        Follow
        XYZ
        ImageGrid
        SlicePanel
        ProjectionPanel
        OrthogonalPanel
        Orthogonal = cell(1,3)
        CorrectMode = false
        TableWindow = []
        Rendering = false
        PendingRender = false
    end
    methods
        function obj = ReferenceView(c)
            obj.Controller = c;
            Tracking.VideoWorkspace.build(obj);
        end
        function setStage(obj,index)
            if obj.Controller.Busy, return; end
            if ~isempty(obj.Playback), obj.Playback.stop(); end
            obj.Stage=index;
            for i=1:5
                obj.Panels{i}.Visible=matlab.lang.OnOffSwitchState(i==index);
                if i==index
                    obj.Stages{i}.BackgroundColor=[.24 .24 .24]; obj.Stages{i}.FontColor=[1 1 1]; obj.Stages{i}.FontWeight='bold';
                else
                    obj.Stages{i}.BackgroundColor=[.94 .94 .94]; obj.Stages{i}.FontColor=[.25 .25 .25]; obj.Stages{i}.FontWeight='normal';
                end
            end
        end
        function detectionModeChanged(obj)
            c=obj.Controller;
            rgbw=strcmp(c.DetectionMode.Value,'RGBW');
            c.RGBW.Visible=matlab.lang.OnOffSwitchState(rgbw);
            c.DetectionChannel.Visible=matlab.lang.OnOffSwitchState(~rgbw);
        end
        function changeView(obj)
            obj.Playback.stop(); obj.Preview.cancel(); obj.FramePreview.cancel(); obj.redraw();
        end
        function changeLabels(obj)
            obj.Labels.Value=~strcmp(obj.LabelMode.Value,'None'); obj.redraw();
        end
        function previewRequest(obj,z)
            c=obj.Controller; if c.Busy, return; end
            obj.Follow.Value=false;
            % Keep the chosen depth when the next movie frame arrives.
            c.Slice.Value=max(1,min(c.Source.nz,round(z)));
            obj.Preview.request(c.Slice.Value);
        end
        function finishSlice(obj,src,event)
            c=obj.Controller; if c.Busy, return; end
            z=src.Value;
            if (isstruct(event) && isfield(event,'Value')) || (isobject(event) && isprop(event,'Value')), z=event.Value; end
            obj.Follow.Value=false; obj.Preview.cancel();
            c.Slice.Value=max(1,min(c.Source.nz,round(z))); obj.redraw();
        end
        function radius = sliceRadius(obj)
            radius=1.5;
            if strcmp(obj.DisplayMode.Value,'Slab'), radius=2.5; end
        end
        function armCorrect(obj)
            c=obj.Controller; if c.Busy || isempty(obj.Selection), return; end
            obj.Playback.stop(); obj.CorrectMode=true; obj.AddMode=false;
            obj.DisplayMode.Value='Slice'; obj.redraw();
            c.Status.Text='Click the selected neuron’s new center in this Z slice.';
        end
        function correctAt(obj,xyz)
            c=obj.Controller; if c.Busy || isempty(obj.Selection), return; end
            xyz=min([c.Source.nx c.Source.ny c.Source.nz],max(1,xyz));
            pending=obj.Selection(1);
            if pending, rows=c.Candidates; else, rows=c.Rows; end
            index=find(rows(:,1)==obj.Selection(2) & rows(:,2)==c.Frame.Value,1);
            if isempty(index), return; end
            obj.Review.checkpoint(); obj.CorrectMode=false;
            rows(index,3:5)=xyz; rows(index,6)=1;
            if pending, c.Candidates=rows;
            else
                c.Rows=rows; c.Origins(sprintf('%d:%d',rows(index,1),rows(index,2)))='reviewed';
            end
            c.render();
        end
        function openTable(obj)
            obj.Playback.stop();
            if ~isempty(obj.TableWindow) && isvalid(obj.TableWindow)
                figure(obj.TableWindow); return;
            end
            obj.TableWindow=uifigure('Name','Neuron coordinates','Position',[200 200 720 420]);
            grid=uigridlayout(obj.TableWindow,[1 1]); c=obj.Controller;
            uitable(grid,'Data',c.Rows,'ColumnName',c.Table.ColumnName,'ColumnEditable',c.Table.ColumnEditable, ...
                'CellEditCallback',@(src,event) obj.editTable(src,event), ...
                'CellSelectionCallback',@(~,event) obj.chooseTable(event));
        end
        function editTable(obj,src,event)
            obj.Controller.safe(@() obj.Controller.edit(event)); src.Data=obj.Controller.Rows;
        end
        function drawTrail(obj,ax)
            c=obj.Controller; trail=findobj(ax,'Tag','selected_trail');
            if ~isempty(trail), trail.Visible='off'; end
            if ~obj.Trails.Value || isempty(obj.Selection) || obj.Selection(1), return; end
            rows=sortrows(c.Rows(c.Rows(:,1)==obj.PreferredID & c.Rows(:,2)<=c.Frame.Value & c.Rows(:,2)>c.Frame.Value-12,:),2);
            if size(rows,1)<2, return; end
            if isequal(ax,c.Axes) && abs(rows(end,5)-obj.SliceValue.Value)>=obj.sliceRadius(), return; end
            x=rows(:,3); y=rows(:,4);
            gaps=[false;diff(rows(:,2))>1] | ismember(rows(:,[1 2]),c.Excluded,'rows'); x(gaps)=NaN; y(gaps)=NaN;
            if isempty(trail)
                plot(ax,x,y,'Color',[.8 .7 .35],'LineWidth',.75,'HitTest','off','Tag','selected_trail');
            else
                set(trail,'XData',x,'YData',y,'Visible','on');
            end
        end
        function drawOrthogonal(obj,volume)
            if ~obj.XYZ.Value
                obj.ImageGrid.ColumnWidth={'1x',0}; obj.OrthogonalPanel.Visible='off'; return;
            end
            obj.ImageGrid.ColumnWidth={'1x',160}; obj.OrthogonalPanel.Visible='on';
            c=obj.Controller;
            row=obj.ListRows(obj.ListRows(:,1)==obj.PreferredID & obj.ListRows(:,8)==0,:);
            if isempty(row)
                for i=1:3, cla(obj.Orthogonal{i}); title(obj.Orthogonal{i},'No selected center'); end
                return;
            end
            xyz=round(row(1,3:5)); x=max(1,xyz(1)-18):min(c.Source.nx,xyz(1)+18);
            y=max(1,xyz(2)-18):min(c.Source.ny,xyz(2)+18); z=max(1,xyz(3)-8):min(c.Source.nz,xyz(3)+8);
            planes={volume(y,x,xyz(3)),reshape(volume(xyz(2),x,z),numel(x),numel(z))',reshape(volume(y,xyz(1),z),numel(y),numel(z))'};
            names={'XY','XZ','YZ'};
            for i=1:3
                ax=obj.Orthogonal{i}; img=findobj(ax,'Type','image'); pixels=obj.displayPixels(planes{i});
                if isempty(img), image(ax,pixels); else, img.CData=pixels; img.XData=[1 size(pixels,2)]; img.YData=[1 size(pixels,1)]; end
                axis(ax,'image'); ax.XTick=[]; ax.YTick=[]; title(ax,[names{i} ' · voxels'],'FontSize',10);
            end
        end
        function delete(obj)
            if isprop(obj,'Playback') && ~isempty(obj.Playback) && isvalid(obj.Playback), delete(obj.Playback); end
            if isprop(obj,'TableWindow') && ~isempty(obj.TableWindow) && isvalid(obj.TableWindow), delete(obj.TableWindow); end
            if isprop(obj,'Review') && ~isempty(obj.Review) && isvalid(obj.Review), obj.Review.clear(); delete(obj.Review); end
            if ~isempty(obj.Contrast) && isvalid(obj.Contrast), delete(obj.Contrast); end
            if ~isempty(obj.FramePreview) && isvalid(obj.FramePreview), delete(obj.FramePreview); end
            if ~isempty(obj.Preview) && isvalid(obj.Preview), delete(obj.Preview); end
        end
        function navigate(obj,frame,continuous)
            c=obj.Controller; if c.Busy, return; end
            if nargin<3 || ~continuous, obj.Playback.stop(); end
            if obj.Rendering
                if nargin<3 || ~continuous, obj.FramePreview.request(frame); end
                return;
            end
            if obj.Follow.Value
                row=find(c.Rows(:,1)==obj.PreferredID & c.Rows(:,2)==round(frame),1);
                if ~isempty(row), c.Slice.Value=min(c.Source.nz,max(1,round(c.Rows(row,5)))); end
            end
            obj.Preview.cancel(); c.Frame.Value=min(c.Source.nt,max(1,round(frame)));
            try
                c.render();
            catch ME
                if c.CacheFrame>0, c.Frame.Value=c.CacheFrame; end
                obj.Playback.stop(); c.Status.Text=ME.message; uialert(c.App.CELL_ID,ME.message,'Frame navigation');
            end
        end
        function fitAxes(obj,ax)
            if isgraphics(ax)
                if isequal(ax,obj.Controller.Axes) || isequal(ax,obj.Projection)
                    % Reserve space for labels when the image pane changes width.
                    ax.Units='normalized'; ax.PositionConstraint='outerposition';
                    ax.LooseInset=max(ax.TightInset,[.04 .10 .02 .06]);
                    ax.OuterPosition=[0 0 1 1];
                else
                    Program.Helpers.fill_axes_parent(ax); ax.OuterPosition=[0 0 1 1];
                end
                daspect(ax,[1 1 1]);
            end
        end
        function redraw(obj)
            if ~obj.Controller.Busy, obj.Controller.render(); end
        end
        function enterSlice(obj)
            c = obj.Controller;
            if c.Busy, return; end
            obj.Follow.Value=false; obj.Preview.cancel();
            c.Slice.Value = max(1,min(c.Source.nz,round(obj.SliceValue.Value))); obj.redraw();
        end
        function preview(obj,z)
            c = obj.Controller;
            if c.Busy || c.CacheFrame~=c.Frame.Value, return; end
            obj.render(z);
        end
        function render(obj,requested_z)
            c = obj.Controller;
            if obj.Rendering, obj.PendingRender=true; return; end
            obj.Rendering=true; cleanup=onCleanup(@() obj.finishRender());
            if nargin<2, requested_z = c.Slice.Value; end
            volume = c.frameData(); z = max(1,min(c.Source.nz,round(requested_z)));
            if obj.SliceValue.Value~=z, obj.SliceValue.Value=z; end
            range = obj.Contrast.getRange(volume);
            obj.DisplayMinimum = range(1); obj.DisplayMaximum = range(2);
            key = [c.CacheFrame,c.Channel.Value,range];
            if ~isequal(obj.DisplayKey,key)
                obj.ProjectionPixels = obj.displayPixels(max(volume,[],3)); obj.DisplayKey = key;
            end
            plane=volume(:,:,z);
            if strcmp(obj.DisplayMode.Value,'Slab')
                plane=max(volume(:,:,max(1,z-2):min(c.Source.nz,z+2)),[],3);
            end
            obj.drawImage(c.Axes,obj.displayPixels(plane));
            mip=strcmp(obj.DisplayMode.Value,'MIP');
            obj.SlicePanel.Visible=matlab.lang.OnOffSwitchState(~mip);
            obj.ProjectionPanel.Visible=matlab.lang.OnOffSwitchState(mip);
            title(c.Axes,sprintf('Frame %d · C%d · Z %d',c.Frame.Value,c.Channel.Value,z),'Interpreter','none','FontWeight','normal');
            obj.updateList();
            setappdata(c.Axes,'reference_label_boxes',zeros(0,4));
            obj.drawMarkers(c.Axes,obj.ListRows(obj.ListRows(:,8)==0,1:7),false,z); obj.drawMarkers(c.Axes,c.Candidates,true,z);
            obj.drawROI(c.Axes,z); obj.drawTrail(obj.Projection);
            projection_key = {key,obj.ListRows,obj.Selection,obj.Labels.Value,obj.LabelMode.Value,c.Excluded,obj.ShowROI.Value,c.Analysis.options()};
            if ~isequaln(obj.ProjectionKey,projection_key)
                obj.drawImage(obj.Projection,obj.ProjectionPixels);
                setappdata(obj.Projection,'reference_label_boxes',zeros(0,4));
                obj.drawMarkers(obj.Projection,obj.ListRows(obj.ListRows(:,8)==0,1:7),false,[]); obj.drawMarkers(obj.Projection,c.Candidates,true,[]);
                obj.drawROI(obj.Projection,[]);
                title(obj.Projection,sprintf('Frame %d · C%d · MIP',c.Frame.Value,c.Channel.Value),'FontWeight','normal');
                obj.ProjectionKey = projection_key;
            end
            if ~isequaln(obj.TableRows,c.Rows)
                c.Table.Data=c.Rows; obj.TableRows=c.Rows;
                if ~isempty(obj.TableWindow) && isvalid(obj.TableWindow)
                    table=findobj(obj.TableWindow,'Type','uitable'); table.Data=c.Rows;
                end
            end
            c.Status.Text = sprintf('Frame %d / %d · C%d · %d neurons · %d candidates', ...
                c.Frame.Value,c.Source.nt,c.Channel.Value,numel(unique(c.Rows(:,1))),size(c.Candidates,1));
            obj.drawTrail(c.Axes); obj.drawTrail(obj.Projection); obj.drawOrthogonal(volume);
            obj.Playback.sync(); c.Analysis.render(); obj.Review.render();
            obj.DetectionSummary.Text=sprintf('Frame %d · %d candidates',c.Frame.Value,size(c.Candidates,1));
        end
        function finishRender(obj)
            obj.Rendering=false;
            if obj.PendingRender
                obj.PendingRender=false;
                obj.Preview.request(obj.Controller.Slice.Value);
            end
        end
        function pixels = displayPixels(obj,plane)
            pixels = Tracking.DisplayContrast.pixels(plane,[obj.DisplayMinimum obj.DisplayMaximum]);
        end
        function drawImage(obj,ax,pixels)
            c = obj.Controller;
            scale = [1 1];
            if c.Source.spacing_measured, scale = c.Source.spacing_um_xyz(1:2); end
            image=getappdata(ax,'main_slice_image');
            if isgraphics(image,'image')
                image.CData=pixels; configure=false;
                delete(findobj(ax,'Tag','reference_label'));
            else
                [image,configure] = Program.Helpers.main_slice_image(ax,pixels,scale,false);
            end
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
            points=findobj(ax,'Tag',sprintf('reference_neurons_%d',pending));
            if ~isempty(points), points.Visible='off'; end
            if isempty(rows), return; end
            c = obj.Controller;
            keep = rows(:,2)==c.Frame.Value;
            if ~isempty(z), keep = keep & abs(rows(:,5)-z)<obj.sliceRadius(); end
            rows = rows(keep,:); if isempty(rows), return; end
            palette = Neurons.Neuron.marker_palette(); color = palette.unassigned;
            if pending, color = palette.candidate; end
            prefs = Program.GUIPreferences.instance().neuron_dot;
            [size_scale,line_scale] = Program.GUIPreferences.neuron_marker_display_scales();
            sizes = repmat(prefs.marker.unselected,size(rows,1),1); colors = repmat(color,size(rows,1),1);
            selected=false(size(rows,1),1);
            if ~isempty(obj.Selection)
                selected = obj.Selection(1)==pending & rows(:,1)==obj.Selection(2) & rows(:,2)==obj.Selection(3);
                sizes(selected) = prefs.marker.selected; colors(selected,:) = repmat(palette.selected,sum(selected),1);
            end
            excluded=ismember(rows(:,[1 2]),c.Excluded,'rows');
            colors(excluded,:)=repmat([.55 .55 .55],nnz(excluded),1);
            order=[find(~selected);find(selected)];
            if isempty(points)
                points=scatter(ax,rows(order,3),rows(order,4),sizes(order)*size_scale,colors(order,:),'filled', ...
                    'MarkerEdgeColor',c.App.neuron_marker.color.edge,'LineWidth',prefs.line*line_scale, ...
                    'MarkerFaceAlpha',.8,'Tag',sprintf('reference_neurons_%d',pending));
            else
                set(points,'XData',rows(order,3),'YData',rows(order,4),'SizeData',sizes(order)*size_scale, ...
                    'CData',colors(order,:),'Visible','on','MarkerEdgeColor',c.App.neuron_marker.color.edge, ...
                    'LineWidth',prefs.line*line_scale);
            end
            points.ButtonDownFcn=@(~,~) obj.markerClick(ax,rows,pending);
            if obj.Labels.Value
                for i=[find(selected);find(~selected)]'
                    if strcmp(obj.LabelMode.Value,'Selected') && ~selected(i), continue; end
                    label=sprintf('#%d',rows(i,1));
                    if pending, label=sprintf('%s?',label); end
                    if ~obj.labelFits(ax,rows(i,3:4),label,selected(i)), continue; end
                    if rows(i,3)<=c.Source.nx/2
                        label=sprintf('\\leftarrow%s',label); offset=4; alignment='left';
                    else
                        label=sprintf('%s\\rightarrow',label); offset=-4; alignment='right';
                    end
                    text(ax,rows(i,3)+offset,rows(i,4),label,'Color',c.App.label_color, ...
                        'FontSize',c.App.label_fontsize,'FontWeight',c.App.label_fontweight, ...
                        'HorizontalAlignment',alignment,'HitTest','off','Clipping','on','Tag','reference_label');
                end
            end
        end
        function fits = labelFits(obj,ax,point,label,selected)
            fits=true;
            if ~strcmp(obj.LabelMode.Value,'Sparse'), return; end
            pixels=getpixelposition(ax,true); scale=min(pixels(3)/obj.Controller.Source.nx,pixels(4)/obj.Controller.Source.ny);
            point=point*scale; width=(numel(label)+2)*obj.Controller.App.label_fontsize*.7;
            box=[point(1)+4*scale point(2)-8 width 18];
            if point(1)>obj.Controller.Source.nx*scale/2, box(1)=point(1)-4*scale-width; end
            boxes=getappdata(ax,'reference_label_boxes');
            if ~isempty(boxes) && ~selected
                fits=~any(box(1)<boxes(:,1)+boxes(:,3) & box(1)+box(3)>boxes(:,1) & ...
                    box(2)<boxes(:,2)+boxes(:,4) & box(2)+box(4)>boxes(:,2));
            end
            if fits, setappdata(ax,'reference_label_boxes',[boxes;box]); end
        end
        function drawROI(obj,ax,z)
            c=obj.Controller; outline=findobj(ax,'Tag','reference_roi');
            if ~isempty(outline), outline.Visible='off'; end
            if ~obj.ShowROI.Value || isempty(obj.Selection), return; end
            index=find(obj.ListRows(:,1)==obj.Selection(2),1);
            radius=sscanf(c.Analysis.Controls.radius.Value,'%f')';
            if isempty(index) || numel(radius)~=3 || any(~isfinite(radius) | radius<=0), return; end
            row=obj.ListRows(index,:); factor=1;
            if ~isempty(z)
                fraction=(z-row(5))/radius(3);
                if abs(fraction)>1, return; end
                factor=sqrt(1-fraction^2);
            end
            theta=linspace(0,2*pi,64);
            x=row(3)+radius(1)*factor*cos(theta); y=row(4)+radius(2)*factor*sin(theta);
            if isempty(outline)
                plot(ax,x,y,'Color',[1 1 1],'LineWidth',.75,'HitTest','off','Tag','reference_roi');
            else
                set(outline,'XData',x,'YData',y,'Visible','on');
            end
        end
        function exclude(obj)
            c=obj.Controller;
            if c.Busy || isempty(obj.Selection) || obj.Selection(1), return; end
            obj.Review.checkpoint();
            key=obj.Selection([2 3]); c.Excluded(ismember(c.Excluded,key,'rows'),:)=[];
            if obj.Exclude.Value, c.Excluded(end+1,:)=key; end
            obj.redraw();
        end

        function updateList(obj)
            c = obj.Controller;
            key = {c.Frame.Value,c.Channel.Value,c.Rows,c.Candidates,obj.Selection,c.Excluded};
            if isequaln(obj.ListKey,key), return; end
            if ~isequaln(obj.IndexedRows,c.Rows) || isempty(obj.FrameIndices)
                obj.FrameIndices=accumarray(c.Rows(:,2),(1:size(c.Rows,1))',[c.Source.nt 1],@(indices) {indices},{[]});
                obj.IndexedRows=c.Rows;
            end
            rows=c.Rows(obj.FrameIndices{c.Frame.Value},:); candidates=c.Candidates(c.Candidates(:,2)==c.Frame.Value,:);
            obj.ListRows=[rows,zeros(size(rows,1),1);candidates,ones(size(candidates,1),1)];
            count = size(obj.ListRows,1);
            obj.Summary.Text = sprintf('%d neurons · %d candidates',nnz(obj.ListRows(:,8)==0),nnz(obj.ListRows(:,8)==1));
            if ~any(obj.ListRows(:,8)), obj.Summary.Text=sprintf('%d neurons',count); end
            if count==0
                obj.NeuronList.Items = {}; obj.NeuronList.ItemsData = []; obj.Selection = [];
            else
                labels = cell(count,1);
                for i=1:count
                    kind = 'Neuron'; if obj.ListRows(i,8), kind = 'Candidate'; end
                    labels{i} = sprintf('%s %d   ·   Z %.1f',kind,obj.ListRows(i,1),obj.ListRows(i,5));
                    if ismember(obj.ListRows(i,[1 2]),c.Excluded,'rows'), labels{i}=sprintf('%s  [excluded]',labels{i}); end
                end
                index = [];
                if ~isempty(obj.Selection)
                    index = find(obj.ListRows(:,8)==obj.Selection(1) & obj.ListRows(:,1)==obj.Selection(2) & obj.ListRows(:,2)==obj.Selection(3),1);
                end
                if isempty(index), index=find(obj.ListRows(:,1)==obj.PreferredID,1); end
                if isempty(index) && any(c.Rows(:,1)==obj.PreferredID)
                    set(obj.NeuronList,'Items',labels,'ItemsData',1:count,'Value',1);
                    obj.Selection=[]; obj.ListKey=key; obj.setBusy(c.Busy); return;
                end
                if isempty(index), index=1; end
                row = obj.ListRows(index,:); obj.Selection = [row(8),row(1),row(2)]; obj.PreferredID=row(1);
                set(obj.NeuronList,'Items',labels,'ItemsData',1:count,'Value',index);
                for i=1:3, obj.Position{i}.Value = row(i+2); end
            end
            obj.ListKey = {c.Frame.Value,c.Channel.Value,c.Rows,c.Candidates,obj.Selection,c.Excluded};
            c.Buttons.remove.Text='Delete track';
            if ~isempty(obj.Selection) && obj.Selection(1), c.Buttons.remove.Text='Delete candidate'; end
            obj.Exclude.Value=~isempty(obj.Selection) && ismember(obj.Selection([2 3]),c.Excluded,'rows');
            obj.setBusy(c.Busy);
        end
        function setBusy(obj,busy)
            obj.Controller.Buttons.cancel.Visible=matlab.lang.OnOffSwitchState(busy);
            obj.Contrast.setBusy(busy); obj.Playback.setBusy(busy);
            if ~isempty(obj.Review) && ~isempty(obj.Review.Confirm)
                obj.Review.Confirm.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(obj.Selection) && ~obj.Selection(1));
                obj.Review.Undo.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(obj.Review.Snapshots));
            end
            for i=1:5, obj.Stages{i}.Enable=matlab.lang.OnOffSwitchState(~busy); end
            handles={obj.DisplayMode,obj.Follow,obj.Trails,obj.XYZ};
            for i=1:numel(handles), handles{i}.Enable=matlab.lang.OnOffSwitchState(~busy); end
            state = matlab.lang.OnOffSwitchState(~busy);
            obj.Labels.Enable = state; obj.LabelMode.Enable=state; obj.ShowROI.Enable=state; obj.NeuronList.Enable = state;
            obj.Exclude.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(obj.Selection) && ~obj.Selection(1));
            obj.SliceValue.Enable = matlab.lang.OnOffSwitchState(~busy && obj.Controller.Source.nz>1);
            for i=1:3
                obj.Position{i}.Enable = matlab.lang.OnOffSwitchState(~isempty(obj.Selection) && ~busy);
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
            c = obj.Controller; obj.Playback.stop(); obj.Selection = [pending,row(1),row(2)]; obj.PreferredID=row(1);
            c.Frame.Value = row(2); if pending, c.Channel.Value = row(7); end; c.Slice.Value = min(c.Source.nz,max(1,round(row(5))));
            c.safe(@() c.render());
        end
        function markerClick(obj,ax,~,~)
            c=obj.Controller; if c.Busy, return; end
            rows=obj.ListRows;
            if isequal(ax,c.Axes), rows=rows(abs(rows(:,5)-obj.SliceValue.Value)<obj.sliceRadius(),:); end
            if isempty(rows), return; end
            point=ax.CurrentPoint; distance=sum((rows(:,3:4)-point(1,1:2)).^2,2);
            nearby=find(distance<=min(distance)+4); index=nearby(1);
            if numel(nearby)>1
                current=find(rows(nearby,1)==obj.PreferredID,1);
                if ~isempty(current), index=nearby(mod(current,numel(nearby))+1); end
            end
            obj.select(rows(index,:),rows(index,8));
        end
        function armAdd(obj)
            if obj.Controller.Busy, return; end
            obj.Playback.stop(); obj.CorrectMode=false; obj.DisplayMode.Value='Slice'; obj.redraw();
            obj.AddMode = ~obj.AddMode;
            if obj.AddMode, obj.Controller.Buttons.add.Text = 'Click image…';
            else, obj.Controller.Buttons.add.Text = 'Add neuron'; end
        end
        function imageClick(obj,ax)
            c = obj.Controller; if c.Busy, return; end
            if obj.AddMode && ~isequal(ax,c.Axes), return; end
            obj.Playback.stop(); c.Cursor = ax.CurrentPoint;
            if obj.CorrectMode && isequal(ax,c.Axes) && ~isempty(obj.Selection)
                obj.correctAt([c.Cursor(1,1:2),round(c.Slice.Value)]);
                return;
            end
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
            obj.Review.checkpoint();
            rows(index,dimension+2) = value; rows(index,6)=1;
            if pending, c.Candidates=rows;
            else
                c.Rows=rows; c.Origins(sprintf('%d:%d',rows(index,1),rows(index,2)))='reviewed';
            end
            if dimension==3, c.Slice.Value=round(value); end
            obj.redraw();
        end
        function removeSelection(obj)
            c=obj.Controller; if isempty(obj.Selection), return; end
            obj.Review.checkpoint();
            identity=obj.Selection(2); pending=obj.Selection(1);
            selected=obj.ListRows(:,1)==identity & obj.ListRows(:,8)==pending;
            position=find(selected,1); remaining=obj.ListRows(~selected,:);
            if isempty(position), position=1; end
            if ~isempty(remaining), obj.PreferredID=remaining(min(position,size(remaining,1)),1); end
            if pending
                c.Candidates(c.Candidates(:,1)==identity,:)=[];
            else
                c.Rows(c.Rows(:,1)==identity,:)=[]; c.Excluded(c.Excluded(:,1)==identity,:)=[];
                keys=c.Origins.keys; keys=keys(startsWith(keys,sprintf('%d:',identity)));
                if ~isempty(keys), remove(c.Origins,keys); end
            end
            obj.Selection=[]; c.render();
        end
    end
end
