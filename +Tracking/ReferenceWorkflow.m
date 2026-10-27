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
        CloseWindow
        InstalledCloseCallback
        Disposing = false
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
            sources = DataHandling.OpenSource.inspect(path);
            yes = sources.recording;
        end
        function workflow = open(app, path)
            Program.HeavyJob.assertIdle();
            info = Tracking.ReferenceWorkflow.bridge(struct('action','inspect','file',char(path)));
            key = 'calcium_reference_workflow';
            if isappdata(app.CELL_ID,key)
                previous = getappdata(app.CELL_ID,key);
                if isvalid(previous), previous.View.Playback.stop(); end
                if isvalid(previous) && (~isempty(previous.Rows) || ~isempty(previous.Candidates))
                    answer = uiconfirm(app.CELL_ID,'Close the current reference session? Unsaved neurons and pending detection candidates will be lost.', ...
                        'Open recording','Options',{'Cancel','Close session'},'DefaultOption','Cancel','CancelOption','Cancel');
                    if strcmp(answer,'Cancel'), workflow = previous; return; end
                end
                delete(previous);
            end
            workflow = Tracking.ReferenceWorkflow(app, info);
            setappdata(app.CELL_ID,key,workflow);
        end
        function python = python(capability,cancel)
            if nargin<1, capability='recording_io'; end
            if nargin<2, cancel=[]; end
            python = Runtime.Resolver.python(capability,'',cancel);
        end
        function response = bridge(request, cancel, progress)
            if nargin < 2, cancel = @() false; end
            if nargin < 3, progress = []; end
            python = Tracking.ReferenceWorkflow.python(Runtime.Catalog.action(request.action),cancel);
            timeout = 3600;
            if strcmp(request.action,'track_sequence'), timeout = 86400; end
            folder = tempname; mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder,'s'));
            input = fullfile(folder,'request.json'); output = fullfile(folder,'response.json');
            fid = fopen(input,'w'); guard = onCleanup(@() fclose(fid));
            fwrite(fid,unicode2native(jsonencode(request),'UTF-8'),'uint8'); clear guard
            root = fileparts(fileparts(mfilename('fullpath')));
            [status, detail] = Wrapper.runPythonProcess( ...
                {python,'-u',fullfile(root,'+Wrapper','reference_video.py'), ...
                '--request',input,'--response',output},'CancelFcn',cancel,'ProgressFcn',progress,'TimeoutSeconds',timeout);
            if status ~= 0, error('Tracking:ReferenceFailed','%s',detail); end
            response = jsondecode(fileread(output));
        end
        function dispatchClose(obj, previous, src, event)
            if isempty(src) || ~isvalid(src), return; end
            if ~isempty(obj) && isvalid(obj) && ~obj.Disposing
                obj.closeSession(src,event);
            else
                % Later handlers can still retain a disposed workflow in their chain.
                Tracking.ReferenceWorkflow.invokeClose(previous,src,event);
            end
        end
        function invokeClose(callback, src, event)
            if isempty(src) || ~isvalid(src), return; end
            if iscell(callback), feval(callback{1},src,event,callback{2:end});
            elseif isa(callback,'function_handle'), callback(src,event);
            elseif ischar(callback) || (isstring(callback) && isscalar(callback))
                evalin('base',char(callback));
            else, delete(src);
            end
        end
    end
    methods
        function obj = ReferenceWorkflow(app, info)
            obj.App = app; obj.Source = info;
            previousVisible=[]; previousTag=[]; previousTab=[];
            try
                obj.Origins = containers.Map('KeyType','char','ValueType','char');
                obj.CloseWindow = app.CELL_ID;
                obj.CloseCallback = obj.CloseWindow.CloseRequestFcn;
                previous = obj.CloseCallback;
                obj.InstalledCloseCallback = @(src,event) Tracking.ReferenceWorkflow.dispatchClose(obj,previous,src,event);
                obj.CloseWindow.CloseRequestFcn = obj.InstalledCloseCallback;
                obj.OutputRoot = fullfile(prefdir,'NeuroPAL','reference-jobs');
                previousVisible=app.VideoGridLayout.Visible;
                previousTag=app.VideoTrackingTab.Tag; previousTab=app.TabGroup.SelectedTab;
                app.VideoGridLayout.Visible = 'off';
                obj.Reader = Tracking.FrameReader(info);
                obj.View = Tracking.ReferenceView(obj);
                app.VideoTrackingTab.Tag = 'rendered'; app.TabGroup.SelectedTab = app.VideoTrackingTab;
                obj.render();
                if info.nt==1, obj.Frame.Enable = 'off'; end
                if info.nz==1, obj.Slice.Enable = 'off'; end
            catch failure
                ownsClose=false;
                try
                    ownsClose=isvalid(obj.CloseWindow) && ...
                        isequal(obj.CloseWindow.CloseRequestFcn,obj.InstalledCloseCallback);
                catch
                end
                try, delete(obj); catch, end
                if ownsClose && ~isempty(previousVisible)
                    % Roll back this construction's presentation without changing a newer owner.
                    try, app.VideoGridLayout.Visible=previousVisible; catch, end
                    try, app.VideoTrackingTab.Tag=previousTag; catch, end
                    try, if ~isempty(previousTab), app.TabGroup.SelectedTab=previousTab; end, catch, end
                end
                rethrow(failure);
            end
        end
        function delete(obj)
            if obj.Disposing, return; end
            obj.Disposing=true;
            try
                if ~isempty(obj.CloseWindow) && isvalid(obj.CloseWindow) && ...
                        isequal(obj.CloseWindow.CloseRequestFcn,obj.InstalledCloseCallback)
                    obj.CloseWindow.CloseRequestFcn = obj.CloseCallback;
                end
            catch
                % A parent window may already be disposing its graphics callbacks.
            end
            obj.stopPlayback();
            % Dispose UI before the reader, including playback installed by a
            % view whose constructor failed before returning its handle.
            resources={obj.View,obj.Analysis,obj.Grid,obj.Reader};
            for i=1:numel(resources)
                try
                    if ~isempty(resources{i}) && isvalid(resources{i}), delete(resources{i}); end
                catch
                    % Continue releasing resources while a failed constructor unwinds.
                end
            end
        end
        function closeSession(obj,src,event)
            obj.stopPlayback();
            if obj.Busy
                obj.Cancelled = true;
                if ~isempty(obj.Status) && isvalid(obj.Status)
                    obj.Status.Text = 'Canceling the active job. Close again when it has stopped.';
                end
                return;
            end
            if ~isempty(obj.Rows) || ~isempty(obj.Candidates)
                answer = uiconfirm(obj.App.CELL_ID,'Close the reference session? Unsaved neurons and pending detection candidates will be lost.', ...
                    'Close session','Options',{'Cancel','Close without saving'},'DefaultOption','Cancel','CancelOption','Cancel');
                if strcmp(answer,'Cancel'), return; end
            end
            Tracking.ReferenceWorkflow.invokeClose(obj.CloseCallback,src,event);
        end
        function safe(obj, action)
            if obj.Busy, return; end
            obj.View.Playback.stop(); obj.View.FramePreview.cancel(); obj.View.Preview.cancel();
            obj.Busy = true; obj.Cancelled = false;
            cleanup = onCleanup(@() obj.finish());
            try
                obj.View.setBusy(true);
                obj.Frame.Enable = 'off'; obj.Channel.Enable = 'off'; obj.Slice.Enable = 'off';
                obj.Table.Enable = 'off';
                obj.DetectionChannel.Enable='off'; obj.DetectionMode.Enable='off'; obj.RGBW.Enable='off';
                obj.Detector.Enable = 'off'; obj.Spacing.Enable = 'off'; obj.Calibration.Enable = 'off';
                obj.First.Enable = 'off'; obj.Last.Enable = 'off';
                obj.Analysis.setBusy(true);
                action();
            catch ME
                obj.Status.Text = ME.message;
                if contains(ME.identifier,'Cancelled'), return;
                elseif startsWith(ME.identifier,'Runtime:')
                    Runtime.Settings.failure(obj.App,ME);
                elseif ~contains(ME.identifier,'Cancelled')
                    uialert(obj.App.CELL_ID,Program.GUIHandling.method_error_message(ME),'Reference workflow');
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
            Tracking.ImageUnits.refresh(obj);
        end
        function detect(obj)
            if ~obj.Calibration.Value
                obj.View.openSettings(); obj.Status.Text='Confirm voxel spacing in Image settings, then run detection.'; return;
            end
            scale = Tracking.ImageUnits.spacing(obj);
            if numel(scale)~=3 || any(~isfinite(scale) | scale<=0), error('Tracking:Spacing','Enter three positive XYZ spacings.'); end
            mode='single_channel'; channel=obj.DetectionChannel.Value; mapping=[];
            if strcmp(obj.DetectionMode.Value,'RGBW')
                mode='rgbw'; mapping=sscanf(obj.RGBW.Value,'%f')';
                if numel(mapping)~=4 || numel(unique(mapping))~=4 || any(~isfinite(mapping) | mapping~=round(mapping) | mapping<0 | mapping>=obj.Source.nc)
                    error('Tracking:RGBWChannels','Enter four distinct channel indices in R G B W order.');
                end
                channel=mapping(1);
            end
            selected=channel; merge_radius=0;
            score_threshold=Tracking.DetectionSettings.threshold(obj);
            if strcmp(obj.DetectionMode.Value,'Multi-channel')
                settings=Tracking.DetectionChannels.get(obj); selected=settings.channels; merge_radius=settings.merge_radius_um;
                if numel(selected)<2, error('Tracking:Channels','Select at least two channels, or choose Single channel.'); end
                mode='multi_channel'; channel=selected(1);
            end
            actual = obj.bridge(struct('action','inspect','file',obj.Source.file));
            if ~strcmp(actual.source_id,obj.Source.source_id)
                error('Tracking:SourceChanged','Recording or metadata changed. Reopen the source before detection.');
            end
            obj.Channel.Value=channel; volume=obj.frameData(); frame=obj.Frame.Value;
            if strcmp(mode,'rgbw'), volume=obj.Cache(:,:,:,mapping+1); selected=mapping; end
            measured = obj.Source.spacing_measured && isequal(scale,obj.Source.spacing_um_xyz(:)');
            snapshot = struct('source_id',obj.Source.source_id,'frame_index',frame-1,'channel_index',channel, ...
                'spacing_measured',measured,'spacing_um_xyz',scale,'input_mode',mode,'rgbw_channels',mapping,'selected_channels',selected);
            obj.Status.Text = 'Detecting selected channel…'; drawnow;
            if strcmp(mode,'multi_channel')
                response=Wrapper.runMultiChannelCentroids(obj.Cache,selected,scale,'MergeRadiusUm',merge_radius, ...
                    'SourceMetadata',snapshot,'Backend',lower(string(obj.Detector.Value)), ...
                    'ScoreThreshold',score_threshold,'ProgressFcn',@(message) obj.progress(message),'CancelFcn',@() obj.Cancelled || ~isvalid(obj.App),'OutputDir',obj.OutputRoot);
            elseif ~any(volume(:)>0)
                response = struct('centroids_yxz',zeros(0,3),'scores',zeros(0,1),'num_centroids',0,'source_metadata',snapshot);
            else
                response = Wrapper.runMoECentroids(volume,scale,'InputMode',string(mode),'SourceMetadata',snapshot, ...
                    'Backend',lower(string(obj.Detector.Value)),'ScoreThreshold',score_threshold, ...
                    'ProgressFcn',@(message) obj.progress(message),'CancelFcn',@() obj.Cancelled || ~isvalid(obj.App),'OutputDir',obj.OutputRoot);
            end
            obj.checkDetectionContext(frame,channel);
            xyz = response.centroids_yxz(:,[2 1 3]);
            if any(xyz<1,'all') || any(xyz>[obj.Source.nx obj.Source.ny obj.Source.nz],'all')
                error('Tracking:Bounds','Detector returned a center outside pixel-center bounds.');
            end
            n = size(xyz,1);
            if n==0
                obj.render(); obj.Status.Text='No neurons detected. Existing candidates, tracks and reference frame were kept.'; return;
            end
            if ~isempty(obj.Candidates)
                answer=uiconfirm(obj.App.CELL_ID,'Replace the pending detection candidates and their edits? Accepted neurons and tracks will be kept.', ...
                    'Replace candidates?','Options',{'Keep existing','Replace candidates'},'DefaultOption',1,'CancelOption',1);
                if ~strcmp(answer,'Replace candidates')
                    obj.Status.Text='Existing detection candidates were kept.'; return;
                end
            end
            obj.checkDetectionContext(frame,channel);
            obj.View.Review.clear();
            source_channels=repmat(channel,n,1);
            if isfield(response,'source_channels'), source_channels=response.source_channels(:); end
            obj.Candidates = [(obj.NextID:obj.NextID+n-1)',repmat(frame,n,1),xyz,response.scores(:),source_channels];
            obj.NextID = obj.NextID+n;
            obj.CandidateFrame = frame; obj.Provenance = response;
            obj.History{end+1} = response;
            if isempty(obj.Rows)
                obj.Reference.Value = frame; obj.First.Value = 1; obj.Last.Value = obj.Source.nt;
            end
            obj.render();
        end
        function checkDetectionContext(obj,frame,channel)
            if obj.Cancelled || ~isvalid(obj.App)
                error('Tracking:Cancelled','Detection was canceled. Existing candidates and tracks were kept.');
            end
            if obj.Frame.Value~=frame || obj.Channel.Value~=channel || obj.CacheFrame~=frame
                error('Tracking:StaleDetection','Frame or channel changed; run detection again.');
            end
        end
        function accept(obj)
            if isempty(obj.Candidates), return; end
            if Tracking.ReferenceConstraints.needed(obj)
                error('Tracking:ReferenceIdentity','Match these proposals to existing neurons using Match neurons. Additional reference frames must keep the original neuron IDs.');
            end
            channels=unique(obj.Candidates(:,7));
            if isfield(obj.Provenance,'source_metadata') && isfield(obj.Provenance.source_metadata,'selected_channels')
                channels=obj.Provenance.source_metadata.selected_channels;
            end
            if obj.Frame.Value~=obj.CandidateFrame || ~ismember(obj.Channel.Value,channels)
                error('Tracking:CandidateView','Return to the candidate frame and channel before accepting.');
            end
            if any(ismember(obj.Candidates(:,[2 7]),obj.Rows(:,[2 7]),'rows'))
                error('Tracking:ExistingSeeds','This frame/channel already has seeds. Delete those rows before accepting a replacement.');
            end
            obj.View.Review.checkpoint();
            obj.Rows = [obj.Rows;obj.Candidates]; obj.NextID = max(obj.NextID,max(obj.Rows(:,1))+1);
            obj.Candidates = zeros(0,7); obj.render(); Tracking.ReferenceFrames.refresh(obj);
        end
        function discard(obj)
            obj.View.Review.checkpoint();
            obj.Candidates = zeros(0,7); obj.render();
        end
        function continueTracking(obj)
            if obj.Busy, return; end
            try
                obj.View.Playback.stop(); obj.View.FramePreview.cancel(); obj.View.Preview.cancel();
                obj.checkTrackingSeeds(false);
                obj.View.setStage(3);
            catch ME
                obj.Status.Text=ME.message;
                uialert(obj.App.CELL_ID,ME.message,'Continue to tracking');
            end
        end
        function checkTrackingSeeds(obj,check_reference)
            if ~isempty(obj.Candidates)
                error('Tracking:PendingCandidates','Accept the detected candidates before continuing to tracking.');
            end
            if isempty(obj.Rows)
                error('Tracking:NoSeeds','Run Auto Detect and accept the candidates first, or add neurons in Review.');
            end
            % Reference and range settings are edited in the Track panel.
            if ~check_reference, return; end
            first=obj.First.Value; last=obj.Last.Value; reference=obj.Reference.Value;
            frames=[first reference last];
            if any(~isfinite(frames) | frames~=round(frames)) || first<1 || first>reference || reference>last || last>obj.Source.nt
                error('Tracking:ReferenceRange','Use whole frame numbers, with First frame <= Reference frame <= Last frame.');
            end
            root=obj.Rows(obj.Rows(:,2)==reference,1);
            if isempty(root)
                error('Tracking:ReferenceSeeds','Frame %d has no accepted neurons. Set Reference frame to a frame containing your accepted neurons.',reference);
            end
            selected=obj.Rows(:,2)>=first & obj.Rows(:,2)<=last & ~ismember(obj.Rows(:,1),root);
            rows=obj.Rows(selected,:);
            for i=1:size(rows,1)
                key=sprintf('%d:%d',rows(i,1),rows(i,2));
                if ~isKey(obj.Origins,key) || ~strcmp(obj.Origins(key),'zephir')
                    error('Tracking:IncompleteReference', ...
                        'Neuron %d has an accepted observation in the tracking range but is missing from reference frame %d. Choose a reference containing all seed neurons, or correct the seed set in Review.',rows(i,1),reference);
                end
            end
        end
        function captureCursor(obj)
            if obj.Busy, return; end
            obj.Cursor = obj.Axes.CurrentPoint;
        end
        function add(obj)
            if isempty(obj.Cursor), error('Tracking:Cursor','Click a location in the image first.'); end
            point = obj.Cursor;
            xyz = [min(obj.Source.nx,max(1,point(1,1))),min(obj.Source.ny,max(1,point(1,2))),round(obj.Slice.Value)];
            identity=obj.View.AddIdentity; frame=obj.View.AddFrame; replace=obj.View.AddReplace;
            obj.View.AddIdentity=[]; obj.View.AddFrame=0; obj.View.AddReplace=false;
            if ~isempty(identity)
                if obj.Frame.Value~=frame || ~any(obj.Rows(:,1)==identity & obj.Rows(:,2)==obj.Reference.Value)
                    error('Tracking:ReferenceIdentity','The reference or current frame changed. Choose Place center again.');
                end
                existing=obj.Rows(:,1)==identity & obj.Rows(:,2)==frame;
                if any(existing) && ~replace
                    error('Tracking:ExistingObservation','This neuron already has a center in this frame. Confirm replacement first.');
                end
                obj.View.Review.checkpoint(identity); obj.Rows(existing,:)=[];
                obj.Rows(end+1,:)=[identity,frame,xyz,1,obj.Channel.Value];
                obj.Origins(sprintf('%d:%d',identity,frame))='reviewed';
                obj.View.PreferredID=identity; obj.View.Selection=[false identity frame];
                obj.render(); Tracking.ReferenceFrames.refresh(obj); return;
            end
            obj.View.Review.checkpoint();
            if isempty(obj.Rows), obj.Reference.Value=obj.Frame.Value; end
            obj.Rows(end+1,:) = [obj.NextID,obj.Frame.Value,xyz,1,obj.Channel.Value]; obj.NextID = obj.NextID+1; obj.render();
        end
        function remove(obj)
            obj.View.removeSelection();
        end
        function edit(obj,event)
            row = event.Indices(1); column = event.Indices(2); value = event.NewData;
            if ischar(value) || isstring(value), value = str2double(value); end
            bounds = [obj.Source.nx obj.Source.ny obj.Source.nz];
            if ~isscalar(value) || ~isfinite(value) || value<.5 || value>bounds(column-2)+.5
                obj.Table.Data = obj.Rows; error('Tracking:EditBounds','Coordinates must lie inside the volume.');
            end
            obj.View.Review.checkpoint(obj.Rows(row,1));
            obj.Origins(sprintf('%d:%d',obj.Rows(row,1),obj.Rows(row,2))) = 'reviewed';
            obj.Rows(row,column) = value; obj.Rows(row,6) = 1; obj.render();
        end
        function observations = observations(obj)
            observations = struct('track_id',{},'parent_id',{},'t',{},'x',{},'y',{},'z',{},'confidence',{},'provenance',{},'channel',{},'excluded',{},'name',{},'identity_confidence',{},'identity_source',{});
            identities=Tracking.NeuronNames.get(obj);
            for i=1:size(obj.Rows,1)
                r = obj.Rows(i,:); origin = 'reviewed';
                key = sprintf('%d:%d',r(1),r(2));
                if isKey(obj.Origins,key), origin = obj.Origins(key); end
                identity=find([identities.id]==r(1),1); name=sprintf('Neuron %d',r(1)); confidence=0; source='unnamed';
                if ~isempty(identity), name=identities(identity).name; confidence=identities(identity).confidence; source=identities(identity).source; end
                observations(i) = struct('track_id',r(1),'parent_id',0,'t',r(2),'x',r(3),'y',r(4),'z',r(5), ...
                    'confidence',r(6),'provenance',origin,'channel',r(7),'excluded',ismember(r([1 2]),obj.Excluded,'rows'),'name',name,'identity_confidence',confidence,'identity_source',source);
            end
        end
        function response = save(obj,folder)
            obj.requireAccepted('saving the session');
            response = obj.bridge(struct('action','export','source',obj.Source,'observations',obj.observations(), ...
                'output_dir',folder,'provenance',struct('jobs',{obj.History},'session',obj.Analysis.session())),@() obj.Cancelled || ~isvalid(obj.App));
            obj.Status.Text = ['Saved seeds: ' response.directory];
        end
        function saveDialog(obj)
            folder = Program.GUI.ManualIDService.selectFile(obj.App,'uigetdir', ...
                fileparts(obj.Source.file),'Save seeds in a new subfolder');
            if isequal(folder,0), return; end
            obj.save(folder);
        end
        function loadDialog(obj)
            [file,folder] = Program.GUI.ManualIDService.selectFile(obj.App,'uigetfile', ...
                '*.h5','Load annotations.h5');
            if isequal(file,0), return; end
            obj.load(fullfile(folder,file));
        end
        function load(obj,file)
            if ~isempty(obj.Rows) || ~isempty(obj.Candidates), error('Tracking:ExistingSeeds','Open a fresh reference session before importing another seed set. Resolve pending candidates or reset the current session first.'); end
            response = obj.bridge(struct('action','import','source',obj.Source,'file',file));
            if isempty(response.provenance), response.provenance=struct(); end
            if ~isstruct(response.provenance) || ~isscalar(response.provenance), error('Tracking:SessionSettings','Invalid saved session provenance.'); end
            if isfield(response.provenance,'session'), Tracking.SessionSettings.validate(obj,response.provenance.session); end
            obj.Candidates=zeros(0,7); obj.CandidateFrame=0;
            Tracking.NeuronNames.set(obj,[]); setappdata(obj.Grid,'paired_reference_provenance',[]);
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
            Tracking.NeuronNames.import(obj,observations);
            obj.Rows = rows; obj.NextID = max(obj.NextID,max([0;rows(:,1);obj.Candidates(:,1)])+1);
        end
        function track(obj,resume)
            if nargin<2, resume=false; end
            obj.checkTrackingSeeds(true);
            request = struct('action','track_sequence','source',obj.Source,'observations',obj.observations(), ...
                'frame_range',[obj.First.Value-1 obj.Last.Value-1],'reference_frame',obj.Reference.Value-1, ...
                'channel',obj.TrackingChannel.Value,'window_size',obj.WindowSize.Value,'epochs',obj.Epochs.Value, ...
                'output_dir',obj.OutputRoot,'provenance',struct('jobs',{obj.History}));
            if resume
                if isempty(obj.TrackDirectory), error('Tracking:Resume','There is no tracking run to resume.'); end
                request.resume_dir=obj.TrackDirectory;
            end
            obj.View.Review.clear();
            response = obj.bridge(request,@() obj.Cancelled || ~isvalid(obj.App),@(message) obj.progress(message));
            obj.TrackDirectory=response.directory;
            obj.mergeTracks(response.observations);
            obj.render(); obj.Status.Text = ['Tracking complete: ' response.directory];
        end
        function mergeTracks(obj,observations)
            previous=obj.observations(); excluded=obj.Excluded; names=Tracking.NeuronNames.get(obj);
            previous_keys=reshape([[previous.track_id]' [previous.t]'],[],2);
            keys=reshape([[observations.track_id]' [observations.t]'],[],2);
            if ~isempty(previous)
                manual=~strcmp({previous.provenance},'zephir')';
                % A checkpoint must not erase manual centers made since its last save.
                observations=observations(~ismember(keys,previous_keys(manual,:),'rows'));
                keys=reshape([[observations.track_id]' [observations.t]'],[],2);
                retained=~ismember(previous_keys,keys,'rows');
                previous=previous(retained);
            end
            obj.setRows(observations);
            current=obj.observations(); merged=[previous(:);current(:)];
            if ~isempty(merged)
                [existing,order]=ismember([[merged.track_id]' [merged.t]'],previous_keys,'rows');
                order(~existing)=size(previous_keys,1)+(1:nnz(~existing));
                [~,indices]=sort(order); merged=merged(indices);
            end
            obj.setRows(merged);
            current_names=Tracking.NeuronNames.get(obj);
            for i=1:numel(names)
                index=find([current_names.id]==names(i).id,1); if isempty(index), index=numel(current_names)+1; end
                current_names(index)=names(i);
            end
            Tracking.NeuronNames.set(obj,current_names);
            retained=ismember(excluded,obj.Rows(:,[1 2]),'rows'); obj.Excluded=unique([obj.Excluded;excluded(retained,:)],'rows');
        end
        function openTracking(obj)
            [file,folder]=Program.GUI.ManualIDService.selectFile(obj.App,'uigetfile', ...
                'tracking.json','Open a saved tracking run',fullfile(obj.OutputRoot,'tracking.json'));
            if isequal(file,0), return; end
            if ~isempty(obj.Rows) || ~isempty(obj.Candidates)
                answer=uiconfirm(obj.App.CELL_ID,'Replace the current neurons and pending candidates with this tracking checkpoint? Unsaved edits will be lost.', ...
                    'Open tracking run','Options',{'Cancel','Replace'},'DefaultOption','Cancel','CancelOption','Cancel');
                if strcmp(answer,'Cancel'), return; end
            end
            response=obj.bridge(struct('action','tracking_checkpoint','source',obj.Source,'directory',folder));
            Tracking.SessionSettings.tracking(obj,response.manifest.parameters);
            obj.TrackDirectory=folder; obj.Candidates=zeros(0,7); obj.setRows(response.observations);
            obj.Analysis.restoreTracking(response.manifest.parameters); obj.Frame.Value=obj.Reference.Value; obj.render();
        end
        function loadProgress(obj)
            obj.requireAccepted('loading tracking progress');
            if isempty(obj.TrackDirectory), error('Tracking:Resume','There is no tracking run to load.'); end
            response=obj.bridge(struct('action','tracking_checkpoint','source',obj.Source,'directory',obj.TrackDirectory));
            Tracking.SessionSettings.tracking(obj,response.manifest.parameters);
            obj.mergeTracks(response.observations); obj.Analysis.restoreTracking(response.manifest.parameters); obj.render();
            obj.Status.Text=sprintf('Loaded %d completed tracking windows.',numel(response.manifest.completed));
        end
        function extractActivity(obj)
            obj.requireAccepted('extracting activity');
            options=obj.Analysis.options();
            if numel(options.radius_xyz)~=3 || any(~isfinite(options.radius_xyz) | options.radius_xyz<=0)
                error('Tracking:ActivityRadius','Enter three positive X Y Z sampling radii in pixels.');
            end
            response=obj.bridge(struct('action','activity','source',obj.Source,'observations',obj.observations(), ...
                'frame_range',[obj.First.Value-1 obj.Last.Value-1],'options',options, ...
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
            obj.requireAccepted('exporting activity');
            if ~obj.activityCurrent(), error('Tracking:Activity','Extract activity again after changing tracks or measurement settings.'); end
            if nargin<2
                folder=Program.GUI.ManualIDService.selectFile(obj.App,'uigetdir', ...
                    fileparts(obj.Source.file),'Export activity and tracks');
            end
            if isequal(folder,0), return; end
            [~,name]=fileparts(tempname(folder)); destination=fullfile(folder,['activity-' name]);
            stage=fullfile(folder,['.activity-' name]); cleanup=onCleanup(@() obj.removeFolder(stage));
            [ok,message]=copyfile(obj.ActivityDirectory,stage);
            if ~ok, error('Tracking:Export','%s',message); end
            % Include names and review decisions made after measurement.
            obj.bridge(struct('action','name_activity','directory',stage,'observations',obj.observations()));
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
        function requireAccepted(obj,action)
            if ~isempty(obj.Candidates)
                error('Tracking:PendingCandidates','Accept or match the pending detection candidates before %s. Unmatched proposals are not saved as neuron tracks.',action);
            end
        end

    end
    methods (Access=private)
        function stopPlayback(obj)
            try
                if ~isempty(obj.View) && isvalid(obj.View) && ...
                        ~isempty(obj.View.Playback) && isvalid(obj.View.Playback)
                    obj.View.Playback.stop();
                end
            catch
                % Construction may have failed before the view became available.
            end
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
