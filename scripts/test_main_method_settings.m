function test_main_method_settings(app)
%TEST_MAIN_METHOD_SETTINGS Keep model paths and sensitivity with their backend.
controls=Program.GUIHandling.main_detect_id_controls(app);
backend=Program.GUIPreferences.get_detection_backend(); id=controls.id_dropdown.Value;
keys={'main_detect_params','main_detect_params_method','main_detect_params_by_method', ...
    'main_id_params','main_id_params_method','main_id_params_by_method'};
state=cell(size(keys)); exists=false(size(keys));
for i=1:numel(keys)
    exists(i)=isappdata(app.CELL_ID,keys{i});
    if exists(i), state{i}=getappdata(app.CELL_ID,keys{i}); end
    if exists(i), rmappdata(app.CELL_ID,keys{i}); end
end
cleanup=onCleanup(@() restore(app,controls,backend,id,keys,exists,state));
Program.GUIPreferences.set_detection_backend('detection_moe');
Program.GUIHandling.main_method_params(app,'detect');
setappdata(app.CELL_ID,'main_detect_params',struct('bundle_path','moe-fixture','score_threshold','0.4'));
Program.GUIPreferences.set_detection_backend('spotiflow_supervised');
assert(isempty(fieldnames(Program.GUIHandling.main_method_params(app,'detect'))));
setappdata(app.CELL_ID,'main_detect_params',struct('bundle_path','spotiflow-fixture'));
Program.GUIPreferences.set_detection_backend('detection_moe');
params=Program.GUIHandling.main_method_params(app,'detect');
assert(strcmp(params.bundle_path,'moe-fixture') && strcmp(params.score_threshold,'0.4'));
Program.GUIPreferences.set_detection_backend('spotiflow_supervised');
params=Program.GUIHandling.main_method_params(app,'detect');
assert(strcmp(params.bundle_path,'spotiflow-fixture') && ~isfield(params,'score_threshold'));
controls.id_dropdown.Value='GAT'; Program.GUIHandling.main_method_params(app,'id');
setappdata(app.CELL_ID,'main_id_params',struct('checkpoint_path','gat-fixture'));
controls.id_dropdown.Value='CRF';
Program.GUIHandling.update_main_id_workflow_state(app);
assert(strcmp(controls.id_dropdown.Value,'CRF'));
assert(strcmp(Program.GUIHandling.main_method_identity(app,'id'),'crf'));
assert(isempty(fieldnames(Program.GUIHandling.main_method_params(app,'id'))));
setappdata(app.CELL_ID,'main_id_params',struct('bundle_path','crf-fixture'));
controls.id_dropdown.Value='GAT'; params=Program.GUIHandling.main_method_params(app,'id');
assert(strcmp(params.checkpoint_path,'gat-fixture') && ~isfield(params,'bundle_path'));
assert(isnan(Program.GUIHandling.moe_score_threshold('default')));
assert(Program.GUIHandling.moe_score_threshold('.4')==.4);
for raw={'-1','1.1','oops','NaN','Inf'}
    caught=false;
    try, Program.GUIHandling.moe_score_threshold(raw{1});
    catch ME, caught=strcmp(ME.identifier,'Methods:MoEScoreThreshold'); end
    assert(caught,'An invalid sensitivity setting was accepted.');
end
fprintf('MAIN_METHOD_SETTINGS_ISOLATION_SENSITIVITY=PASS\n');
end
function restore(app,controls,backend,id,keys,exists,state)
Program.GUIPreferences.set_detection_backend(backend); controls.id_dropdown.Value=id;
for i=1:numel(keys)
    if exists(i), setappdata(app.CELL_ID,keys{i},state{i});
    elseif isappdata(app.CELL_ID,keys{i}), rmappdata(app.CELL_ID,keys{i}); end
end
Program.GUIHandling.sync_main_detect_id_controls(app);
Program.GUI.MainDetectionInput.refresh(app);
end
