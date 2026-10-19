function report = test_release_acceptance(app, workflow, varargin)
%TEST_RELEASE_ACCEPTANCE Run release regressions on disposable image copies.
% Model inference and native gestures are validated separately from this suite.
% Skipped checks leave the requested scope incomplete, even when none fail.
if nargin<1, app=[]; end
if nargin<2, workflow=[]; end
parser=inputParser;
addParameter(parser,'Groups',{'engine','main','processing','video'});
addParameter(parser,'ImageSources',{});
addParameter(parser,'OutputRoot',fullfile(tempname,'release-acceptance'));
addParameter(parser,'ThrowOnFailure',false);
parse(parser,varargin{:}); options=parser.Results;
groups=cellstr(string(options.Groups)); groups=groups(:)';
allowed={'engine','main','processing','formats','video'};
if isempty(groups) || any(~ismember(groups,allowed))
    error('NeuroPAL:ReleaseGroups','Choose one or more groups from: %s.',strjoin(allowed,', '));
end
output=char(options.OutputRoot);
if ~isfolder(output), mkdir(output); end
root=fileparts(fileparts(mfilename('fullpath')));
previousPath=path; previousFolder=pwd;
cleanup=onCleanup(@() restore_runtime(previousPath,previousFolder));
addpath(root,fullfile(root,'scripts'));
addpath(genpath(fullfile(root,'External_Dependencies')));
cd(root);
report=struct('started',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'scope','Software contracts and disposable image round trips; excludes scientific accuracy and native gestures. Real-image pixel parity samples first, middle and last Z planes of every channel.', ...
    'requested_groups',{groups},'skips_are_acceptance_passes',false, ...
    'output',output,'results',struct('group',{},'test',{},'status',{},'seconds',{},'identifier',{},'message',{},'details',{}));

if ismember('engine',groups)
    tests={@test_annotation_catalog,@test_annotation_store,@test_annotation_exchange, ...
        @test_annotation_id_writers,@test_annotation_recovery,@test_neuropal_id_integrity_fallback, ...
        @test_annotation_job_context,@test_annotation_constraints,@test_method_registry, ...
        @test_model_setup_failures,@test_advanced_method_scaffolds,@test_multichannel_detection, ...
        @test_legacy_detection_input,@test_transformer_input_indices,@test_heavy_job, ...
        @test_color_readout,@test_histmatch_memory,@test_debug_array_summary, ...
        @test_main_display_view,@test_latest_slice_preview,@test_npal_mat_source, ...
        @test_neuropal_image_loader,@test_import_memory,@test_nwb_stream_export, ...
        @test_nwb_canonical_axes,@test_nwb_singleton_image,@test_nwb_centers,@test_nwb_frame_reader, ...
        @test_processing_transaction,@test_nn_streaming,@test_autoid_resource_cleanup, ...
        @test_ui_resource_lifecycle,@test_large_file_policy,@test_tracking_contracts, ...
        @test_tracking_job_io,@test_tracking_result_adapter,@test_tracking_roi, ...
        @test_trackmate_export,@test_reference_identity_results,@test_h5_video_axes, ...
        @test_video_views,@test_video_slider,@test_video_playback_lifecycle, ...
        @test_reference_workflow_lifecycle,@test_mlapp_code_sync,@test_open_callback_contract};
    for i=1:numel(tests), run_case('engine',func2str(tests{i}),tests{i}); end
end

if ismember('main',groups)
    if isempty(app)
        skip('main','loaded-app','An existing app with a disposable annotated image is required.');
    else
        assert(~isempty(app.image_file) && numel(app.image_neurons.neurons)>=3, ...
            'Open a disposable image with at least three neurons before the main group.');
        tests={@()test_annotation_service(app),@()test_main_detect_save(app), ...
            @()test_manual_id_input(app),@()test_manual_id_contract_ui(app), ...
            @()test_neuron_id_chooser(app),@test_manual_id_data, ...
            @()test_manual_id_selection(app),@()test_manual_id_view(app), ...
            @()test_main_keyboard_guard(app),@()test_main_keyboard_scope(app), ...
            @()test_main_keyboard_navigation(app),@()test_main_slider(app), ...
            @()test_neuron_click_sequence(app),@()test_main_detection_inputs(app), ...
            @()test_main_method_settings(app),@()test_main_geometry_actions(app), ...
            @test_nwb_annotation_roundtrip};
        for i=1:numel(tests), run_case('main',func2str(tests{i}),tests{i}); end
        Program.GUI.ManualIDController.close(app);
    end
