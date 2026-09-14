classdef ReferenceWorkflow < handle
    %REFERENCEWORKFLOW Detect and review reference neurons in a calcium recording.
    properties
        App
        Source
        Grid
        Frame
        Slice
        Channel
        Detector
        Spacing
        Calibration
        Status
        Axes
        Table
        Buttons
        First
        Last
        Rows = zeros(0, 7)
        Candidates = zeros(0, 7)
        CandidateFrame = 0
        NextID = 1
        Cache = []
        CacheFrame = 0
        Busy = false
        Cancelled = false
        Provenance = struct()
        History = {}
        Cursor = []
        OutputRoot
        CloseCallback
        Origins
    end
    methods (Static)
        function yes = supports(path)
            [~,~,ext] = fileparts(path);
            yes = false;
            if ~any(strcmpi(ext, {'.h5','.hdf5'})), return; end
            try
                info = h5info(path, '/data');
                yes = numel(info.Dataspace.Size) == 5;
            catch
            end
        end
        function workflow = open(app, path)
            Program.HeavyJob.assertIdle();
            info = Tracking.ReferenceWorkflow.bridge(struct('action','inspect','file',char(path)));
            key = 'calcium_reference_workflow';
            if isappdata(app.CELL_ID,key)
                previous = getappdata(app.CELL_ID,key);
                if isvalid(previous) && ~isempty(previous.Rows)
                    answer = uiconfirm(app.CELL_ID,'Close the current reference session? Save seeds first to retain edits.', ...
                        'Open recording','Options',{'Cancel','Close session'},'DefaultOption','Cancel','CancelOption','Cancel');
                    if strcmp(answer,'Cancel'), workflow = previous; return; end
                end
                delete(previous);
            end
            workflow = Tracking.ReferenceWorkflow(app, info);
            setappdata(app.CELL_ID,key,workflow);
        end
        function python = python()
            python = getenv('NEUROPAL_VIDEO_PYTHON');
            if isempty(python), python = getenv('NEUROPAL_YOLO_PYTHON'); end
            if isempty(python)
                root = fileparts(fileparts(mfilename('fullpath')));
                candidate = fullfile(fileparts(root),'.venv-ai-pipeline','bin','python');
                if isfile(candidate), python = candidate; end
            end
            if isempty(python) || ~isfile(python)
                error('Tracking:PythonMissing','Set NEUROPAL_VIDEO_PYTHON to the ZephIR Python environment.');
            end
        end
        function response = bridge(request, cancel)
            if nargin < 2, cancel = @() false; end
            folder = tempname; mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder,'s'));
            input = fullfile(folder,'request.json'); output = fullfile(folder,'response.json');
            fid = fopen(input,'w'); guard = onCleanup(@() fclose(fid));
            fwrite(fid,jsonencode(request),'char'); clear guard
            root = fileparts(fileparts(mfilename('fullpath')));
            [status, detail] = Wrapper.runPythonProcess( ...
                {Tracking.ReferenceWorkflow.python(),'-u',fullfile(root,'+Wrapper','reference_video.py'), ...
                '--request',input,'--response',output},'CancelFcn',cancel,'TimeoutSeconds',3600);
            if status ~= 0, error('Tracking:ReferenceFailed','%s',detail); end
            response = jsondecode(fileread(output));
        end
    end
    methods
        function obj = ReferenceWorkflow(app, info)
            obj.App = app; obj.Source = info;
            obj.Origins = containers.Map('KeyType','char','ValueType','char');
            obj.CloseCallback = app.CELL_ID.CloseRequestFcn;
            app.CELL_ID.CloseRequestFcn = @(src,event) obj.closeSession(src,event);
            obj.OutputRoot = fullfile(prefdir,'NeuroPAL','reference-jobs');
            app.VideoGridLayout.Visible = 'off';
            obj.Grid = uigridlayout(app.VideoTrackingTab,[4 2]);
            obj.Grid.ColumnWidth = {'1x',380}; obj.Grid.RowHeight = {60,'1x',150,28};
            controls = uigridlayout(obj.Grid,[1 6]); controls.Layout.Column = [1 2];
            controls.ColumnWidth = {60,90,40,'1x',70,120};
            uilabel(controls,'Text','Frame');
            obj.Frame = uispinner(controls,'Limits',[1 max(2,info.nt)],'Value',1,'Step',1, ...
                'ValueChangedFcn',@(~,~) obj.safe(@() obj.render()));
            uilabel(controls,'Text','Z');
            obj.Slice = uislider(controls,'Limits',[1 max(2,info.nz)],'Value',ceil(info.nz/2), ...
                'MajorTicks',unique(round(linspace(1,info.nz,min(5,info.nz)))), ...
                'MinorTicks',[],'ValueChangedFcn',@(~,~) obj.safe(@() obj.render()));
            uilabel(controls,'Text','Channel');
            obj.Channel = uidropdown(controls,'Items',cellstr("C"+string(0:info.nc-1)), ...
                'ItemsData',0:info.nc-1,'Value',0,'ValueChangedFcn',@(~,~) obj.safe(@() obj.render()));
            obj.Axes = uiaxes(obj.Grid); obj.Axes.Layout.Row = 2; obj.Axes.Layout.Column = 1;
            obj.Axes.Toolbar.Visible = 'off'; obj.Axes.ButtonDownFcn = @(~,~) obj.captureCursor(); colormap(obj.Axes,gray(256));
            panel = uigridlayout(obj.Grid,[12 2]); panel.Layout.Row = [2 3]; panel.Layout.Column = 2;
            panel.RowHeight = {28,28,28,28,28,28,28,28,28,28,28,'1x'};
            uilabel(panel,'Text','Detector'); obj.Detector = uidropdown(panel,'Items',{'MoE','Spotiflow'});
            uilabel(panel,'Text','Spacing X Y Z (µm)'); obj.Spacing = uieditfield(panel,'text','Value','0.4 0.4 1.5', ...
                'ValueChangedFcn',@(~,~) obj.spacingChanged());
            obj.Calibration = uicheckbox(panel,'Text','Use assumed spacing','Value',false); obj.Calibration.Layout.Column = [1 2];
            if info.spacing_measured
                obj.Spacing.Value = num2str(info.spacing_um_xyz(:)'); obj.Calibration.Text = 'Use measured spacing'; obj.Calibration.Value = true;
            end
            obj.Buttons.detect = uibutton(panel,'Text','Detect frame','ButtonPushedFcn',@(~,~) obj.safe(@() obj.detect()));
            obj.Buttons.cancel = uibutton(panel,'Text','Cancel','ButtonPushedFcn',@(~,~) obj.cancel());
            obj.Buttons.accept = uibutton(panel,'Text','Accept candidates','ButtonPushedFcn',@(~,~) obj.safe(@() obj.accept()));
            obj.Buttons.discard = uibutton(panel,'Text','Discard candidates','ButtonPushedFcn',@(~,~) obj.safe(@() obj.discard()));
            obj.Buttons.add = uibutton(panel,'Text','Add at last click','ButtonPushedFcn',@(~,~) obj.safe(@() obj.add()));
            obj.Buttons.remove = uibutton(panel,'Text','Delete selected','ButtonPushedFcn',@(~,~) obj.safe(@() obj.remove()));
            obj.Buttons.save = uibutton(panel,'Text','Save seeds…','ButtonPushedFcn',@(~,~) obj.safe(@() obj.saveDialog()));
            obj.Buttons.load = uibutton(panel,'Text','Load seeds…','ButtonPushedFcn',@(~,~) obj.safe(@() obj.loadDialog()));
            uilabel(panel,'Text','Track from frame'); obj.First = uispinner(panel,'Limits',[1 max(2,info.nt)],'Value',1);
            uilabel(panel,'Text','Through frame'); obj.Last = uispinner(panel,'Limits',[1 max(2,info.nt)],'Value',min(3,info.nt));
            obj.Buttons.track = uibutton(panel,'Text','Track window','ButtonPushedFcn',@(~,~) obj.safe(@() obj.track())); obj.Buttons.track.Layout.Column = [1 2];
            note = uilabel(panel,'Text','Review candidates before saving or tracking. Single-channel model accuracy is unvalidated.', 'WordWrap','on'); note.Layout.Column = [1 2];
            obj.Table = uitable(obj.Grid,'Data',obj.Rows,'ColumnName',{'ID','Frame','X','Y','Z','Score','Channel'}, ...
                'ColumnEditable',[false false true true true false false],'CellEditCallback',@(~,e) obj.safe(@() obj.edit(e)));
            obj.Table.Layout.Row = 3; obj.Table.Layout.Column = 1;
            obj.Status = uilabel(obj.Grid,'Text',''); obj.Status.Layout.Row = 4; obj.Status.Layout.Column = [1 2];
            app.VideoTrackingTab.Tag = 'rendered'; app.TabGroup.SelectedTab = app.VideoTrackingTab;
            obj.render();
            if info.nt==1, obj.Frame.Enable = 'off'; end
            if info.nz==1, obj.Slice.Enable = 'off'; end
        end
        function delete(obj)
            if ~isempty(obj.App) && isvalid(obj.App) && isvalid(obj.App.CELL_ID)
                obj.App.CELL_ID.CloseRequestFcn = obj.CloseCallback;
            end
            if ~isempty(obj.Grid) && isvalid(obj.Grid), delete(obj.Grid); end
        end
        function closeSession(obj,src,event)
            if obj.Busy
                obj.Cancelled = true;
                obj.Status.Text = 'Canceling the active job. Close again when it has stopped.';
                return;
            end
            if ~isempty(obj.Rows)
                answer = uiconfirm(obj.App.CELL_ID,'Close the reference session? Save seeds first to retain edits.', ...
                    'Close session','Options',{'Cancel','Close without saving'},'DefaultOption','Cancel','CancelOption','Cancel');
                if strcmp(answer,'Cancel'), return; end
            end
            callback = obj.CloseCallback;
            if iscell(callback), feval(callback{1},src,event,callback{2:end});
            elseif isa(callback,'function_handle'), callback(src,event);
            else, delete(obj.App);
            end
        end
        function safe(obj, action)
            if obj.Busy, return; end
            obj.Busy = true; obj.Cancelled = false;
            obj.Frame.Enable = 'off'; obj.Channel.Enable = 'off'; obj.Slice.Enable = 'off';
            obj.Table.Enable = 'off';
            obj.Detector.Enable = 'off'; obj.Spacing.Enable = 'off'; obj.Calibration.Enable = 'off';
            obj.First.Enable = 'off'; obj.Last.Enable = 'off';
            cleanup = onCleanup(@() obj.finish());
            try
                action();
            catch ME
                obj.Status.Text = ME.message;
                if ~contains(ME.identifier,'Cancelled')
                    uialert(obj.App.CELL_ID,ME.message,'Reference workflow');
                end
            end
        end
        function finish(obj)
            obj.Busy = false;
            if ~isvalid(obj.App) || ~isvalid(obj.Frame), return; end
            obj.Frame.Enable = 'on'; obj.Channel.Enable = 'on'; obj.Slice.Enable = 'on';
            obj.Table.Enable = 'on';
            obj.Detector.Enable = 'on'; obj.Spacing.Enable = 'on'; obj.Calibration.Enable = 'on';
            obj.First.Enable = 'on'; obj.Last.Enable = 'on';
            if obj.Source.nt==1, obj.Frame.Enable = 'off'; end
            if obj.Source.nz==1, obj.Slice.Enable = 'off'; end
        end
        function progress(obj,message)
            obj.Status.Text = char(message);
        end
        function cancel(obj)
            obj.Cancelled = true;
        end
        function volume = frameData(obj)
            t = round(obj.Frame.Value); obj.Frame.Value = min(obj.Source.nt,t);
            t = obj.Frame.Value;
            if t ~= obj.CacheFrame
                file = [tempname '.bin']; cleanup = onCleanup(@() obj.removeFile(file));
                response = obj.bridge(struct('action','frame','source',obj.Source,'frame_index',t-1,'output_raw',file),@() obj.Cancelled || ~isvalid(obj.App));
                fid = fopen(file,'r'); guard = onCleanup(@() fclose(fid));
                obj.Cache = reshape(fread(fid,prod(response.shape_yxzc),['*' response.dtype]),response.shape_yxzc(:)');
                obj.CacheFrame = t;
            end
            volume = obj.Cache(:,:,:,obj.Channel.Value+1);
        end
        function render(obj)
            volume = obj.frameData(); z = min(obj.Source.nz,round(obj.Slice.Value)); obj.Slice.Value = z;
            image = imagesc(obj.Axes,volume(:,:,z)); image.HitTest = 'off';
            axis(obj.Axes,'image'); obj.Axes.YDir = 'reverse';
            obj.Axes.XLim = [.5 obj.Source.nx+.5]; obj.Axes.YLim = [.5 obj.Source.ny+.5];
            xlabel(obj.Axes,'X (pixels)'); ylabel(obj.Axes,'Y (pixels)');
            title(obj.Axes,sprintf('Frame %d · C%d · Z %d',obj.Frame.Value,obj.Channel.Value,z));
            hold(obj.Axes,'on');
            obj.drawRows(obj.Rows,z,[.4 .9 .6]); obj.drawRows(obj.Candidates,z,[1 .7 .2]);
            hold(obj.Axes,'off'); obj.Table.Data = obj.Rows;
            obj.Status.Text = sprintf('%d accepted observations · %d candidates · %s',size(obj.Rows,1),size(obj.Candidates,1),obj.Source.file);
        end
        function drawRows(obj,rows,z,color)
            if isempty(rows), return; end
            keep = rows(:,2)==obj.Frame.Value & abs(rows(:,5)-z)<=1 & rows(:,7)==obj.Channel.Value;
            scatter(obj.Axes,rows(keep,3),rows(keep,4),55,color,'HitTest','off');
        end
        function spacingChanged(obj)
            obj.Calibration.Text = 'Use assumed spacing'; obj.Calibration.Value = false;
        end
        function detect(obj)
            if ~obj.Calibration.Value, error('Tracking:Spacing','Confirm measured or assumed voxel spacing before detection.'); end
            scale = sscanf(obj.Spacing.Value,'%f')';
            if numel(scale)~=3 || any(~isfinite(scale) | scale<=0), error('Tracking:Spacing','Enter three positive XYZ spacings.'); end
            actual = obj.bridge(struct('action','inspect','file',obj.Source.file));
            if ~strcmp(actual.source_id,obj.Source.source_id)
                error('Tracking:SourceChanged','Recording or metadata changed. Reopen the source before detection.');
            end
            volume = obj.frameData(); frame = obj.Frame.Value; channel = obj.Channel.Value;
            measured = obj.Source.spacing_measured && isequal(scale,obj.Source.spacing_um_xyz(:)');
            snapshot = struct('source_id',obj.Source.source_id,'frame_index',frame-1,'channel_index',channel, ...
                'spacing_measured',measured,'spacing_um_xyz',scale);
            obj.Status.Text = 'Detecting selected channel…'; drawnow;
            if ~any(volume(:)>0)
                response = struct('centroids_yxz',zeros(0,3),'scores',zeros(0,1),'num_centroids',0,'source_metadata',snapshot);
            else
                response = Wrapper.runMoECentroids(volume,scale,'InputMode','single_channel','SourceMetadata',snapshot, ...
                    'Backend',lower(string(obj.Detector.Value)),'ProgressFcn',@(message) obj.progress(message),'CancelFcn',@() obj.Cancelled || ~isvalid(obj.App),'OutputDir',obj.OutputRoot);
            end
            if obj.Frame.Value~=frame || obj.Channel.Value~=channel
                error('Tracking:StaleDetection','Frame or channel changed; run detection again.');
            end
            xyz = response.centroids_yxz(:,[2 1 3]);
            if any(xyz<1,'all') || any(xyz>[obj.Source.nx obj.Source.ny obj.Source.nz],'all')
                error('Tracking:Bounds','Detector returned a center outside pixel-center bounds.');
            end
            n = size(xyz,1);
            obj.Candidates = [(obj.NextID:obj.NextID+n-1)',repmat(frame,n,1),xyz,response.scores(:),repmat(channel,n,1)];
            obj.CandidateFrame = frame; obj.Provenance = response;
            obj.History{end+1} = response;
            obj.First.Value = frame; obj.Last.Value = min(obj.Source.nt,frame+2);
            obj.render();
        end
        function accept(obj)
            if isempty(obj.Candidates), return; end
            if obj.Frame.Value~=obj.CandidateFrame || any(obj.Candidates(:,7)~=obj.Channel.Value)
                error('Tracking:CandidateView','Return to the candidate frame and channel before accepting.');
            end
            if any(ismember(obj.Candidates(:,[2 7]),obj.Rows(:,[2 7]),'rows'))
                error('Tracking:ExistingSeeds','This frame/channel already has seeds. Delete those rows before accepting a replacement.');
            end
            obj.Rows = [obj.Rows;obj.Candidates]; obj.NextID = max(obj.Rows(:,1))+1;
            obj.Candidates = zeros(0,7); obj.render();
        end
        function discard(obj)
            obj.Candidates = zeros(0,7); obj.render();
        end
        function captureCursor(obj)
            if obj.Busy, return; end
            obj.Cursor = obj.Axes.CurrentPoint;
        end
        function add(obj)
            if isempty(obj.Cursor), error('Tracking:Cursor','Click a location in the image first.'); end
            point = obj.Cursor;
            xyz = [min(obj.Source.nx,max(1,point(1,1))),min(obj.Source.ny,max(1,point(1,2))),round(obj.Slice.Value)];
            obj.Rows(end+1,:) = [obj.NextID,obj.Frame.Value,xyz,1,obj.Channel.Value]; obj.NextID = obj.NextID+1; obj.render();
        end
        function remove(obj)
            selection = obj.Table.Selection;
            if isempty(selection), return; end
            obj.Rows(unique(selection(:,1)),:) = []; obj.render();
        end
        function edit(obj,event)
            row = event.Indices(1); column = event.Indices(2); value = event.NewData;
            if ischar(value) || isstring(value), value = str2double(value); end
            bounds = [obj.Source.nx obj.Source.ny obj.Source.nz];
            if ~isscalar(value) || ~isfinite(value) || value<1 || value>bounds(column-2)
                obj.Table.Data = obj.Rows; error('Tracking:EditBounds','Coordinates must lie inside the volume.');
            end
            obj.Origins(sprintf('%d:%d',obj.Rows(row,1),obj.Rows(row,2))) = 'reviewed';
            obj.Rows(row,column) = value; obj.Rows(row,6) = 1; obj.render();
        end
        function observations = observations(obj)
            observations = struct('track_id',{},'parent_id',{},'t',{},'x',{},'y',{},'z',{},'confidence',{},'provenance',{},'channel',{});
            for i=1:size(obj.Rows,1)
                r = obj.Rows(i,:); origin = 'reviewed';
                key = sprintf('%d:%d',r(1),r(2));
                if isKey(obj.Origins,key), origin = obj.Origins(key); end
                observations(i) = struct('track_id',r(1),'parent_id',0,'t',r(2),'x',r(3),'y',r(4),'z',r(5), ...
                    'confidence',r(6),'provenance',origin,'channel',r(7));
            end
        end
        function response = save(obj,folder)
            response = obj.bridge(struct('action','export','source',obj.Source,'observations',obj.observations(), ...
                'output_dir',folder,'provenance',struct('jobs',{obj.History})),@() obj.Cancelled || ~isvalid(obj.App));
            obj.Status.Text = ['Saved seeds: ' response.directory];
        end
        function saveDialog(obj)
            folder = uigetdir(fileparts(obj.Source.file),'Save seeds in a new subfolder');
            if isequal(folder,0), return; end
            obj.save(folder);
        end
        function loadDialog(obj)
            [file,folder] = uigetfile('*.h5','Load annotations.h5');
            if isequal(file,0), return; end
            obj.load(fullfile(folder,file));
        end
        function load(obj,file)
            if ~isempty(obj.Rows), error('Tracking:ExistingSeeds','Open a fresh reference session before importing another seed set.'); end
            response = obj.bridge(struct('action','import','source',obj.Source,'file',file));
            obj.setRows(response.observations);
            if isfield(response.provenance,'jobs')
                jobs = response.provenance.jobs;
                if isempty(jobs), obj.History = {};
                elseif iscell(jobs), obj.History = jobs;
                else, obj.History = arrayfun(@(job) job,jobs,'UniformOutput',false);
                end
            elseif ~isempty(fieldnames(response.provenance))
                obj.History = {response.provenance};
            end
            if ~isempty(obj.History), obj.Provenance = obj.History{end}; end
            if ~isempty(obj.Rows)
                obj.Frame.Value = obj.Rows(1,2); obj.Channel.Value = obj.Rows(1,7);
            end
            obj.render();
        end
        function setRows(obj,observations)
            rows = zeros(numel(observations),7);
            for i=1:numel(observations)
                r = observations(i); channel = obj.Channel.Value;
                if isfield(r,'channel'), channel = r.channel; end
                obj.Origins(sprintf('%d:%d',r.track_id,r.t)) = char(r.provenance);
                rows(i,:) = [r.track_id,r.t,r.x,r.y,r.z,r.confidence,channel];
            end
            obj.Rows = rows; obj.NextID = max([0;rows(:,1)])+1;
        end
        function track(obj)
            first = round(obj.First.Value); last = round(obj.Last.Value);
            if last-first+1>100 || first>last || last>obj.Source.nt, error('Tracking:Window','Select a valid window of at most 100 frames.'); end
            observations = obj.observations();
            if ~isempty(observations), observations = observations([observations.channel]==obj.Channel.Value); end
            response = obj.bridge(struct('action','track','source',obj.Source,'observations',observations, ...
                'frame_range',[first-1 last-1],'channel',obj.Channel.Value,'output_dir',obj.OutputRoot,'provenance',obj.Provenance),@() obj.Cancelled || ~isvalid(obj.App));
            retained = obj.Rows(~(obj.Rows(:,2)>=first & obj.Rows(:,2)<=last & obj.Rows(:,7)==obj.Channel.Value),:);
            obj.setRows(response.observations); obj.Rows = [retained;obj.Rows]; obj.NextID = max([0;obj.Rows(:,1)])+1;
            obj.render(); obj.Status.Text = ['Tracking complete: ' response.directory];
        end
    end
    methods (Static, Access=private)
        function removeFile(file)
            if isfile(file), delete(file); end
        end
    end
end
