function test_main_detection_inputs(app)
%TEST_MAIN_DETECTION_INPUTS Validate source selection and individual atlas browsing.
controls=getappdata(app.CELL_ID,'main_detection_input');
mode=controls.mode.Value; channels=controls.channels.Value;
cleanup=onCleanup(@() restore(controls,mode,channels));
controls.mode.Value='Single channel'; controls.channels.Value='1';
[input,selected,~]=Program.GUI.MainDetectionInput.get(app);
assert(strcmp(input,'single_channel') && isequal(selected,1));
controls.mode.Value='Multi-channel'; controls.channels.Value='1 2';
[input,selected,~]=Program.GUI.MainDetectionInput.get(app);
assert(strcmp(input,'multi_channel') && isequal(selected,[1 2]));
for value={'1 1','0 2','1 NaN','1 2.5','1'}
    controls.channels.Value=value{1}; failed=false;
    try
        Program.GUI.MainDetectionInput.get(app);
    catch ME
        failed=strcmp(ME.identifier,'Methods:DetectionChannels');
    end
    assert(failed,'Invalid channel selection was accepted.');
end
controls.mode.Value='Single channel'; controls.channels.Value='1 2'; failed=false;
try
    Program.GUI.MainDetectionInput.get(app);
catch ME
    failed=strcmp(ME.identifier,'Methods:DetectionChannels');
end
assert(failed);

window=uifigure('Visible','off'); window_cleanup=onCleanup(@() delete(window));
list=uilistbox(window); use=uibutton(window);
names=cellstr(string(Neurons.Hermaphrodite.getNeurons())); names=names(:);
Program.GUI.NeuronIDChooser.filter(list,use,names,{'IL1'},'Suggested classes','');
assert(all(ismember({'IL1L','IL1R','IL1DL','IL1DR','IL1VL','IL1VR'},list.Items)));
Program.GUI.NeuronIDChooser.filter(list,use,names,{'IL1'},'All neurons','AVAL');
assert(isequal(list.Items,{'AVAL'}));
Program.GUI.NeuronIDChooser.filter(list,use,names,{'IL1'},'All neurons','not-a-neuron');
assert(isempty(list.Items) && strcmp(use.Enable,'off'));
fprintf('MAIN_DETECTION_INPUT_VALIDATION_AND_FULL_ATLAS_BROWSING=PASS\n');
end
function restore(controls,mode,channels)
controls.mode.Value=mode; controls.channels.Value=channels;
end