end

if ismember('processing',groups)
    if isempty(app) || isempty(app.image_file)
        skip('processing','loaded-app','Open a disposable image in the app so its original image can be restored.');
    else
        original=char(app.image_file);
        imageCleanup=onCleanup(@() run_case('processing','restore-original-image',@()restore_image(app,original)));
        base=fullfile(output,'processing-audit'); if ~isfolder(base), mkdir(base); end
        classes={'uint8','uint16','single'};
        for i=1:numel(classes)
            folder=fullfile(base,classes{i}); if ~isfolder(folder), mkdir(folder); end
            source=fullfile(folder,'baseline.mat'); make_image(source,classes{i});
            operationFolder=fullfile(folder,'processing-format-audit');
            run_case('processing',['operations-' classes{i}], ...
                @()test_processing_operations(app,source,operationFolder));
        end
        tests={@test_processing_normalization,@test_processing_geometry,@test_processing_spectral, ...
            @test_processing_session,@test_processing_recovery,@test_processing_canvas, ...
            @test_processing_legacy_orientation};
        for i=1:numel(tests)
            run_case('processing',func2str(tests{i}),@()processing_case(app,base,tests{i}));
        end
        run_case('processing','save-refusal-preserves-source',@()save_cancel_case(app,base));
        clear imageCleanup
    end
end

if ismember('formats',groups)
    if isempty(app) || isempty(app.image_file)
        skip('formats','loaded-app','Open a disposable image in the app so its original image can be restored.');
    else
        original=char(app.image_file);
        imageCleanup=onCleanup(@() run_case('formats','restore-original-image',@()restore_image(app,original)));
        sources=cellstr(string(options.ImageSources));
        if isempty(sources), skip('formats','source-matrix','No ImageSources were supplied.'); end
        for i=1:numel(sources)
            [~,name,extension]=fileparts(sources{i});
            folder=fullfile(output,'format-audit',sprintf('%02d-%s',i,matlab.lang.makeValidName(name)));
            run_case('formats',[name extension],@()format_case(app,sources{i},folder));
        end
        clear imageCleanup
    end
end

if ismember('video',groups)
    if isempty(workflow)
        skip('video','loaded-workflow','An existing recording workflow is required.');
    else
        workflow.View.Playback.stop();
        tests={@test_reference_coordinate_table,@test_reference_safety,@test_reference_constraints, ...
            @test_reference_marker_editing, ...
            @test_video_detection_settings,@test_tracking_transition,@test_activity_input_validation, ...
            @test_image_units,@test_video_contrast,@test_video_playback_rate};
        for i=1:numel(tests), run_case('video',func2str(tests{i}),@()tests{i}(workflow)); end
        if workflow.Source.nt>=800 && workflow.Source.nz>=17
            tests={@test_video_depth_playback,@test_video_render_serialization};
            for i=1:numel(tests), run_case('video',func2str(tests{i}),@()tests{i}(workflow)); end
        else
            skip('video','bedant-playback-regressions','These fixtures require at least 800 frames and 17 Z slices.');
        end
        if workflow.Source.nt>=1500
            run_case('video','wall-clock-playback',@()test_video_playback_clock(workflow));
        else
            skip('video','wall-clock-playback','This fixture requires at least 1500 frames.');
        end
        if ~isempty(workflow.Rows) && workflow.activityCurrent()
            run_case('video','reference-activity',@()test_reference_activity(workflow));
        else
            skip('video','reference-activity','Current extracted activity is required.');
        end
    end
