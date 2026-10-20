function test_main_artifact_removal(app)
% Check canceled selections, staged pixels and unchanged human annotations.
original_file=app.image_file;
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()restore(app,original_file,folder));
file=fullfile(folder,'artifacts.mat');
data=reshape(uint16(mod((1:21*23*5*5)*37,4093)+1),21,23,5,5);
info=app.image_info; info.scale=[.4 .5 1.2];
prefs=app.image_prefs; prefs.RGBW=[4 2 1 5]; prefs.DIC=NaN; prefs.GFP=NaN; prefs.is_Z_flip=false;
worm=struct('body','Head','age','Adult','sex','XX','strain','','notes','');
version=Program.ProgramInfo.version;
neurons=Neurons.Image([],'Head','scale',info.scale);
neuron=Neurons.Neuron(); neuron.position=[8 8 3]; neuron.annotation='AVAL';
neuron.annotation_confidence=1; neuron.color_readout=[1 1 1 1];
neurons.neurons=neuron;
save(file,'data','info','prefs','worm','version','-v7.3');
mp_params=app.mp_params;
save(fullfile(folder,'artifacts_ID.mat'),'neurons','version','mp_params');
Program.Routines.open(file);
app.TabGroup.SelectedTab=app.NeuroPALIDTab;
Program.GUI.ManualIDService.ensure(app);
original_store=app.image_neurons.annotation_store;
original_positions=app.image_neurons.get_positions();
original_ids=app.id_file;
options=struct('ConfirmFcn',@()'Remove','MaskFcn',@(~)[], 'RefreshFcn',@()[]);

% Missing main pixels fail before the confirmation or polygon window opens.
app.image_data=[];
assert_error(@()Program.ArtifactRemoval.apply(app,'manual',struct('ConfirmFcn',@unexpected)), ...
    'NeuroPAL:ArtifactImage');
app.image_data=data;
old_prefs=app.image_prefs; app.image_prefs=[];
assert_error(@()Program.ArtifactRemoval.apply(app,'automatic'),'NeuroPAL:ArtifactChannels');
app.image_prefs=old_prefs;
check_other_processing_mode(app);

% Canceling either dialog has no checkpoint, pixel or annotation side effects.
snapshot=Program.ProcessingSession.get(app);
processing_tag=app.ImageProcessingTab.Tag;
assert(~Program.ArtifactRemoval.apply(app,'manual',options));
assert(isequaln(snapshot,Program.ProcessingSession.get(app)) && isequal(app.image_data,data));
assert(strcmp(app.ImageProcessingTab.Tag,processing_tag));
options.ConfirmFcn=@()'Cancel'; options.MaskFcn=@(~)unexpected();
assert(~Program.ArtifactRemoval.apply(app,'manual',options));
assert(strcmp(app.id_file,original_ids) && ~Program.ProcessingSession.dirty(app));

% A mask clears only assigned channels, across Z, even over a reviewed neuron.
mask=false(21,23); mask(6:10,6:10)=true;
options.ConfirmFcn=@()'Remove'; options.MaskFcn=@(~)mask;
fprintf('ARTIFACT_FIXTURE_CHANNELS=%s class=%s size=%s\n',mat2str(app.image_prefs.RGBW),class(app.image_data),mat2str(size(app.image_data)));
assert(Program.ArtifactRemoval.apply(app,'manual',options));
assert(isequal(app.TabGroup.SelectedTab,app.NeuroPALIDTab));
expected=data;
for c=[4 2 1 5]
    for z=1:5
        plane=expected(:,:,z,c); plane(mask)=0; expected(:,:,z,c)=plane;
    end
end
if ~isequal(app.image_data,expected) || ~isa(app.image_data,'uint16')
    mismatches=zeros(1,size(data,4));
    for c=1:size(data,4), mismatches(c)=nnz(app.image_data(:,:,:,c)~=expected(:,:,:,c)); end
    error('test:ArtifactPixels','Manual cleanup class=%s mapping=%s mismatches per channel=%s.', ...
        class(app.image_data),mat2str(app.image_prefs.RGBW),mat2str(mismatches));
