function test_main_geometry_actions(app)
% Check main-menu rotations against an image landmark and saved calibration.
original_file = app.image_file;
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() restore(original_file, folder));
file = fullfile(folder, 'landmark.mat');
data = zeros(9, 13, 5, 4, 'uint16');
data(3, 9, 2, :) = 1000;
info = app.image_info; info.scale = [.3 .7 1.5];
prefs = app.image_prefs; prefs.RGBW = [1 2 3 4];
prefs.DIC = NaN; prefs.GFP = NaN; prefs.is_Z_flip = false;
worm = struct('body', 'Head', 'age', 'Adult', 'sex', 'XX', 'strain', '', 'notes', '');
version = Program.ProgramInfo.version;
neurons = Neurons.Image([], 'Head', 'scale', info.scale);
neuron = Neurons.Neuron(); neuron.position = [3 9 2]; neuron.annotation = 'AVAL';
neuron.color_readout = [1 1 1 1]; neurons.neurons = neuron;
save(file, 'data', 'info', 'prefs', 'worm', 'version', '-v7.3');
mp_params = app.mp_params;
save(fullfile(folder, 'landmark_ID.mat'), 'neurons', 'version', 'mp_params');
Program.Routines.open(file);
app.TabGroup.SelectedTab = app.NeuroPALIDTab;
menus = {'RotateAllHorizontalMenu', 'RotateAllHorizontalMenu', ...
    'RotateAllVerticalMenu', 'RotateAllVerticalMenu', ...
    'RotateAllClockwiseMenu', 'RotateAllAntiClockwiseMenu'};
for i = 1:numel(menus)
    menu = app.(menus{i}); menu.MenuSelectedFcn(menu, []);
    [~, peak] = max(reshape(app.image_data(:, :, :, 1), [], 1));
    [y, x, z] = ind2sub(size(app.image_data, 1:3), peak);
    assert(isequal(app.image_neurons.neurons(1).position, [y x z]));
    assert(isequal(app.image_um_scale(:), app.image_info.scale(:)));
    assert(isequal(app.image_neurons.scale(:), app.image_info.scale(:)));
    assert(isempty(app.image_data_zscored));
    saved = load(file, 'data', 'info');
    assert(isequal(saved.data, app.image_data));
    assert(isequal(saved.info.scale, app.image_info.scale));
end
assert(isequal(app.image_data, data) && isequal(app.image_info.scale, info.scale));
fprintf('MAIN_GEOMETRY_MENUS_PIXELS_CENTERS_CALIBRATION=PASS\n');
end

function restore(file, folder)
Program.Routines.open(file);
rmdir(folder, 's');
end
