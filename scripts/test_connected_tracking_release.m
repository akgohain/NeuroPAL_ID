function report = test_connected_tracking_release(c, output_root, cancel_mode)
%TEST_CONNECTED_TRACKING_RELEASE Exercise durable tracking and named exports.
% Use a disposable session; success keeps the completed trial visible.
% Failure restores observations/session settings, not all UI history or caches.
% Native cancellation needs an operator; use timer mode for unattended runs.
assert(~c.Busy && isempty(c.Candidates),'Accept or match the pending candidates first.');
assert(c.Source.nt>=12 && ~isempty(c.Rows),'Open a recording with accepted reference neurons.');
c.checkTrackingSeeds(true);
if nargin<2, output_root=tempdir; end
if nargin<3, cancel_mode='native'; end
cancel_mode=lower(char(string(cancel_mode)));
assert(any(strcmp(cancel_mode,{'native','timer'})),'Choose native or timer cancellation.');
if ~isfolder(output_root), mkdir(output_root); end
folder=tempname(output_root); mkdir(folder);
report_path=fullfile(folder,'report.json');
saved=struct('session',c.Analysis.session(),'observations',c.observations(), ...
    'output_root',c.OutputRoot,'frame',c.Frame.Value,'channel',c.Channel.Value,'slice',c.Slice.Value);
original_names=Tracking.NeuronNames.get(c);
assert(~isempty(original_names) && any(strlength(string({original_names.name}))>0), ...
    'Give at least one reference neuron a name before this named-export trial.');
reference=c.Reference.Value;
first=max(1,reference-4); last=min(c.Source.nt,first+11); first=max(1,last-11);
primary=sort(unique(c.Rows(c.Rows(:,2)==reference,1)));
manual=saved.observations(~strcmp({saved.observations.provenance},'zephir'));
report=struct('status','running','directory',folder,'source',c.Source.file, ...
    'source_id',c.Source.source_id,'frame_range',[first last],'reference_frame',reference, ...
    'seed_count',numel(primary),'window_size',5,'epochs_per_frame',40, ...
    'manual_reference_count',numel(manual), ...
    'manual_rows_in_trial',nnz([manual.t]>=first & [manual.t]<=last), ...
    'reference_frames_in_trial',unique([manual([manual.t]>=first & [manual.t]<=last).t]), ...
    'cancel_mode',cancel_mode,'cancel_requested',false,'cancel_timed_out',false, ...
    'events',{{}},'scope','Actual CPU tracking and software persistence; biological accuracy is not evaluated.');