end
report.finished=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
report.passed=sum(strcmp({report.results.status},'passed'));
report.failed=sum(strcmp({report.results.status},'failed'));
report.skipped=sum(strcmp({report.results.status},'skipped'));
report.requested_groups_complete=report.failed==0 && report.skipped==0;
checkpoint();
fprintf('RELEASE_ACCEPTANCE_RESULT=%d passed, %d failed, %d skipped\n',report.passed,report.failed,report.skipped);
fprintf('RELEASE_ACCEPTANCE_REQUESTED_SCOPE_COMPLETE=%d\n',report.requested_groups_complete);
if options.ThrowOnFailure && report.failed>0
    error('NeuroPAL:ReleaseAcceptance','%d release acceptance groups failed. See %s.',report.failed,output);
end

    function run_case(group,name,action)
        started=tic; fprintf('RELEASE_CASE_START %s %s\n',group,name);
        result=struct('group',group,'test',name,'status','passed','seconds',0, ...
            'identifier','','message','','details','');
        try
            action();
            Program.HeavyJob.assertIdle();
        catch failure
            result.status='failed'; result.identifier=failure.identifier; result.message=failure.message;
            result.details=getReport(failure,'extended','hyperlinks','off');
            fprintf('RELEASE_CASE_FAILURE %s\n%s\n',name,result.details);
        end
        result.seconds=toc(started); report.results(end+1)=result;
        checkpoint(); fprintf('RELEASE_CASE_END %s %s %.3fs\n',name,result.status,result.seconds);
    end

    function skip(group,name,reason)
        report.results(end+1)=struct('group',group,'test',name,'status','skipped', ...
            'seconds',0,'identifier','','message',reason,'details',''); checkpoint();
    end

    function checkpoint()
        file=fullfile(output,'results.json'); temporary=[file '.tmp']; fid=fopen(temporary,'w');
        assert(fid>=0,'Cannot write acceptance results.'); fileCleanup=onCleanup(@() fclose(fid));
        fwrite(fid,jsonencode(report),'char'); clear fileCleanup
        movefile(temporary,file,'f');
    end
end

function make_image(file,type)
data=reshape(mod(0:41*53*33*4-1,251),[41 53 33 4]);
switch type
    case 'uint16', data=uint16(data)*uint16(200);
    case 'single', data=single(data)/250;
    otherwise, data=uint8(data);
end
info=struct('scale',[.4 .6 1.5],'gamma',.8);
prefs=struct('RGBW',[1 2 3 4],'DIC',NaN,'GFP',NaN,'gamma',.8, ...
    'is_Z_flip',false,'rotate',struct('horizontal',false,'vertical',false));
worm=struct('body','Head','age','Adult','sex','XX','strain','','notes','Disposable software validation fixture');
version=Program.ProgramInfo.version;
save(file,'data','info','prefs','worm','version','-v7.3');
end

function load_processing(app,file)
Program.ProcessingSession.clear(app); app.flags=struct(); app.image_data=[];
Program.Routines.Processing.load_file('image',file);
end

function processing_case(app,base,test)
folder=fullfile(base,[func2str(test) '-' char(java.util.UUID.randomUUID())]); mkdir(folder);
source=fullfile(folder,'source.mat'); make_image(source,'uint16');
load_processing(app,source);
model=Neurons.Image([],'scale',app.image_um_scale);
for point=[7 13 4; 25 40 22]'
    neuron=Neurons.Neuron; neuron.position=point'; neuron.annotation='AVAL';
    neuron.color_readout=zeros(1,4); model.neurons(end+1)=neuron;
end
app.image_neurons=model; app.mp_params.k=2;
Program.Handlers.neurons.save_id_file();
Program.ProcessingSession.capture(app);
test(app);
end

function save_cancel_case(app,base)
folder=fullfile(base,['save-cancel-' char(java.util.UUID.randomUUID())]); mkdir(folder);
source=fullfile(folder,'source.mat'); make_image(source,'uint16');
load_processing(app,source); test_processing_save_cancel(app,string(source));
Program.ProcessingSession.clear(app); app.flags=struct();
end

