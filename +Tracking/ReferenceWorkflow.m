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
        DetectionChannel
        DetectionMode
        RGBW
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
        Reader
        Busy = false
        Cancelled = false
        Provenance = struct()
        History = {}
        Cursor = []
        OutputRoot
        CloseCallback
        Origins
        View
        Analysis
        Reference
        TrackingChannel
        WindowSize
        Epochs
        TrackDirectory = ''
        ActivityDirectory = ''
        ActivityRows = []
        ActivityExcluded = []
        ActivitySettings = struct()
        Excluded = zeros(0,2)
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
                if isvalid(previous), previous.View.Playback.stop(); end
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
        function response = bridge(request, cancel, progress)
            if nargin < 2, cancel = @() false; end
            if nargin < 3, progress = []; end
            timeout = 3600;
            if strcmp(request.action,'track_sequence'), timeout = 86400; end
            folder = tempname; mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder,'s'));
            input = fullfile(folder,'request.json'); output = fullfile(folder,'response.json');
            fid = fopen(input,'w'); guard = onCleanup(@() fclose(fid));
            fwrite(fid,jsonencode(request),'char'); clear guard
            root = fileparts(fileparts(mfilename('fullpath')));
            [status, detail] = Wrapper.runPythonProcess( ...
                {Tracking.ReferenceWorkflow.python(),'-u',fullfile(root,'+Wrapper','reference_video.py'), ...
                '--request',input,'--response',output},'CancelFcn',cancel,'ProgressFcn',progress,'TimeoutSeconds',timeout);
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
            obj.Reader = Tracking.FrameReader(info);
            obj.View = Tracking.ReferenceView(obj);
            app.VideoTrackingTab.Tag = 'rendered'; app.TabGroup.SelectedTab = app.VideoTrackingTab;
            obj.render();
            if info.nt==1, obj.Frame.Enable = 'off'; end
            if info.nz==1, obj.Slice.Enable = 'off'; end
        end
        function delete(obj)
            if ~isempty(obj.Reader) && isvalid(obj.Reader), delete(obj.Reader); end
            if ~isempty(obj.Analysis) && isvalid(obj.Analysis), delete(obj.Analysis); end
            if ~isempty(obj.View) && isvalid(obj.View), delete(obj.View); end
            if ~isempty(obj.App) && isvalid(obj.App) && isvalid(obj.App.CELL_ID)
                obj.App.CELL_ID.CloseRequestFcn = obj.CloseCallback;
            end
            if ~isempty(obj.Grid) && isvalid(obj.Grid), delete(obj.Grid); end
        end
        function closeSession(obj,src,event)
            obj.View.Playback.stop();
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
            obj.View.Playback.stop(); obj.View.FramePreview.cancel(); obj.View.Preview.cancel();
            obj.Busy = true; obj.Cancelled = false;
            obj.View.setBusy(true);
            obj.Frame.Enable = 'off'; obj.Channel.Enable = 'off'; obj.Slice.Enable = 'off';
            obj.Table.Enable = 'off';
            obj.DetectionChannel.Enable='off'; obj.DetectionMode.Enable='off'; obj.RGBW.Enable='off';
            obj.Detector.Enable = 'off'; obj.Spacing.Enable = 'off'; obj.Calibration.Enable = 'off';
            obj.First.Enable = 'off'; obj.Last.Enable = 'off';
            obj.Analysis.setBusy(true);
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
            obj.DetectionChannel.Enable='on'; obj.DetectionMode.Enable='on'; obj.RGBW.Enable='on';
            obj.Detector.Enable = 'on'; obj.Spacing.Enable = 'on'; obj.Calibration.Enable = 'on';
            obj.First.Enable = 'on'; obj.Last.Enable = 'on';
            obj.View.updateList(); obj.View.setBusy(false); obj.Analysis.setBusy(false);
            if obj.Source.nt==1, obj.Frame.Enable = 'off'; end
            if obj.Source.nz==1, obj.Slice.Enable = 'off'; end
        end
        function progress(obj,message)
            obj.Status.Text = char(message);
            prefix = 'Tracking workspace: ';
            if startsWith(message,prefix), obj.TrackDirectory = char(extractAfter(message,prefix)); end
        end
        function cancel(obj)
            obj.Cancelled = true;
        end
        function volume = frameData(obj)
            t = round(obj.Frame.Value); obj.Frame.Value = min(obj.Source.nt,t);
            t = obj.Frame.Value;
            if t ~= obj.CacheFrame
                obj.Cache = obj.Reader.read(t);
                obj.CacheFrame = t;
            end
            volume = obj.Cache(:,:,:,obj.Channel.Value+1);
        end
        function render(obj)
            obj.View.render();
        end
        function spacingChanged(obj)
            obj.Calibration.Text = 'Use assumed spacing'; obj.Calibration.Value = false;
        end
        function detect(obj)
            if ~obj.Calibration.Value, error('Tracking:Spacing','Confirm measured or assumed voxel spacing in Settings before detection.'); end
            scale = sscanf(obj.Spacing.Value,'%f')';
            if numel(scale)~=3 || any(~isfinite(scale) | scale<=0), error('Tracking:Spacing','Enter three positive XYZ spacings.'); end
            actual = obj.bridge(struct('action','inspect','file',obj.Source.file));
            if ~strcmp(actual.source_id,obj.Source.source_id)
                error('Tracking:SourceChanged','Recording or metadata changed. Reopen the source before detection.');
            end
            mode='single_channel'; channel=obj.DetectionChannel.Value; mapping=[];
            if strcmp(obj.DetectionMode.Value,'RGBW')
                mode='rgbw'; mapping=sscanf(obj.RGBW.Value,'%f')';
                if numel(mapping)~=4 || numel(unique(mapping))~=4 || any(~isfinite(mapping) | mapping~=round(mapping) | mapping<0 | mapping>=obj.Source.nc)
                    error('Tracking:RGBWChannels','Enter four distinct channel indices in R G B W order.');
                end
                channel=mapping(1);
            end
            obj.Channel.Value=channel; volume=obj.frameData(); frame=obj.Frame.Value;
            if strcmp(mode,'rgbw'), volume=obj.Cache(:,:,:,mapping+1); end
            measured = obj.Source.spacing_measured && isequal(scale,obj.Source.spacing_um_xyz(:)');
            snapshot = struct('source_id',obj.Source.source_id,'frame_index',frame-1,'channel_index',channel, ...
                'spacing_measured',measured,'spacing_um_xyz',scale,'input_mode',mode,'rgbw_channels',mapping);
            obj.Status.Text = 'Detecting selected channel…'; drawnow;
            if ~any(volume(:)>0)
                response = struct('centroids_yxz',zeros(0,3),'scores',zeros(0,1),'num_centroids',0,'source_metadata',snapshot);
            else
                response = Wrapper.runMoECentroids(volume,scale,'InputMode',string(mode),'SourceMetadata',snapshot, ...
                    'Backend',lower(string(obj.Detector.Value)),'ProgressFcn',@(message) obj.progress(message),'CancelFcn',@() obj.Cancelled || ~isvalid(obj.App),'OutputDir',obj.OutputRoot);
            end
            if obj.Frame.Value~=frame || obj.Channel.Value~=channel
                error('Tracking:StaleDetection','Frame or channel changed; run detection again.');
            end
            xyz = response.centroids_yxz(:,[2 1 3]);
            if any(xyz<1,'all') || any(xyz>[obj.Source.nx obj.Source.ny obj.Source.nz],'all')
                error('Tracking:Bounds','Detector returned a center outside pixel-center bounds.');
            end
            obj.View.Review.clear();
            n = size(xyz,1);
            obj.Candidates = [(obj.NextID:obj.NextID+n-1)',repmat(frame,n,1),xyz,response.scores(:),repmat(channel,n,1)];
            obj.NextID = obj.NextID+n;
            obj.CandidateFrame = frame; obj.Provenance = response;
            obj.History{end+1} = response;
            obj.Reference.Value = frame; obj.First.Value = 1; obj.Last.Value = obj.Source.nt;
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
            obj.View.Review.checkpoint();
            obj.Rows = [obj.Rows;obj.Candidates]; obj.NextID = max(obj.NextID,max(obj.Rows(:,1))+1);
            obj.Candidates = zeros(0,7); obj.render();
        end
        function discard(obj)
            obj.View.Review.checkpoint();
            obj.Candidates = zeros(0,7); obj.render();
        end
        function captureCursor(obj)
            if obj.Busy, return; end
            obj.Cursor = obj.Axes.CurrentPoint;
        end
        function add(obj)
            if isempty(obj.Cursor), error('Tracking:Cursor','Click a location in the image first.'); end
            obj.View.Review.checkpoint();
            point = obj.Cursor;
            xyz = [min(obj.Source.nx,max(1,point(1,1))),min(obj.Source.ny,max(1,point(1,2))),round(obj.Slice.Value)];
            obj.Rows(end+1,:) = [obj.NextID,obj.Frame.Value,xyz,1,obj.Channel.Value]; obj.NextID = obj.NextID+1; obj.render();
        end
        function remove(obj)
            obj.View.removeSelection();
        end
        function edit(obj,event)
            row = event.Indices(1); column = event.Indices(2); value = event.NewData;
            if ischar(value) || isstring(value), value = str2double(value); end
            bounds = [obj.Source.nx obj.Source.ny obj.Source.nz];
            if ~isscalar(value) || ~isfinite(value) || value<1 || value>bounds(column-2)
                obj.Table.Data = obj.Rows; error('Tracking:EditBounds','Coordinates must lie inside the volume.');
            end
            obj.View.Review.checkpoint(obj.Rows(row,1));
            obj.Origins(sprintf('%d:%d',obj.Rows(row,1),obj.Rows(row,2))) = 'reviewed';
            obj.Rows(row,column) = value; obj.Rows(row,6) = 1; obj.render();
        end
        function observations = observations(obj)
            observations = struct('track_id',{},'parent_id',{},'t',{},'x',{},'y',{},'z',{},'confidence',{},'provenance',{},'channel',{},'excluded',{});
            for i=1:size(obj.Rows,1)
                r = obj.Rows(i,:); origin = 'reviewed';
                key = sprintf('%d:%d',r(1),r(2));
                if isKey(obj.Origins,key), origin = obj.Origins(key); end
                observations(i) = struct('track_id',r(1),'parent_id',0,'t',r(2),'x',r(3),'y',r(4),'z',r(5), ...
                    'confidence',r(6),'provenance',origin,'channel',r(7),'excluded',ismember(r([1 2]),obj.Excluded,'rows'));
            end
        end
        function response = save(obj,folder)
            response = obj.bridge(struct('action','export','source',obj.Source,'observations',obj.observations(), ...
                'output_dir',folder,'provenance',struct('jobs',{obj.History},'session',obj.Analysis.session())),@() obj.Cancelled || ~isvalid(obj.App));
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
            obj.Candidates=zeros(0,7); obj.CandidateFrame=0;
            obj.History={}; obj.Provenance=struct(); obj.TrackDirectory=''; obj.ActivityDirectory='';
            obj.ActivityRows=[]; obj.ActivityExcluded=[]; obj.ActivitySettings=struct();
            obj.setRows(response.observations);
            if isfield(response.provenance,'session'), obj.Analysis.restoreSession(response.provenance.session); end
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
            obj.View.Review.clear();
            rows = zeros(numel(observations),7); obj.Excluded = zeros(0,2);
            for i=1:numel(observations)
                r = observations(i); channel = obj.Channel.Value;
                if isfield(r,'channel'), channel = r.channel; end
                obj.Origins(sprintf('%d:%d',r.track_id,r.t)) = char(r.provenance);
                if isfield(r,'excluded') && r.excluded, obj.Excluded(end+1,:) = [r.track_id r.t]; end
                rows(i,:) = [r.track_id,r.t,r.x,r.y,r.z,r.confidence,channel];
            end
            obj.Rows = rows; obj.NextID = max(obj.NextID,max([0;rows(:,1);obj.Candidates(:,1)])+1);
        end
        function track(obj,resume)
            obj.View.Review.clear();
            if nargin<2, resume=false; end
            request = struct('action','track_sequence','source',obj.Source,'observations',obj.observations(), ...
                'frame_range',[obj.First.Value-1 obj.Last.Value-1],'reference_frame',obj.Reference.Value-1, ...
                'channel',obj.TrackingChannel.Value,'window_size',obj.WindowSize.Value,'epochs',obj.Epochs.Value, ...
                'output_dir',obj.OutputRoot,'provenance',struct('jobs',{obj.History}));
            if resume
                if isempty(obj.TrackDirectory), error('Tracking:Resume','There is no tracking run to resume.'); end
                request.resume_dir=obj.TrackDirectory;
            end
            response = obj.bridge(request,@() obj.Cancelled || ~isvalid(obj.App),@(message) obj.progress(message));
            obj.TrackDirectory=response.directory;
            obj.mergeTracks(response.observations);
            obj.render(); obj.Status.Text = ['Tracking complete: ' response.directory];
        end
        function mergeTracks(obj,observations)
            previous=obj.observations(); excluded=obj.Excluded;
            keys=[[observations.track_id]' [observations.t]'];
            if ~isempty(previous)
                retained=~ismember([[previous.track_id]' [previous.t]'],keys,'rows');
                previous=previous(retained);
            end
            obj.setRows(observations);
            current=obj.observations(); obj.setRows([previous(:);current(:)]);
            retained=ismember(excluded,obj.Rows(:,[1 2]),'rows'); obj.Excluded=unique([obj.Excluded;excluded(retained,:)],'rows');
        end
        function openTracking(obj)
            [file,folder]=uigetfile('tracking.json','Open a saved tracking run',fullfile(obj.OutputRoot,'tracking.json'));
            if isequal(file,0), return; end
            if ~isempty(obj.Rows)
                answer=uiconfirm(obj.App.CELL_ID,'Replace the current neurons with this tracking checkpoint? Save seeds first to retain edits.', ...
                    'Open tracking run','Options',{'Cancel','Replace'},'DefaultOption','Cancel','CancelOption','Cancel');
                if strcmp(answer,'Cancel'), return; end
            end
            response=obj.bridge(struct('action','tracking_checkpoint','source',obj.Source,'directory',folder));
            obj.TrackDirectory=folder; obj.Candidates=zeros(0,7); obj.setRows(response.observations);
            obj.Analysis.restoreTracking(response.manifest.parameters); obj.Frame.Value=obj.Reference.Value; obj.render();
        end
        function loadProgress(obj)
            if isempty(obj.TrackDirectory), error('Tracking:Resume','There is no tracking run to load.'); end
            response=obj.bridge(struct('action','tracking_checkpoint','source',obj.Source,'directory',obj.TrackDirectory));
            obj.mergeTracks(response.observations); obj.Analysis.restoreTracking(response.manifest.parameters); obj.render();
            obj.Status.Text=sprintf('Loaded %d completed tracking windows.',numel(response.manifest.completed));
        end
        function extractActivity(obj)
            response=obj.bridge(struct('action','activity','source',obj.Source,'observations',obj.observations(), ...
                'frame_range',[obj.First.Value-1 obj.Last.Value-1],'options',obj.Analysis.options(), ...
                'output_dir',obj.OutputRoot,'provenance',struct('jobs',{obj.History},'tracking',obj.TrackDirectory)), ...
                @() obj.Cancelled || ~isvalid(obj.App),@(message) obj.progress(message));
            obj.ActivityDirectory=response.directory; obj.ActivityRows=obj.Rows; obj.ActivityExcluded=obj.Excluded;
            obj.ActivitySettings=obj.Analysis.options(); obj.Analysis.showActivity();
            obj.Status.Text=sprintf('Activity saved · %.1f%% finite ΔF/F · %s',100*response.finite_fraction,response.directory);
        end
        function current = activityCurrent(obj)
            current=~isempty(obj.ActivityDirectory) && isfile(fullfile(obj.ActivityDirectory,'activity.h5')) && isequal(obj.Rows,obj.ActivityRows) && ...
                isequal(obj.Excluded,obj.ActivityExcluded) && isequal(obj.Analysis.options(),obj.ActivitySettings);
        end
        function exportActivity(obj,folder)
            if ~obj.activityCurrent(), error('Tracking:Activity','Extract activity again after changing tracks or measurement settings.'); end
            if nargin<2, folder=uigetdir(fileparts(obj.Source.file),'Export activity and tracks'); end
            if isequal(folder,0), return; end
            [~,name]=fileparts(tempname(folder)); destination=fullfile(folder,['activity-' name]);
            stage=fullfile(folder,['.activity-' name]); cleanup=onCleanup(@() obj.removeFolder(stage));
            [ok,message]=copyfile(obj.ActivityDirectory,stage);
            if ~ok, error('Tracking:Export','%s',message); end
            % Include review decisions made after the measurements were extracted.
            snapshot=obj.bridge(struct('action','export','source',obj.Source,'observations',obj.observations(), ...
                'output_dir',stage,'provenance',struct('jobs',{obj.History},'session',obj.Analysis.session())), ...
                @() obj.Cancelled || ~isvalid(obj.App));
            tracks=fullfile(stage,'tracks'); if isfolder(tracks), rmdir(tracks,'s'); end
            [ok,message]=movefile(snapshot.directory,tracks);
            if ~ok, error('Tracking:Export','%s',message); end
            [ok,message]=movefile(stage,destination);
            if ~ok, error('Tracking:Export','%s',message); end
            obj.Status.Text=['Exported activity and tracks: ' destination];
        end

    end
    methods (Static, Access=private)
        function removeFolder(folder)
            if isfolder(folder), rmdir(folder,'s'); end
        end
        function removeFile(file)
            if isfile(file), delete(file); end
        end
    end
end
