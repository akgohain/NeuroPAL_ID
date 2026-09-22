function test_processing_session(app)
% Check that previews, neuron coordinates, and saved files remain consistent.
assert(strcmp(app.VolumeDropDown.Value, 'Colormap'));
assert(contains(app.image_file, 'processing-audit'), 'Use a disposable processing fixture.');
Program.ProcessingSession.capture(app);
original = app.image_data;
positions = app.image_neurons.get_positions();
annotations = app.image_neurons.get_annotations();
scale = app.image_um_scale;
path = app.image_file; id_path = app.id_file;

% Rotation follows the image without allocating a proxy volume.
app.proc_rot_spinner.Value = 90;
app.flip_lr.Value = false; app.flip_ud.Value = false;
Program.GUIHandling.confirm_processing_rotation(app);
assert(isequal(app.image_data, imrotate(original,90)));
expected = [size(original,2)+1-positions(:,2), positions(:,1), positions(:,3)];
assert(max(abs(app.image_neurons.get_positions()-expected), [], 'all') < 1e-9);
assert(isequal(app.image_neurons.get_annotations(),annotations));
assert(~strcmp(app.id_file,id_path));
on_disk = load(id_path,'neurons');
assert(isequal(on_disk.neurons.get_positions(),positions));
Program.Routines.Processing.reset();
assert(isequal(app.image_data,original));
assert(isequal(app.image_neurons.get_positions(),positions));
assert(isequal(app.image_um_scale,scale));
assert(strcmp(app.id_file,id_path));
assert(strcmp(app.ProcSaveButton.Enable,'off'));

% Mirroring and discarding restore the whole model, including its colors.
Program.GUIHandling.apply_processing_mirror_z(app);
expected = positions; expected(:,3) = size(original,3)+1-expected(:,3);
assert(max(abs(app.image_neurons.get_positions()-expected), [], 'all') < 1e-9);
Program.Routines.Processing.reset();
assert(isequal(app.image_data,original));
assert(isequal(app.image_neurons.get_positions(),positions));

% A failed action keeps both the pixels and annotation file intact.
failed=false;
try, Program.Helpers.apply_processing_preview_action(app,{'hori','invalid'});
catch ME, failed=strcmp(ME.identifier,'NeuroPAL:ProcessingAction'); end
assert(failed && isequal(app.image_data,original));
assert(isequal(app.image_neurons.get_positions(),positions));

% Saving a window applies it once and leaves a clean, repeatable save.
Program.GUIHandling.handle_processing_histogram_slider(app,'tl',[25 220],true,true);
assert(strcmp(app.ProcSaveButton.Enable,'on'));
assert(Program.Routines.Processing.save());
once=app.image_data;
assert(~isequal(once,original));
assert(isequal(app.tl_hist_slider.Value,[0 255]));
assert(~Program.ProcessingSession.dirty(app));
assert(Program.Routines.Processing.save());
assert(isequal(once,app.image_data));
loaded=load(path,'data','info','prefs');
saved=load(id_path,'neurons');
assert(isequal(loaded.data,once));
assert(isequal(saved.neurons.get_annotations(),annotations));
assert(isequal(saved.neurons.get_positions(),positions));
assert(isequaln(saved.neurons.get_colors_readout(),app.image_neurons.get_colors_readout()));

% Pending downsample settings must be reported as unsaved.
app.ProcXYFactorEditField.Value=0.5;
app.ProcZSlicesEditField.Value=size(once,3);
Program.GUIHandling.handle_processing_downsample_field_changed(app);
assert(Program.ProcessingSession.dirty(app));
assert(strcmp(app.ProcSaveButton.Enable,'on'));
assert(Program.Routines.Processing.save());
new_dims=size(app.image_data);
expected=positions;
expected(:,1:2)=(positions(:,1:2)-0.5).*(new_dims(1:2)./size(original,[1 2]))+0.5;
expected=min(max(expected,1),new_dims(1:3));
assert(max(abs(app.image_neurons.get_positions()-expected),[],'all')<1e-9);
assert(abs(app.image_um_scale(1)-scale(1)*size(original,2)/new_dims(2))<1e-12);
assert(isequal(app.image_neurons.get_annotations(),annotations));
Program.Routines.open(path);
assert(isequal(size(app.image_data),new_dims));
assert(max(abs(app.image_neurons.get_positions()-expected),[],'all')<1e-9);
assert(isequal(app.image_neurons.get_annotations(),annotations));
fprintf('PROCESSING_SESSION=PASS\n');
end
