function test_moe_app(bundle, output)
%TEST_MOE_APP Real App Designer open/detect/edit/save acceptance on NWB fixture.
arguments
    bundle (1,1) string
    output (1,1) string
end
mkdir(output);
source = fullfile(bundle, 'examples', 'original', '000715__sub-55-YAaDV_ophys.nwb');
fixture = fullfile(output, '000715__sub-55-YAaDV_ophys.nwb');
if exist(fixture, 'file') ~= 2, copyfile(source, fixture); end
previous_backend = Program.GUIPreferences.get_detection_backend();
prefs_cleanup = onCleanup(@() local_restore_backend(previous_backend));
app = visualize_light;
cleanup = onCleanup(@() delete(app));
Program.Routines.open(char(fixture));
assert(~isempty(app.image_data), 'NWB did not open');
assert(isequal(size(app.image_data), [218,905,39,5]), 'Unexpected MATLAB YXZC layout');
assert(isequal(double(app.image_prefs.RGBW(:)'), [5,4,1,2]), 'Incorrect RGBW channels');
assert(isempty(app.image_neurons) || app.image_neurons.num_neurons() == 0, 'Fixture imported annotations before detection');
controls = Program.GUIHandling.main_detect_id_controls(app);
assert(any(strcmp(controls.detect_dropdown.ItemsData, 'detection_moe')));
controls.detect_dropdown.Value = 'detection_moe';
controls.detect_dropdown.ValueChangedFcn(controls.detect_dropdown, []);
assert(strcmp(Program.GUIPreferences.get_detection_backend(), 'detection_moe'));
setappdata(app.CELL_ID, 'main_detect_params', struct('bundle_path', char(bundle), ...
    'dataset_id', '000715', 'device', 'cpu'));
Program.GUIHandling.update_main_id_workflow_state(app);
drawnow;
exportapp(app.CELL_ID, fullfile(output, 'opened.png'));
app.AutoDetectButton.ButtonPushedFcn(app.AutoDetectButton, []);
assert(~isempty(app.image_neurons) && app.image_neurons.num_neurons() > 0, 'MoE did not import neurons');
assert(strcmp(app.mp_params.backend, 'detection_moe'));
positions = app.image_neurons.get_positions();
assert(isequal(positions, app.mp_params.centroids_yxz), 'Import changed detector centers');
assert(size(positions,1) == app.mp_params.num_centroids, 'App removed MoE detections');
response = jsondecode(fileread(fullfile(app.mp_params.output_dir, 'response.json')));
assert(isequal(positions, response.centroids_yxz));
% An actual model edit, persisted using the same save function as the app.
original_position = app.image_neurons.neurons(1).position;
app.image_neurons.neurons(1).position = original_position + [0.25,0,0];
app.image_neurons.neurons(1).annotation = 'MoE integration test';
app.id_file = char(fullfile(output, 'moe_edit_ID.mat'));
Program.Handlers.neurons.save_id_file();
saved = load(app.id_file, 'neurons', 'mp_params');
assert(isequal(saved.neurons.neurons(1).position, original_position+[0.25,0,0]));
assert(strcmp(saved.neurons.neurons(1).annotation, 'MoE integration test'));
assert(saved.neurons.num_neurons() == size(positions,1));
Program.Routines.ID.render();
drawnow;
exportapp(app.CELL_ID, fullfile(output, 'detected-edited.png'));
report = struct('status', 'passed', 'count', size(positions,1), ...
    'dataset', '000715', 'saved_id_file', app.id_file, 'inference_output', app.mp_params.output_dir, ...
    'checks', {{'original NWB open', 'no imported annotations', 'RGBW ordering', ...
    'full expert inference', 'subpixel center import', 'no duplicate pruning', 'edit and save reload'}});
fid = fopen(fullfile(output, 'app-report.json'), 'w');
fwrite(fid, jsonencode(report, PrettyPrint=true)); fclose(fid);
fprintf('MOE_APP_ACCEPTANCE=PASS count=%d\n', size(positions,1));
end

function local_restore_backend(backend)
Program.GUIPreferences.set_detection_backend(backend);
Program.GUIPreferences.save();
end
