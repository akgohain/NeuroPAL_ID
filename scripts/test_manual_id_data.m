function test_manual_id_data()
% Check manual centers and exports without a full normalized image cache.
rng(29);
data = uint16(randi(2000, 17, 19, 9, 5));
channels = [5 4 1 2];
normalized = Methods.Preprocess.zscore_frame(data(:,:,:,channels));
readout = Methods.ColorReadout(data, channels);
positions = [1 1 1; 8.2 10.6 4; 17 19 9];
expected = Neurons.Image([], 'Head');
actual = Neurons.Image([], 'Head');
for i = 1:size(positions,1)
    point = positions(i,:);
    expected.add_neuron(normalized, point, [3 3 1], [1 1 2]);
    actual.add_neuron(readout, point, [3 3 1], [1 1 2]);
    patch = Methods.Utils.subcube(normalized, round(point), [3 3 1]);
    sampled = Methods.Utils.subcube(readout, round(point), [3 3 1]);
    assert(max(abs(patch-sampled), [], 'all') < 1e-12);
end
assert(isequal(expected.get_positions(), actual.get_positions()));
assert(max(abs(expected.get_colors_readout()-actual.get_colors_readout()), [], 'all') < 1e-12);
new_channels = [1 2 4 5];
expected.update_colors(Methods.Preprocess.zscore_frame(data), channels, new_channels);
actual.update_colors(Methods.ColorReadout(data), channels, new_channels);
assert(max(abs(expected.get_colors_readout()-actual.get_colors_readout()), [], 'all') < 1e-12);

folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
csvfile = fullfile(folder, 'manual.csv');
prefs = struct('GFP', NaN, 'RGBW', channels);
actual.neurons(1).annotation = 'AVAL';
actual.neurons(1).annotation_confidence = 1;
Output.ImageAnalysis.exportID2CSV(csvfile, prefs, data, [], actual, [1;1;2]);
contents = fileread(csvfile);
assert(contains(contents, 'AVAL,1.000000,0,,NaN,'));
rows = splitlines(string(contents));
header = find(startsWith(rows, 'User ID,'));
assert(numel(rows(header+1:end-1)) == size(positions,1));
width = numel(strfind(char(rows(header)), ','));
for row = rows(header+1:end-1)'
    assert(numel(strfind(char(row), ',')) == width);
end

% A late write failure must preserve the previous export.
actual.neurons(2).color_readout = [];
failed = false;
try
    Output.ImageAnalysis.exportID2CSV(csvfile, prefs, data, [], actual, [1;1;2]);
catch
    failed = true;
end
assert(failed && strcmp(fileread(csvfile), contents));
assert(numel(dir(fullfile(folder, '*.csv'))) == 1);
fprintf('MANUAL_ID_DATA=PASS\n');
end
