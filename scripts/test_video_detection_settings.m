function test_video_detection_settings(c)
%TEST_VIDEO_DETECTION_SETTINGS Keep score overrides explicit and method-specific.
assert(~c.Busy);
saved=c.Analysis.session(); cleanup=onCleanup(@() restore(c,saved));
c.Detector.Value='MoE'; Tracking.DetectionSettings.restore(c,[]);
assert(isnan(Tracking.DetectionSettings.threshold(c)));
Tracking.DetectionSettings.open(c);
controls=getappdata(c.Grid,'detection_settings_controls');
assert(controls.defaults.Value && strcmp(controls.score.Enable,'off'));
Tracking.DetectionSettings.restore(c,struct('use_model_default',false,'score_threshold',.35));
assert(Tracking.DetectionSettings.threshold(c)==.35 && strcmp(controls.score.Enable,'on'));
session=jsondecode(jsonencode(c.Analysis.session()));
Tracking.DetectionSettings.restore(c,[]); c.Analysis.restoreSession(session);
assert(Tracking.DetectionSettings.threshold(c)==.35);
c.Detector.Value='Spotiflow'; Tracking.DetectionSettings.refresh(c);
assert(isnan(Tracking.DetectionSettings.threshold(c)) && strcmp(controls.defaults.Enable,'off') && strcmp(controls.score.Enable,'off'));
c.Detector.Value='MoE'; Tracking.DetectionSettings.refresh(c);
assert(Tracking.DetectionSettings.threshold(c)==.35);
c.View.setBusy(true); assert(strcmp(controls.defaults.Enable,'off') && strcmp(controls.score.Enable,'off'));
c.View.setBusy(false); assert(strcmp(controls.score.Enable,'on'));
for value={-1,1.1,Inf,NaN,[.2 .3]}
    expect(@() Tracking.DetectionSettings.restore(c,struct('use_model_default',false,'score_threshold',value{1})), ...
        'Tracking:DetectionSettings');
end
legacy=rmfield(session,'detection_settings'); c.Analysis.restoreSession(legacy);
assert(isnan(Tracking.DetectionSettings.threshold(c)));
fprintf('VIDEO_DETECTION_SETTINGS_DEFAULT_CUSTOM_SESSION=PASS\n');
end

function restore(c,saved)
c.Analysis.restoreSession(saved); c.View.setBusy(false);
window=getappdata(c.Grid,'detection_settings_window');
if ~isempty(window) && isvalid(window), window.Visible='off'; end
end

function expect(callback,identifier)
try, callback(); catch ME, assert(strcmp(ME.identifier,identifier),ME.message); return; end
error('test:MissingError','Expected %s',identifier);
end
