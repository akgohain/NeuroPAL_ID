function test_processing_save_cancel(app, source_file)
%TEST_PROCESSING_SAVE_CANCEL Preserve source and pending actions when apply returns false.
arguments
    app
    source_file (1,1) string
end
before = load(source_file,'info','prefs');
app.VolumeDropDown.Value = 'Colormap';
app.proc_image = matfile(source_file);
app.image_file = char(source_file);
app.image_data = [];
app.image_prefs.gamma(:) = 0.73;
pending = struct('ds',true);
app.flags = pending;
% Lazy downsampling is refused through the same false result as cancellation.
Program.Routines.Processing.save();
assert(isequaln(app.flags,pending));
assert(isequaln(load(source_file,'info','prefs'),before));
assert(strcmp(app.image_file,source_file));
fprintf('PROCESSING_SAVE_CANCEL=PASS (refused apply preserves source and actions)\n');
end