end
assert(isequal(app.image_data(:,:,:,3),data(:,:,:,3)));
assert_unchanged_annotations(app,original_store,original_positions);
disk=load(file,'data'); assert(isequal(disk.data,data));
assert(isempty(app.image_data_zscored) && Program.ProcessingSession.dirty(app));
assert(~strcmp(app.id_file,original_ids));
Program.Routines.Processing.reset();
assert(isequal(app.image_data,data) && strcmp(app.id_file,original_ids));
assert_unchanged_annotations(app,original_store,original_positions);

% An automatic call uses fresh native pixels, not the cleared z-score cache.
fprintf('ARTIFACT_AFTER_RESET_CHANNELS=%s zcache_empty=%d\n',mat2str(app.image_prefs.RGBW),isempty(app.image_data_zscored));
assert(isempty(app.image_data_zscored));
automatic=Methods.Preprocess.automatic_artifact_mask(data,[4 2 1]);
assert(any(automatic,'all'),'The fixture must contain removable small artifacts.');
assert(Program.ArtifactRemoval.apply(app,'automatic',options));
expected=data;
for c=[4 2 1 5]
    channel=expected(:,:,:,c); channel(automatic)=0; expected(:,:,:,c)=channel;
end
if ~isequal(app.image_data,expected) || ~isempty(app.image_data_zscored)
    mismatches=zeros(1,size(data,4));
    for c=1:size(data,4), mismatches(c)=nnz(app.image_data(:,:,:,c)~=expected(:,:,:,c)); end
    error('test:AutomaticArtifactPixels','Automatic cleanup mapping=%s mismatches per channel=%s zcache_empty=%d.', ...
        mat2str(app.image_prefs.RGBW),mat2str(mismatches),isempty(app.image_data_zscored));
end
assert_unchanged_annotations(app,original_store,original_positions);
disk=load(file,'data'); assert(isequal(disk.data,data));
Program.Routines.Processing.reset();

% A failed redraw rolls pixels, annotations and checkpoint metadata back.
app.selected_neuron=1; Program.GUI.ManualIDController.select(app,1);
Program.GUI.ManualIDController.edited(app,'AVAR?',false);
snapshot=Program.ProcessingSession.get(app);
id_snapshot=getappdata(app.CELL_ID,'manual_id_file_snapshot');
image=getappdata(app.XY,'main_slice_image'); original_image=image.CData;
options.RefreshFcn=@()render_then_fail(app,original_image);
assert_error(@()Program.ArtifactRemoval.apply(app,'manual',options),'test:ArtifactRefresh');
assert(isequal(app.image_data,data) && strcmp(app.id_file,original_ids));
assert(isequaln(snapshot,Program.ProcessingSession.get(app)) && ~Program.ProcessingSession.dirty(app));
assert_unchanged_annotations(app,original_store,original_positions);
image=getappdata(app.XY,'main_slice_image'); assert(isequal(image.CData,original_image));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.text,'AVAR?') && state.dirty && ...
    isequaln(state.context,Program.GUI.ManualIDService.context(app,1)));
assert(isequaln(id_snapshot,getappdata(app.CELL_ID,'manual_id_file_snapshot')));
Program.HeavyJob.assertIdle();

% Invalid channel assignments and bad selections leave the source intact.
options.RefreshFcn=@()[]; options.MaskFcn=@(~)true(2,3);
assert_error(@()Program.ArtifactRemoval.apply(app,'manual',options),'NeuroPAL:ArtifactMask');
app.image_prefs.RGBW=[1 1 2 NaN];
assert_error(@()Program.ArtifactRemoval.apply(app,'automatic',options),'NeuroPAL:ArtifactRGB');
app.image_prefs.RGBW=[1 2 8 NaN];
assert_error(@()Program.ArtifactRemoval.apply(app,'manual',options),'NeuroPAL:ArtifactChannels');
app.image_prefs=old_prefs;
assert(isequal(app.image_data,data) && ~Program.ProcessingSession.dirty(app));

