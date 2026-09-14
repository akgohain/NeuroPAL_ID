function handle_zephir_time_slider(app, value, is_final)
%HANDLE_ZEPHIR_TIME_SLIDER Coalesce live XY previews and refresh on release.
if nargin < 3, is_final = true; end
if nargin < 2 || ~local_valid_app(app) || isempty(value) || ...
        ~isstruct(app.video_info) || ~isfield(app.video_info,'nt')
    return
end
target_t = min(max(round(double(value)),1),double(app.video_info.nt));
if ~isscalar(target_t) || ~isfinite(target_t), return; end
state = local_state(app);
state.revision = state.revision+1;
state.target = target_t;
state.final = logical(is_final);
setappdata(app.CELL_ID,'video_tslider_state',state);
app.tEditField.Value = target_t;

if is_final
    local_stop_timer(app);
    app.tSlider.Value = target_t;
    app.visual_composer(target_t);
    drawnow limitrate nocallbacks
    return
end

% Retain MIP and annotated-frame overlay semantics until the full refresh.
if ~local_can_preview(app)
    local_stop_timer(app);
    return
end
timer_key = 'video_tslider_timer';
if isappdata(app.CELL_ID,timer_key)
    worker = getappdata(app.CELL_ID,timer_key);
else
    worker = [];
end
if isempty(worker) || ~isvalid(worker)
    worker = timer('ExecutionMode','fixedSpacing','Period',0.12, ...
        'StartDelay',0.05,'BusyMode','drop','Name','NeuroPAL video preview', ...
        'TimerFcn',@(source,event) local_render_pending(app,source));
    setappdata(app.CELL_ID,timer_key,worker);
end
if strcmp(worker.Running,'off'), start(worker); end
end

function local_render_pending(app, worker)
if ~local_valid_app(app)
    stop(worker);
    delete(worker);
    return
end
state = local_state(app);
if state.final || state.rendered == state.revision || ~local_can_preview(app)
    stop(worker);
    return
end
revision = state.revision;
z = min(max(round(app.hor_zSlider.Value),1),app.video_info.nz);
source_key = Program.Helpers.video_request_key(app.video_info,struct('z',z));
try
    views = Program.Helpers.video_render_views(app,state.target,z,1,1,false,true);
    % Process queued slider events before publishing the completed read.
    drawnow limitrate
    if ~local_valid_app(app) || ~isvalid(worker), return; end
    current = local_state(app);
    current_z = min(max(round(app.hor_zSlider.Value),1),app.video_info.nz);
    current_source = Program.Helpers.video_request_key(app.video_info,struct('z',current_z));
    if current.revision == revision && ~current.final && local_can_preview(app) && ...
            strcmp(source_key,current_source)
        rgb = Program.Helpers.scale_video_projection(app,views.xy);
        handle = Program.Helpers.set_video_image(app.xyAxes,rgb,'npal_video_xy');
        handle.ButtonDownFcn = {@app.ImageClicked};
        app.xyAxes.XLim = [1 size(rgb,2)];
        app.xyAxes.YLim = [1 size(rgb,1)];
        delete(findobj(app.xyAxes,'Type','images.roi.Point'));
        current.rendered = revision;
        setappdata(app.CELL_ID,'video_tslider_state',current);
        drawnow limitrate nocallbacks
    end
catch exception
    if isvalid(worker), stop(worker); end
    warning('Program:Video:PreviewFailed','Video preview failed: %s',exception.message);
    return
end
if local_valid_app(app)
    current = local_state(app);
    if current.final || current.revision == revision || ~local_can_preview(app)
        if isvalid(worker), stop(worker); end
    end
end
end

function state = local_state(app)
state = struct('revision',0,'rendered',0,'target',1,'final',false);
if isappdata(app.CELL_ID,'video_tslider_state')
    state = getappdata(app.CELL_ID,'video_tslider_state');
end
end

function tf = local_valid_app(app)
tf = ~isempty(app) && isvalid(app) && isprop(app,'CELL_ID') && ...
    ~isempty(app.CELL_ID) && isvalid(app.CELL_ID);
end

function tf = local_can_preview(app)
tf = isstruct(app.video_info) && isfield(app.video_info,'file') && ...
    endsWith(lower(char(app.video_info.file)),'.h5') && ...
    ~app.OverlayFrameMIPCheckBox.Value && ~app.OverlaylastIDdframeCheckBox_2.Value;
end

function local_stop_timer(app)
if isappdata(app.CELL_ID,'video_tslider_timer')
    worker = getappdata(app.CELL_ID,'video_tslider_timer');
    if ~isempty(worker) && isvalid(worker), stop(worker); end
end
end
