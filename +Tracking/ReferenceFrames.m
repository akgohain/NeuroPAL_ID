classdef ReferenceFrames
    %REFERENCEFRAMES Choose representative frames before annotating a recording.
    methods (Static)
        function open(c)
            if c.Busy, return; end
            c.View.Playback.stop();
            window=getappdata(c.Grid,'reference_frames_window');
            if ~isempty(window) && isvalid(window)
                response=getappdata(c.Grid,'reference_frame_recommendations');
                if ~isempty(response), Tracking.ReferenceFrames.populate(c,response); end
                window.Visible='on'; figure(window); return;
            end
            window=uifigure('Name','Reference frames','Position',[300 300 390 440]);
            window.CloseRequestFcn=@(src,~) set(src,'Visible','off');
            grid=uigridlayout(window,[6 2]); grid.Padding=[14 12 14 12]; grid.RowHeight={28,28,32,'1x',38,32};
            grid.ColumnWidth={95,'1x'};
            uilabel(grid,'Text','Channel');
            channel=uidropdown(grid,'Items',cellstr("C"+string(0:c.Source.nc-1)), ...
                'ItemsData',0:c.Source.nc-1,'Value',c.DetectionChannel.Value, ...
                'ValueChangedFcn',@(~,~) Tracking.ReferenceFrames.parametersChanged(c));
            uilabel(grid,'Text','Suggestions'); count=uispinner(grid,'Limits',[1 max(2,min(20,c.Source.nt))],'Value',min(5,c.Source.nt));
            run=uibutton(grid,'Text','Recommend frames','ButtonPushedFcn',@(~,~) Tracking.ReferenceFrames.run(c)); run.Layout.Column=[1 2];
            run.Tooltip='Compares at most 128 uniformly sampled frames. This appearance heuristic does not inspect every frame or establish neuron visibility or identity.';
            list=uilistbox(grid,'Items',{},'ItemsData',[]); list.Layout.Column=[1 2];
            status=uilabel(grid,'Text','','WordWrap','on'); status.Layout.Column=[1 2];
            use=uibutton(grid,'Text','Open selected frame','ButtonPushedFcn',@(~,~) Tracking.ReferenceFrames.use(c)); use.Layout.Column=[1 2];
            controls=struct('window',window,'channel',channel,'count',count,'run',run,'list',list,'status',status,'use',use);
            setappdata(c.Grid,'reference_frames_window',window); setappdata(c.Grid,'reference_frames_controls',controls);
            response=getappdata(c.Grid,'reference_frame_recommendations');
            if isempty(response) && isfield(c.Source,'metadata')
                names=fieldnames(c.Source.metadata);
                name=names(startsWith(names,'t_ref_fn'));
                exact=sprintf('t_ref_fn%d',c.Source.nt);
                if isfield(c.Source.metadata,exact), name=[{exact};name(~strcmp(name,exact))]; end
                if ~isempty(name)
                    frames=c.Source.metadata.(name{1});
                    if isnumeric(frames) && isvector(frames) && all(isfinite(frames(:))) && all(frames(:)==round(frames(:))) && all(frames(:)>=0 & frames(:)<c.Source.nt)
                        response=struct('frames',frames(:)','channel',c.DetectionChannel.Value,'method','source_metadata', ...
                            'source_id',c.Source.source_id,'frame_index_base',0);
                    end
                end
            end
            if ~isempty(response), Tracking.ReferenceFrames.populate(c,response); end
            controls.status.Text='Detect one reference first. Match later frames to those same neurons.';
            Tracking.ReferenceFrames.setBusy(c,false);
        end
        function run(c)
            controls=getappdata(c.Grid,'reference_frames_controls');
            c.safe(@() Tracking.ReferenceFrames.calculate(c,controls.channel.Value,controls.count.Value));
        end
        function calculate(c,channel,count)
            controls=getappdata(c.Grid,'reference_frames_controls');
            response=c.bridge(struct('action','recommend_frames','source',c.Source,'channel',channel,'count',count), ...
                @() c.Cancelled || ~isvalid(c.App),@(message) c.progress(message));
            Tracking.ReferenceFrames.populate(c,response);
            controls.status.Text='Detect one reference first. Match later frames to those same neurons.';
        end
        function response = validate(c,response)
            if ~isstruct(response) || ~isscalar(response) || ~isfield(response,'frames') || ~isfield(response,'channel')
                error('Tracking:ReferenceFrames','Recommendations must contain frame indices and a channel.');
            end
            if isfield(response,'source_id') && ~strcmp(response.source_id,c.Source.source_id)
                error('Tracking:ReferenceFrames','Recommendations belong to a different recording.');
            end
            if isfield(response,'frame_index_base') && ~isequal(response.frame_index_base,0)
                error('Tracking:ReferenceFrames','Recommendation frame indices must use the zero-based source convention.');
            end
            if ~isnumeric(response.channel) || ~isscalar(response.channel) || ~isfinite(response.channel) || response.channel~=round(response.channel) || response.channel<0 || response.channel>=c.Source.nc
                error('Tracking:ReferenceFrames','Recommendations contain an invalid channel.');
            end
            if ~isnumeric(response.frames) || (~isempty(response.frames) && ~isvector(response.frames))
                error('Tracking:ReferenceFrames','Recommendation frame indices must be a numeric vector.');
            end
            frames=double(response.frames(:)')+1;
            if any(~isfinite(frames) | frames~=round(frames) | frames<1 | frames>c.Source.nt)
                error('Tracking:ReferenceFrames','Recommendations contain invalid frame indices.');
            end
            response.frames=unique(frames-1,'stable'); response.frame_index_base=0;
            response.source_id=c.Source.source_id;
        end
        function restore(c,response)
            if isempty(response)
                setappdata(c.Grid,'reference_frame_recommendations',[]); Tracking.ReferenceFrames.refresh(c); return;
            end
            response=Tracking.ReferenceFrames.validate(c,response);
            setappdata(c.Grid,'reference_frame_recommendations',response);
            Tracking.ReferenceFrames.refresh(c);
        end
        function populate(c,response)
            response=Tracking.ReferenceFrames.validate(c,response);
            setappdata(c.Grid,'reference_frame_recommendations',response);
            Tracking.ReferenceFrames.refresh(c);
        end
        function refresh(c)
            controls=getappdata(c.Grid,'reference_frames_controls');
            if isempty(controls) || ~isvalid(controls.window), return; end
            response=getappdata(c.Grid,'reference_frame_recommendations');
            if isempty(response)
                controls.list.Items={}; controls.list.ItemsData=[]; Tracking.ReferenceFrames.setBusy(c,c.Busy); return;
            end
            frames=double(response.frames(:)')+1; previous=controls.list.Value;
            labels=cell(1,numel(frames));
            for i=1:numel(frames)
                indices=find(c.Rows(:,2)==frames(i)); count=0;
                for row=indices(:)'
                    key=sprintf('%d:%d',c.Rows(row,1),frames(i));
                    if ~isKey(c.Origins,key) || ~strcmp(c.Origins(key),'zephir'), count=count+1; end
                end
                labels{i}=sprintf('Frame %d',frames(i));
                if count==1, labels{i}=sprintf('%s · 1 reference center',labels{i});
                elseif count>1, labels{i}=sprintf('%s · %d reference centers',labels{i},count); end
            end
            controls.list.Items=labels; controls.list.ItemsData=frames;
            if isnumeric(previous) && isscalar(previous) && ismember(previous,frames), controls.list.Value=previous;
            elseif ~isempty(frames), controls.list.Value=frames(1); end
            controls.channel.Value=response.channel;
            Tracking.ReferenceFrames.setBusy(c,c.Busy);
        end
        function use(c)
            if c.Busy, return; end
            controls=getappdata(c.Grid,'reference_frames_controls');
            if isempty(controls.list.Value), return; end
            response=getappdata(c.Grid,'reference_frame_recommendations');
            if isempty(response), Tracking.ReferenceFrames.refresh(c); return; end
            try
                response=Tracking.ReferenceFrames.validate(c,response);
                if controls.channel.Value~=response.channel
                    Tracking.ReferenceFrames.parametersChanged(c); return;
                end
                c.Channel.Value=response.channel; c.DetectionChannel.Value=response.channel;
                c.View.navigate(controls.list.Value);
                if c.Frame.Value~=controls.list.Value || c.CacheFrame~=controls.list.Value, return; end
                c.View.setStage(2); controls.window.Visible='off';
            catch ME
                uialert(controls.window,ME.message,'Open reference frame');
            end
        end
        function parametersChanged(c)
            controls=getappdata(c.Grid,'reference_frames_controls');
            if isempty(controls), return; end
            controls.list.Items={}; controls.list.ItemsData=[]; controls.use.Enable='off';
            controls.status.Text='Recommend frames for the selected channel before opening one.';
        end
        function setBusy(c,busy)
            controls=getappdata(c.Grid,'reference_frames_controls');
            if isempty(controls), return; end
            for name={'channel','count','run','list'}, controls.(name{1}).Enable=matlab.lang.OnOffSwitchState(~busy); end
            if c.Source.nt==1, controls.count.Enable='off'; end
            controls.use.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(controls.list.Items));
        end
    end
end