% Staging pixels retains the selected draft and permits its next explicit save.
source_ids=Annotations.Store.fingerprint(original_ids);
options.MaskFcn=@(~)mask;
assert(Program.ArtifactRemoval.apply(app,'manual',options));
state=Program.GUI.ManualIDController.state(app);
assert(strcmp(state.text,'AVAR?') && state.dirty && ...
    isequaln(state.context,Program.GUI.ManualIDService.context(app,1)));
staged_ids=app.id_file;
result=Program.GUI.ManualIDController.assign(app);
assert(result.changed && isfile(staged_ids));
record=Program.GUI.ManualIDService.record(app,1);
assert(strcmp(record.candidates{1},'AVAR') && strcmp(record.certainty,'tentative'));
assert(isequaln(source_ids,Annotations.Store.fingerprint(original_ids)));
Program.Routines.Processing.reset();
assert(isequal(app.image_data,data) && strcmp(app.id_file,original_ids));
assert_unchanged_annotations(app,original_store,original_positions);
fprintf('MAIN_ARTIFACT_CANCEL_PIXELS_IDS_ROLLBACK=PASS\n');
end

function assert_unchanged_annotations(app,store,positions)
assert(isequaln(app.image_neurons.annotation_store.records,store.records));
assert(isequaln(app.image_neurons.annotation_store.evidence,store.evidence));
assert(isequaln(app.image_neurons.get_positions(),positions));
end

function check_other_processing_mode(app)
previous=struct('items',{app.VolumeDropDown.Items},'mode',app.VolumeDropDown.Value, ...
    'flags',app.flags,'pixels',app.image_data,'session',Program.ProcessingSession.get(app), ...
    'id_file',app.id_file,'t',app.proc_tSlider.Value,'rotation',app.proc_rot_spinner.Value, ...
    'xy_factor',app.ProcXYFactorEditField.Value);
cleanup=onCleanup(@()restore_mode(app,previous));
if ~any(strcmp(app.VolumeDropDown.Items,'Video'))
    app.VolumeDropDown.Items=[app.VolumeDropDown.Items {'Video'}];
end
app.VolumeDropDown.Value='Video';
app.flags=struct('artifact_test_video_pending',true);
assert_error(@()Program.ArtifactRemoval.apply(app,'manual',struct('ConfirmFcn',@unexpected)), ...
    'NeuroPAL:ArtifactView');
assert_error(@()Program.ArtifactRemoval.apply(app,'automatic'),'NeuroPAL:ArtifactView');
assert(strcmp(app.VolumeDropDown.Value,'Video'));
assert(isequaln(app.flags,struct('artifact_test_video_pending',true)));
assert(isequal(app.image_data,previous.pixels) && strcmp(app.id_file,previous.id_file));
assert(isequaln(Program.ProcessingSession.get(app),previous.session));
assert(app.proc_tSlider.Value==previous.t && app.proc_rot_spinner.Value==previous.rotation && ...
    app.ProcXYFactorEditField.Value==previous.xy_factor);
end

function restore_mode(app,previous)
app.VolumeDropDown.Value=previous.mode;
app.VolumeDropDown.Items=previous.items;
app.flags=previous.flags;
end

function render_then_fail(app,original)
Program.Routines.ID.render();
image=getappdata(app.XY,'main_slice_image');
assert(~isequal(image.CData,original),'The failure fixture must first paint the masked pixels.');
error('test:ArtifactRefresh','Injected failure after painting masked pixels.');
end

function assert_error(action,identifier)
try
    action(); error('test:MissingError','Expected %s.',identifier);
catch ME
    assert(strcmp(ME.identifier,identifier),'Expected %s; got %s: %s',identifier,ME.identifier,ME.message);
end
end

function answer=unexpected()
error('test:UnexpectedDialog','A rejected operation must not open a dialog.');
answer='Remove';
end

function restore(app,file,folder)
if ~isempty(Program.ProcessingSession.get(app))
    Program.ProcessingSession.discard(app); Program.ProcessingSession.clear(app);
end
Program.Routines.open(file);
if isfolder(folder), rmdir(folder,'s'); end
end
