classdef NeuroPALReference < handle
    %NEUROPALREFERENCE Detect, identify and align a paired structural volume.
    properties
        Controller
        Window
        Volume
        Axes
        VideoAxes
        Table
        Status
        Detector
        IDProfile
        ReferenceChannel
        VideoChannel
        Frame
        ScaleMode
        Buttons
        Positions = zeros(0,3)
        Scores = []
        Names = strings(0,1)
        Confidence = []
        NameSources = strings(0,1)
        Alignment = []
        Detection = []
        Predictions = []
        Applied = false
        Selected = 1
        IdentityModel = []
    end
    methods (Static)
        function open(c)
            previous=getappdata(c.Grid,'paired_reference_controller');
            if ~isempty(previous) && isvalid(previous), figure(previous.Window); return; end
            reference=Tracking.NeuroPALReference(c);
            setappdata(c.Grid,'paired_reference_controller',reference);
        end
    end
    methods
        function obj = NeuroPALReference(c)
            obj.Controller=c; reference=c.Source.neuropal;
            dims=double(reference.dimensions_xyzc(:)'); channels=double(reference.rgbw_channels(:)');
            if numel(channels)~=4 || numel(unique(channels))~=4 || any(channels<0 | channels>=dims(4))
                error('Tracking:ReferenceChannels','The NWB must provide four distinct RGBW channel indices.');
            end
            if isempty(reference.spacing_um_xyz), error('Tracking:ReferenceSpacing','The NeuroPAL volume needs measured voxel spacing.'); end
            if prod(dims(1:3))*4*reference.itemsize>256*2^20, error('Tracking:ReferenceSize','The NeuroPAL reference exceeds the 256 MiB volume limit.'); end
            obj.Volume=zeros(dims(2),dims(1),dims(3),4,reference.dtype);
            for i=1:4
                if strcmp(reference.axis_order,'CZXY')
                    obj.Volume(:,:,:,i)=h5read(c.Source.file,reference.data_path,[1 1 1 channels(i)+1],[dims(2) dims(1) dims(3) 1]);
                else
                    raw=h5read(c.Source.file,reference.data_path,[channels(i)+1 1 1 1],[1 dims(3) dims(2) dims(1)]);
                    obj.Volume(:,:,:,i)=permute(reshape(raw,[dims(3) dims(2) dims(1)]),[2 3 1]);
                end
            end
            obj.Window=uifigure('Name','NeuroPAL reference','Position',[100 100 1050 680], ...
                'CloseRequestFcn',@(~,~) obj.close());
            grid=uigridlayout(obj.Window,[5 1]); grid.RowHeight={32,30,'1x',170,24}; grid.ColumnWidth={'1x'};
            bar=uigridlayout(grid,[1 8]); bar.Layout.Row=1; bar.Padding=[0 0 0 0]; bar.ColumnWidth={90,'1x',60,85,'1x','1x','1x',60};
            obj.Detector=uidropdown(bar,'Items',{'MoE','Spotiflow'});
            obj.Buttons.detect=uibutton(bar,'Text','Auto Detect','ButtonPushedFcn',@(~,~) c.safe(@() obj.detect()));
            uilabel(bar,'Text','ID profile');
            profiles={'Choose','000541','000692','000714','000715','000981'};
            obj.IDProfile=uidropdown(bar,'Items',profiles,'Tooltip','DANDI cohort used by the Auto-ID preprocessing adapter.');
            for i=2:numel(profiles)
                if contains(c.Source.file,[filesep profiles{i} filesep]), obj.IDProfile.Value=profiles{i}; break; end
            end
            obj.Buttons.identify=uibutton(bar,'Text','Auto ID','ButtonPushedFcn',@(~,~) c.safe(@() obj.identify()));
            obj.Buttons.align=uibutton(bar,'Text','Align to video','ButtonPushedFcn',@(~,~) c.safe(@() obj.align()));
            obj.Buttons.use=uibutton(bar,'Text','Use aligned seeds','ButtonPushedFcn',@(~,~) obj.use());
            obj.Buttons.cancel=uibutton(bar,'Text','Cancel','Enable','off','ButtonPushedFcn',@(~,~) c.cancel());
            settings=uigridlayout(grid,[1 8]); settings.Layout.Row=2; settings.Padding=[0 0 0 0];
            settings.ColumnWidth={110,65,90,65,45,75,60,'1x'};
            uilabel(settings,'Text','Reference channel'); obj.ReferenceChannel=uidropdown(settings,'Items',cellstr("C"+string(0:dims(4)-1)),'ItemsData',0:dims(4)-1,'Value',0);
            uilabel(settings,'Text','Video channel'); obj.VideoChannel=uidropdown(settings,'Items',cellstr("C"+string(0:c.Source.nc-1)),'ItemsData',0:c.Source.nc-1,'Value',c.Channel.Value);
            uilabel(settings,'Text','Frame'); obj.Frame=uispinner(settings,'Limits',[1 max(2,c.Source.nt)],'Value',c.Frame.Value,'RoundFractionalValues','on');
            uilabel(settings,'Text','Scaling'); obj.ScaleMode=uidropdown(settings,'Items',{'Fit image extents','Use voxel spacing'},'ItemsData',{'extent','physical'},'Value','extent');
            controls={obj.ReferenceChannel,obj.VideoChannel,obj.Frame,obj.ScaleMode};
            for i=1:numel(controls), controls{i}.ValueChangedFcn=@(~,~) obj.invalidateAlignment(); end
            previews=uigridlayout(grid,[1 2]); previews.Layout.Row=3; previews.Padding=[0 0 0 0]; previews.ColumnWidth={'1x','1x'};
            obj.Axes=uiaxes(previews); obj.Axes.Layout.Column=1; obj.Axes.Toolbar.Visible='off';
            obj.VideoAxes=uiaxes(previews); obj.VideoAxes.Layout.Column=2; obj.VideoAxes.Toolbar.Visible='off';
            obj.Table=uitable(grid,'ColumnName',{'#','Name','ID confidence','X','Y','Z'}, ...
                'ColumnEditable',[false true false false false false],'RowName',{},'CellEditCallback',@(~,event) obj.rename(event),'CellSelectionCallback',@(~,event) obj.select(event));
            obj.Table.Layout.Row=4; obj.Table.ColumnFormat={'numeric','char','short','short','short','short'};
            footer=uigridlayout(grid,[1 2]); footer.Layout.Row=5; footer.Padding=[0 0 0 0]; footer.ColumnWidth={'1x',130};
            obj.Status=uilabel(footer,'Text','');
            obj.Buttons.remove=uibutton(footer,'Text','Remove neuron','ButtonPushedFcn',@(~,~) obj.remove());
            obj.render();
        end
        function close(obj)
            if obj.Controller.Busy, return; end
            delete(obj);
        end
        function delete(obj)
            if ~isempty(obj.Window) && isvalid(obj.Window), delete(obj.Window); end
            if isvalid(obj.Controller.Grid) && isappdata(obj.Controller.Grid,'paired_reference_controller')
                rmappdata(obj.Controller.Grid,'paired_reference_controller');
            end
            obj.Volume=[];
        end
        function invalidateAlignment(obj)
            if obj.Controller.Busy, return; end
            obj.Alignment=[]; obj.render();
        end
        function setBusy(obj,busy)
            handles=[{obj.Detector,obj.IDProfile,obj.ReferenceChannel,obj.VideoChannel,obj.Frame,obj.ScaleMode,obj.Table},struct2cell(obj.Buttons)'];
            state='on'; if busy, state='off'; end
            for i=1:numel(handles), handles{i}.Enable=state; end
            if isfield(obj.Buttons,'remove'), obj.Buttons.remove.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(obj.Positions)); end
            obj.Buttons.cancel.Enable=matlab.lang.OnOffSwitchState(busy);
            obj.Buttons.identify.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(obj.Positions));
            obj.Buttons.use.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(obj.Positions) && ~isempty(obj.Alignment));
        end
        function detect(obj)
            c=obj.Controller; ref=c.Source.neuropal;
            response=Wrapper.runReferenceCentroids(obj.Volume,double(ref.spacing_um_xyz(:)'), ...
                'Backend',lower(obj.Detector.Value), ...
                'OutputDir',fullfile(c.OutputRoot,'neuropal-detection'), ...
                'CancelFcn',@() c.Cancelled,'ProgressFcn',@(message) obj.progress(message));
            if response.num_centroids==0, obj.Status.Text='No neurons detected. Previous reference results were kept.'; return; end
            obj.Positions=response.centroids_yxz(:,[2 1 3]); obj.Scores=response.scores(:);
            obj.Names=strings(size(obj.Scores)); obj.Confidence=zeros(size(obj.Scores)); obj.NameSources=repmat("unnamed",size(obj.Scores));
            obj.Detection=response; obj.Predictions=[]; obj.IdentityModel=[]; obj.Selected=1; obj.render();
        end
        function identify(obj)
            if isempty(obj.Positions), error('Tracking:ReferenceSeeds','Run Auto Detect on the NeuroPAL reference first.'); end
            c=obj.Controller; ref=c.Source.neuropal;
            profile=char(obj.IDProfile.Value);
            if strcmp(profile,'Choose'), error('Tracking:ReferenceProfile','Choose the recording''s DANDI cohort in ID profile before running Auto ID.'); end
            [repo,checkpoint]=Wrapper.resolveTransformerAssets();
            [~,output_name]=fileparts(tempname);
            predictions=Wrapper.runTransformerAutoIDFromVolume(obj.Volume,obj.Positions(:,[2 1 3]),double(ref.spacing_um_xyz(:)'), ...
                'Labels',strings(0,1),'DatasetID',profile,'Device','cpu','OutputName',[output_name '.csv'], ...
                'CancelFcn',@() c.Cancelled,'ProgressFcn',@(message) obj.progress(message));
            [predictions,names,confidence,sources]=Tracking.referenceIdentityResults(predictions,size(obj.Positions,1));
            obj.Names=names; obj.Confidence=confidence; obj.NameSources=sources;
            obj.Predictions=predictions;
            obj.IdentityModel=struct('repository',repo,'checkpoint',checkpoint,'mc_samples',20,'dataset_id',profile, ...
                'predictions',table2struct(predictions),'input_positions_xyz',obj.Positions,'labels_supplied',false);
            obj.render(); obj.Status.Text=sprintf('%d ID suggestions · %d unnamed',nnz(strlength(names)>0),nnz(strlength(names)==0));
        end
        function align(obj)
            c=obj.Controller;
            alignment=c.bridge(struct('action','align_neuropal','source',c.Source,'reference_channel',obj.ReferenceChannel.Value, ...
                'channel',obj.VideoChannel.Value,'frame_index',obj.Frame.Value-1,'scale_mode',obj.ScaleMode.Value),@() c.Cancelled);
            obj.Alignment=alignment; obj.render();
            obj.Status.Text=sprintf('Image alignment correlation: %.3f. Inspect the centers on the video before using them.',alignment.correlation);
        end
        function xyz = mapped(obj)
            if isempty(obj.Alignment), xyz=zeros(0,3); return; end
            xyz=(obj.Positions-1).*double(obj.Alignment.scale_xyz(:)')+1+double(obj.Alignment.shift_xyz(:)');
        end
        function rename(obj,event)
            if obj.Controller.Busy, return; end
            name=strtrim(string(event.NewData));
            if strlength(name)>64, obj.render(); uialert(obj.Window,'Use a neuron name of at most 64 characters.','Neuron name'); return; end
            obj.Names(event.Indices(1))=name; obj.NameSources(event.Indices(1))="reviewed"; obj.Confidence(event.Indices(1))=1;
        end
        function select(obj,event)
            if obj.Controller.Busy || isempty(event.Indices), return; end
            obj.Selected=event.Indices(1,1); obj.render();
        end
        function remove(obj)
            if obj.Controller.Busy || isempty(obj.Positions), return; end
            index=min(obj.Selected,size(obj.Positions,1));
            obj.Positions(index,:)=[]; obj.Scores(index)=[]; obj.Names(index)=[];
            obj.Confidence(index)=[]; obj.NameSources(index)=[];
            obj.Selected=max(1,min(index,size(obj.Positions,1))); obj.render();
        end
        function use(obj)
            c=obj.Controller; if c.Busy, return; end
            obj.Applied=false; c.safe(@() obj.apply());
            if obj.Applied, c.View.setStage(3); delete(obj); end
        end
        function apply(obj)
            c=obj.Controller;
            if ~isempty(c.Rows) || ~isempty(c.Candidates), error('Tracking:ExistingSeeds','Save or reset the current tracking session before using another reference seed set.'); end
            if isempty(obj.Positions), error('Tracking:ReferenceSeeds','Detect reference neurons first.'); end
            if isempty(obj.Alignment) || obj.Alignment.correlation<.15, error('Tracking:ReferenceAlignment','Align the reference and inspect the video centers first.'); end
            if obj.Alignment.frame_index~=obj.Frame.Value-1 || obj.Alignment.channel~=obj.VideoChannel.Value || ...
                    obj.Alignment.reference_channel~=obj.ReferenceChannel.Value || ~strcmp(obj.Alignment.scale_mode,obj.ScaleMode.Value) || ...
                    ~strcmp(obj.Alignment.source_id,c.Source.source_id)
                error('Tracking:ReferenceAlignment','The reference frame or channel changed. Align again before using the seeds.');
            end
            xyz=obj.mapped(); bounds=[c.Source.nx c.Source.ny c.Source.nz];
            inside=all(xyz>=.5 & xyz<=bounds+.5,2);
            if ~all(inside), error('Tracking:ReferenceBounds','%d reference centers lie outside the video. Adjust alignment before using the seeds.',nnz(~inside)); end
            ids=(c.NextID:c.NextID+size(xyz,1)-1)'; frame=obj.Frame.Value;
            records=struct('id',{},'name',{},'confidence',{},'source',{});
            for i=1:numel(ids), records(i)=struct('id',ids(i),'name',char(obj.Names(i)),'confidence',obj.Confidence(i),'source',char(obj.NameSources(i))); end
            Tracking.NeuronNames.set(c,records);
            c.Rows=[ids,repmat(frame,numel(ids),1),xyz,obj.Scores,repmat(obj.VideoChannel.Value,numel(ids),1)]; c.NextID=ids(end)+1;
            provenance=struct('source_id',c.Source.source_id,'reference',c.Source.neuropal,'alignment',obj.Alignment, ...
                'positions_xyz',obj.Positions,'detection',obj.Detection,'auto_id',obj.IdentityModel,'names',records,'model_predictions_are_provisional',true);
            setappdata(c.Grid,'paired_reference_provenance',provenance); c.History{end+1}=provenance;
            c.Reference.Value=frame; c.Frame.Value=frame; c.Channel.Value=obj.VideoChannel.Value;
            c.First.Value=1; c.Last.Value=c.Source.nt; c.render(); obj.Applied=true;
        end
        function progress(obj,message)
            obj.Status.Text=char(message); obj.Controller.Status.Text=char(message);
        end
        function render(obj)
            rgb=reshape(single(max(obj.Volume(:,:,:,1:3),[],3)),size(obj.Volume,1),size(obj.Volume,2),3);
            for i=1:3
                plane=rgb(:,:,i); values=plane(plane>0); ceiling=1;
                if ~isempty(values), ceiling=max(1,prctile(values,99.5)); end
                rgb(:,:,i)=min(1,plane/ceiling);
            end
            hold(obj.Axes,'off'); image(obj.Axes,rgb); axis(obj.Axes,'image'); title(obj.Axes,'NeuroPAL'); hold(obj.Axes,'on');
            if ~isempty(obj.Positions), scatter(obj.Axes,obj.Positions(:,1),obj.Positions(:,2),10,'w'); end
            c=obj.Controller; pixels=c.Reader.read(obj.Frame.Value); plane=max(pixels(:,:,:,obj.VideoChannel.Value+1),[],3);
            hold(obj.VideoAxes,'off'); imagesc(obj.VideoAxes,plane); colormap(obj.VideoAxes,gray); axis(obj.VideoAxes,'image'); title(obj.VideoAxes,sprintf('Video · frame %d',obj.Frame.Value));
            hold(obj.VideoAxes,'on'); xyz=obj.mapped(); if ~isempty(xyz), scatter(obj.VideoAxes,xyz(:,1),xyz(:,2),10,'r'); end
            n=size(obj.Positions,1);
            if n>0
                index=min(obj.Selected,n); point=obj.Positions(index,:);
                scatter(obj.Axes,point(1),point(2),70,'y','LineWidth',1.5);
                label=sprintf('#%d',index);
                if strlength(obj.Names(index))>0, label=sprintf('%s · #%d',obj.Names(index),index); end
                if obj.NameSources(index)=="auto-id", label=[label '?']; end
                text(obj.Axes,point(1)+10,point(2),label,'Color','y','Interpreter','none');
                if ~isempty(xyz), scatter(obj.VideoAxes,xyz(index,1),xyz(index,2),70,'y','LineWidth',1.5); end
            end
            if isfield(obj.Buttons,'remove'), obj.Buttons.remove.Enable=matlab.lang.OnOffSwitchState(n>0 && ~c.Busy); end
            obj.Table.Data=[num2cell((1:n)') cellstr(obj.Names) num2cell(obj.Confidence) num2cell(obj.Positions)];
            obj.Buttons.identify.Enable=matlab.lang.OnOffSwitchState(n>0);
            obj.Buttons.use.Enable=matlab.lang.OnOffSwitchState(n>0 && ~isempty(obj.Alignment));
        end
    end
end
