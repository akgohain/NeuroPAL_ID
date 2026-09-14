function report = test_performance_app(bundle, predictions, output)
%TEST_PERFORMANCE_APP Exercise the real app with saved detector output.
arguments
    bundle (1,1) string
    predictions (1,1) string
    output (1,1) string
end
if exist(output,'dir') ~= 7, mkdir(output); end
started = tic;
app = visualize_light;
cleanup = onCleanup(@() delete(app));
report = struct('startup_seconds',toc(started));
fprintf('PERFORMANCE_APP startup %.3f seconds\n',report.startup_seconds);
source = fullfile(bundle,'examples','original','000715__sub-55-YAaDV_ophys.nwb');
fixture = fullfile(output,'fixture.nwb');
if exist(fixture,'file') ~= 2, copyfile(source,fixture); end
started = tic;
Program.Routines.open(char(fixture));
report.open_seconds = toc(started);
assert(isequal(size(app.image_data),[218 905 39 5]));
view = Program.Helpers.main_display_view_cache(app);
assert(~isfield(view,'render_volume'));
pixels = view.display_slice;
projection = view.max_projection;
usage = whos('pixels','projection');
report.display_pixel_bytes = sum([usage.bytes]);
assert(report.display_pixel_bytes == 2*218*905*3);
response = jsondecode(fileread(predictions));
readout = Methods.ColorReadout(app.image_data(:,:,:,app.image_prefs.RGBW));
sp = Methods.CellposeDetect.centroidsToSupervoxels(response.centroids_yxz,readout);
sp.positions = response.centroids_yxz;
app.image_neurons = Neurons.Image(sp,app.worm.body,'scale',app.image_um_scale');
app.mp_params = response;
app.mp_params.backend = 'detection_moe';
app.mp_params.k = response.num_centroids;
app.image_neurons.neurons(1).annotation = 'Performance test';
app.show_labels = true;
app.ZSlider.Value = Program.Helpers.gui_z_to_data_index( ...
    response.centroids_yxz(1,3),size(app.image_data,3),app.image_prefs.is_Z_flip);
Program.Routines.ID.render();
drawnow;
exportapp(app.CELL_ID,fullfile(output,'loaded.png'));
timings = zeros(2,30);
base_image = findobj(app.XY,'Tag','main_slice_pixels');
assert(isscalar(base_image));
test_main_slider(app);
for labels = [false true]
    app.show_labels = labels;
    app.XY.XLim = [20 90];
    app.XY.YLim = [15 100];
    for i = 1:size(timings,2)
        app.ZSlider.Value = mod(i*7-1,size(app.image_data,3))+1;
        started = tic;
        Program.Routines.ID.get_slice(app.ZSlider,app.image_view,app.XY);
        drawnow;
        timings(labels+1,i) = toc(started);
        current_image = findobj(app.XY,'Tag','main_slice_pixels');
        assert(isequal(current_image,base_image));
        assert(isequal(app.XY.XLim,[20 90]) && isequal(app.XY.YLim,[15 100]));
        assert(numel(app.XY.Children) <= response.num_centroids+2);
        expected = Program.Helpers.get_current_display_slice(app,'main');
        assert(isequal(current_image.CData,expected));
        if ~labels, assert(isempty(findobj(app.XY,'Type','text'))); end
    end
end
report.slice_seconds = timings;
report.slice_p95_seconds = prctile(timings(:),95);
Program.Routines.ID.render();
assert(isequal(app.XY.XLim,[0 size(app.image_data,2)]));
assert(isequal(app.XY.YLim,[0 size(app.image_data,1)]));
assert(isequal(findobj(app.XY,'Tag','main_slice_pixels'),base_image));
app.ZSlider.Value = Program.Helpers.gui_z_to_data_index( ...
    response.centroids_yxz(1,3),size(app.image_data,3),app.image_prefs.is_Z_flip);
Program.Routines.ID.get_slice(app.ZSlider,app.image_view,app.XY);
assert(~isempty(findobj(app.XY,'Type','text')));
input_context = Program.Helpers.main_job_context(app,true);
Program.Helpers.assert_main_job_context(app,input_context);
job = Program.HeavyJob.acquire('Test source edit rejection');
job_cleanup = onCleanup(@() delete(job));
assert_busy(@() Program.Routines.open(char(fixture)));
assert_busy(@() Program.Routines.Processing.load_file('image',char(fixture)));
assert_busy(@() Program.Routines.Videos.load(char(fixture)));
assert_busy(@() Program.Routines.Processing.reset());
assert_busy(@() Program.Routines.Processing.save());
assert_busy(@() Program.Routines.Processing.pass_to_main());
assert_busy(@() Program.Helpers.apply_processing_preview_action(app,{'window'}));
assert_busy(@() app.UpdateFromChild());
Program.Helpers.assert_main_job_context(app,input_context);
clear job_cleanup
position = app.image_neurons.neurons(1).position;
app.image_neurons.neurons(1).position = position+[0.25 0 0];
app.id_file = char(fullfile(output,'edited_ID.mat'));
Program.Handlers.neurons.save_id_file();
saved = load(app.id_file,'neurons','mp_params');
assert(isequal(saved.neurons.neurons(1).position,position+[0.25 0 0]));
assert(strcmp(saved.neurons.neurons(1).annotation,'Performance test'));
report.count = saved.neurons.num_neurons();
report.status = 'passed';
fid = fopen(fullfile(output,'report.json'),'w');
file_cleanup = onCleanup(@() fclose(fid));
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
fprintf('PERFORMANCE_APP=PASS count=%d p95=%.3f seconds\n',report.count,report.slice_p95_seconds);
end

function assert_busy(callback)
try
    callback();
    error('Expected mutation rejection.');
catch ME
    assert(strcmp(ME.identifier,'Program:HeavyJob:Busy'));
end
end