watch=[]; timer_cleanup=[]; callback_cleanup=[]; phase_failure=[]; final_session=[]; started=tic;
cancel_button=c.Buttons.cancel; original_cancel=cancel_button.ButtonPushedFcn; installed_cancel=[];
try
    c.View.Playback.stop(); c.View.FramePreview.cancel(); c.View.Preview.cancel();
    c.OutputRoot=folder; c.First.Value=first; c.Last.Value=last;
    c.WindowSize.Value=5; c.Epochs.Value=40; c.TrackDirectory='';
    c.Analysis.Controls.signal.Value=c.TrackingChannel.Value;
    c.Analysis.Controls.reference.Value=-1; c.Analysis.Controls.radius.Value='3 3 1';
    c.Analysis.Controls.background.Value=true; c.Analysis.Controls.baseline.Value=20;
    c.Analysis.Controls.motion.Value=10;
    c.checkTrackingSeeds(true); record('configured');

    cancel_started=tic;
    if strcmp(cancel_mode,'native')
        installed_cancel=@native_cancel;
        cancel_button.ButtonPushedFcn=installed_cancel;
        callback_cleanup=onCleanup(@() restore_callback(cancel_button,original_cancel,installed_cancel));
        record('waiting_for_native_cancel_after_first_checkpoint');
    else
        watch=timer('ExecutionMode','fixedSpacing','Period',.25,'BusyMode','drop', ...
            'TimerFcn',@cancel_after_checkpoint);
        timer_cleanup=onCleanup(@() cleanup_timer(watch));
        start(watch);
    end
    failure=run_action(@() c.track());
    cleanup_timer(watch);
    restore_callback(cancel_button,original_cancel,installed_cancel);
    assert(report.cancel_requested,'Cancel the first run after a durable completed window is saved.');
    assert(~report.cancel_timed_out,'Timer cancellation did not see a durable completed window within ten minutes.');
    assert(~isempty(failure) && contains(lower(failure.identifier),'cancel'), ...
        'The tracking cancellation must return a cancellation error.');
    assert(~c.Busy && isfile(fullfile(c.TrackDirectory,'checkpoint.json')));
    manifest=jsondecode(fileread(fullfile(c.TrackDirectory,'tracking.json')));
    assert(~isempty(manifest.completed) && ~strcmp(manifest.state,'complete'));
    report.cancelled_completed_windows=numel(manifest.completed);
    report.tracking_directory=c.TrackDirectory;
    assert_observations(manual,c.observations(),true);
    record('cancelled_after_durable_checkpoint');

    failure=run_action(@() c.loadProgress()); rethrow_if_present(failure);
    assert_observations(manual,c.observations(),true);
    assert_names(original_names,Tracking.NeuronNames.get(c));
    report.loaded_checkpoint_rows=size(c.Rows,1); record('checkpoint_loaded');

    resumed=tic;
    failure=run_action(@() c.track(true)); rethrow_if_present(failure);
    report.resume_seconds=toc(resumed);
    manifest=jsondecode(fileread(fullfile(c.TrackDirectory,'tracking.json')));
    assert(strcmp(manifest.state,'complete') && numel(manifest.completed)>=2);
    assert(manifest.parameters.epochs==40 && manifest.parameters.window_size==5);
    selected=c.Rows(c.Rows(:,2)>=first & c.Rows(:,2)<=last,:);
    assert(size(selected,1)==numel(primary)*(last-first+1));
    for frame=first:last
        assert(isequal(sort(selected(selected(:,2)==frame,1)),primary));
    end
    assert(all(isfinite(selected),'all'));
    assert_observations(manual,c.observations(),true);
    assert_names(original_names,Tracking.NeuronNames.get(c));
    report.completed_windows=numel(manifest.completed); report.tracked_rows=size(selected,1);
    record('resumed_at_default_epochs');

    % Exclude one disposable observation, then restore the original decisions.
    exclusions=c.Excluded; probes=selected(:,[1 2]); available=find(~ismember(probes,exclusions,'rows'),1);
    assert(~isempty(available),'The trial needs one observation that is not already excluded.');
    probe=probes(available,:); time_index=probe(2)-first+1;
    c.Excluded=unique([exclusions;probe],'rows');
    failure=run_action(@() c.extractActivity()); rethrow_if_present(failure);
    file=fullfile(c.ActivityDirectory,'activity.h5');
    ids=double(h5read(file,'/neuron_id')); index=find(ids==probe(1),1);
    flags=h5read(file,'/quality_flags',[index time_index],[1 1]);
    assert(bitand(flags,uint16(2))~=0 && isnan(h5read(file,'/dff',[index time_index],[1 1])));
    report.exclusion_probe=probe; report.exclusion_probe_passed=true;
    c.Excluded=exclusions;
    failure=run_action(@() c.extractActivity()); rethrow_if_present(failure);
    assert(c.activityCurrent()); file=fullfile(c.ActivityDirectory,'activity.h5');
    frames=double(h5read(file,'/frame')); ids=double(h5read(file,'/neuron_id'));
    assert(isequal(frames(:)',first:last));
    assert(isequal(sort(ids(:)),sort(unique(c.Rows(:,1)))));
    dff=double(h5read(file,'/dff')); report.finite_dff_fraction=mean(isfinite(dff),'all');
    assert(any(isfinite(dff),'all'),'The complete activity trial returned no finite measurements.');
    report.activity_directory=c.ActivityDirectory; record('activity_and_exclusion_checked');

    expected_rows=c.Rows; expected_observations=c.observations();
    expected_names=Tracking.NeuronNames.get(c); expected_exclusions=c.Excluded;
    stored_names=string(h5read(file,'/neuron_name'));
    for i=1:numel(ids)
        row=find([expected_observations.track_id]==ids(i),1);
        assert(stored_names(i)==string(expected_observations(row).name));
    end
    exports=fullfile(folder,'exports'); mkdir(exports);
    failure=run_action(@() c.exportActivity(exports)); rethrow_if_present(failure);
    entries=dir(fullfile(exports,'activity-*')); entries=entries([entries.isdir]); assert(numel(entries)==1);
    exported=fullfile(entries(1).folder,entries(1).name);
    for name={'frame','neuron_id','source_time','centers_xyz','signal','dff','quality_flags','neuron_name'}
        dataset=['/' name{1}];
        assert(isequaln(h5read(file,dataset),h5read(fullfile(exported,'activity.h5'),dataset)), ...
            'Activity export changed %s.',dataset);
    end
    imported=c.bridge(struct('action','import','source',c.Source, ...
        'file',fullfile(exported,'tracks','annotations.h5')));
    assert_observations(expected_observations,imported.observations,false);
    report.export_directory=exported; record('activity_and_named_tracks_exported');

    sessions=fullfile(folder,'sessions'); mkdir(sessions);
    failure=run_action(@save_session); rethrow_if_present(failure);
    session_file=fullfile(final_session.directory,'annotations.h5');
    c.Rows=zeros(0,7); c.Candidates=zeros(0,7);
    c.Origins=containers.Map('KeyType','char','ValueType','char');
    Tracking.NeuronNames.set(c,[]); c.TrackDirectory=''; c.ActivityDirectory='';
    failure=run_action(@() c.load(session_file)); rethrow_if_present(failure);
    assert(isequaln(c.Rows,expected_rows) && isequaln(c.Excluded,expected_exclusions));
    assert_observations(expected_observations,c.observations(),false);
    assert_names(expected_names,Tracking.NeuronNames.get(c));
    assert(c.activityCurrent() && c.Epochs.Value==40 && c.WindowSize.Value==5);
    assert(strcmp(c.TrackDirectory,report.tracking_directory));
    actual=c.bridge(struct('action','inspect','file',c.Source.file));
    assert(strcmp(actual.source_id,report.source_id),'The source or metadata changed during testing.');
    report.session_file=session_file; record('session_reloaded_exactly');
    report.status='passed'; report.total_seconds=toc(started);
    c.OutputRoot=saved.output_root; c.View.setStage(4); c.Frame.Value=reference; c.render();
    write_report();
    save(fullfile(folder,'expected-state.mat'),'expected_rows','expected_observations', ...
        'expected_names','expected_exclusions','report','-v7');
    fprintf('CONNECTED_DEFAULT_TRACKING_CANCEL_RESUME_EXPORT_SESSION=PASS %s\n',report_path);
catch ME
    cleanup_timer(watch); restore_callback(cancel_button,original_cancel,installed_cancel);
    report.status='failed'; report.total_seconds=toc(started);
    report.error=struct('identifier',ME.identifier,'message',ME.message,'stack',ME.stack);
    write_report();
    try
        c.Cancelled=false; c.OutputRoot=saved.output_root;
        c.Origins=containers.Map('KeyType','char','ValueType','char');
        c.setRows(saved.observations); c.Analysis.restoreSession(saved.session);
        c.Frame.Value=saved.frame; c.Channel.Value=saved.channel; c.Slice.Value=saved.slice; c.render();
    catch restore_failure
        warning('test:Restore','Could not restore the pre-trial view: %s',restore_failure.message);
    end
    rethrow(ME);
end

    function failure=run_action(action)
        phase_failure=[]; c.safe(@invoke);
        failure=phase_failure;
        function invoke()
            try, action(); catch error_value, phase_failure=error_value; end
        end
    end
    function save_session()
        final_session=c.save(sessions);
    end
    function native_cancel(src,event)
        invoke_callback(original_cancel,src,event);
        report.cancel_requested=true;
        path=fullfile(c.TrackDirectory,'tracking.json');
        if isfile(path)
            try
                state=jsondecode(fileread(path));
                report.native_cancel_completed_windows=numel(state.completed);
            catch
                report.native_cancel_completed_windows=0;
            end
        end
        record('native_cancel_clicked');
    end
    function cancel_after_checkpoint(~,~)
        if report.cancel_requested, return; end
        if toc(cancel_started)>600
            report.cancel_requested=true; report.cancel_timed_out=true; c.cancel(); return;
        end
        path=fullfile(c.TrackDirectory,'tracking.json');
        if ~isfile(path), return; end
        try, state=jsondecode(fileread(path)); catch, return; end
        if ~isempty(state.completed) && ~strcmp(state.state,'complete')
            report.cancel_requested=true; report.cancelled_completed_windows=numel(state.completed);
            c.cancel(); write_report();
        end
    end
    function record(event)
        report.events{end+1}=struct('event',event,'seconds',toc(started)); write_report();
        fprintf('CONNECTED_RELEASE %s %.2fs\n',event,toc(started));
    end
    function write_report()
        temporary=[report_path '.tmp']; fid=fopen(temporary,'w'); assert(fid>=0);
        guard=onCleanup(@() fclose(fid)); fwrite(fid,jsonencode(report),'char'); clear guard
        movefile(temporary,report_path,'f');
    end
end

function cleanup_timer(watch)
if ~isempty(watch) && isvalid(watch), stop(watch); delete(watch); end
end

function restore_callback(button,previous,installed)
if ~isempty(button) && isvalid(button) && ~isempty(installed) && isequal(button.ButtonPushedFcn,installed)
    button.ButtonPushedFcn=previous;
end
end

function invoke_callback(callback,src,event)
if isa(callback,'function_handle'), callback(src,event);
elseif iscell(callback), feval(callback{1},src,event,callback{2:end});
else, error('test:CancelCallback','The Cancel button has no executable callback.'); end
end

function rethrow_if_present(failure)
if ~isempty(failure), rethrow(failure); end
end

function assert_names(expected,actual)
for i=1:numel(expected)
    index=find([actual.id]==expected(i).id,1); assert(~isempty(index));
    assert(isequaln(expected(i),actual(index)),'A reviewed neuron name changed.');
end
end

function assert_observations(expected,actual,subset)
keys=@(rows) [[rows.track_id]' [rows.t]'];
expected_keys=keys(expected); actual_keys=keys(actual);
if ~subset, assert(size(expected_keys,1)==size(actual_keys,1)); end
[present,indices]=ismember(expected_keys,actual_keys,'rows'); assert(all(present));
actual=actual(indices);
for name={'parent_id','x','y','z','confidence','channel','excluded','identity_confidence'}
    assert(isequaln(double([expected.(name{1})]),double([actual.(name{1})])), ...
        'Observation field %s changed.',name{1});
end
for name={'name','provenance','identity_source'}
    assert(isequal(string({expected.(name{1})}),string({actual.(name{1})})), ...
        'Observation field %s changed.',name{1});
end
end