function format_case(app,source,folder)
assert(isfile(source),'The image source does not exist: %s',source);
if ~isfolder(folder), mkdir(folder); end
folder=fullfile(folder,['run-' char(java.util.UUID.randomUUID())]); mkdir(folder);
[~,name,extension]=fileparts(source); file=fullfile(folder,[name extension]);
copyfile(source,file);
metadata=fullfile(fileparts(source),'metadata.json');
if any(strcmpi(extension,{'.h5','.hdf5'})) && isfile(metadata)
    copyfile(metadata,fullfile(folder,'metadata.json'));
end
Program.ProcessingSession.clear(app); app.flags=struct();
if Tracking.ReferenceWorkflow.supports(file)
    % Paired NWBs open their movie by default; this matrix tests the static image.
    prepared=DataHandling.NeuroPALImage.prepare(file);
    Program.Routines.open(prepared);
else
    Program.Routines.open(file);
    prepared=file;
    if ~strcmpi(extension,'.mat'), prepared=fullfile(folder,[name '.mat']); end
end
assert_image_file(app,prepared);
load_processing(app,file);
baseline=DataHandling.Helpers.npal_mat.open_source(app.image_file);
assert(numel(baseline.dims)>=4 && all(baseline.dims>0));
sampled_z=unique([1 ceil(baseline.dims(3)/2) baseline.dims(3)]);
expected=cell(numel(sampled_z),baseline.dims(4));
for channel=1:baseline.dims(4)
    for z=1:numel(sampled_z)
        expected{z,channel}=baseline.read_plane(baseline.dims(3)+1-sampled_z(z),channel);
        assert(all(isfinite(expected{z,channel}),'all'));
    end
end
scale=app.image_um_scale; originalClass=baseline.source_class;
assert(Program.Helpers.apply_processing_preview_action(app,'mirrorz'));
assert(Program.Routines.Processing.save());
saved=DataHandling.Helpers.npal_mat.open_source(app.image_file);
assert(isequal(saved.dims,baseline.dims) && strcmp(saved.source_class,originalClass));
for channel=1:saved.dims(4)
    for z=1:numel(sampled_z)
        assert(isequaln(saved.read_plane(sampled_z(z),channel),expected{z,channel}));
    end
end
assert(isequal(app.image_um_scale,scale));
assert(~Program.ProcessingSession.dirty(app));
savedFile=app.image_file; load_processing(app,savedFile);
assert(strcmp(app.image_file,savedFile));
Program.Routines.open(savedFile);
assert_image_file(app,savedFile);
actualDims=size(app.image_data); actualDims(end+1:4)=1;
assert(isequal(actualDims,saved.dims));
fprintf('RELEASE_FORMAT_ROUNDTRIP %s dims=%s class=%s\n',extension,mat2str(saved.dims),saved.source_class);
end

function restore_image(app,file)
assert(~isempty(app) && isvalid(app),'The app closed before its original image could be restored.');
assert(~isempty(file) && isfile(file),'The original image is unavailable for restoration.');
Program.ProcessingSession.clear(app); app.flags=struct();
Program.Routines.open(file);
assert_image_file(app,file);
assert(~Program.ProcessingSession.dirty(app),'Restoring the original image left pending processing actions.');
end

function assert_image_file(app,expected)
assert(~isempty(app.image_data) && ~isempty(app.image_file),'The opener did not load an image.');
actual=char(java.io.File(char(app.image_file)).getCanonicalPath());
expected=char(java.io.File(char(expected)).getCanonicalPath());
if ispc, matches=strcmpi(actual,expected); else, matches=strcmp(actual,expected); end
assert(matches,'The opener kept %s instead of loading %s.',actual,expected);
assert(~app.is_opening_file,'The opener did not release its loading state.');
end

function restore_runtime(previousPath,previousFolder)
cd(previousFolder); path(previousPath);
end
