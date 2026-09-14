function test_color_readout()
% Compare sampled readouts with the legacy whole-volume z-score definition.
rng(17);
data = rand(11,13,7,4);
data(1,1,1,1) = NaN;
data(:,:,:,2) = 0;
data(:,:,:,3) = NaN;
positions = [1 1 1; 5 6 4; 11 13 7; -1 30 10];
expected = Methods.CellposeDetect.centroidsToSupervoxels(positions, Methods.Preprocess.zscore_frame(data));
actual = Methods.CellposeDetect.centroidsToSupervoxels(positions, Methods.ColorReadout(data));
assert(isequal(actual.positions,expected.positions));
assert(isequal(isnan(actual.color),isnan(expected.color)));
finite = isfinite(expected.color);
assert(all(abs(actual.color(finite)-expected.color(finite)) < 1e-12));
assert(isequaln(actual.color,actual.color_readout));
for type = {'uint8','uint16','single'}
    data = cast(randi(255,9,10,5,3),type{1});
    expected = Methods.CellposeDetect.centroidsToSupervoxels(positions, Methods.Preprocess.zscore_frame(data));
    actual = Methods.CellposeDetect.centroidsToSupervoxels(positions, Methods.ColorReadout(data));
    assert(max(abs(actual.color-expected.color),[],'all') < 1e-12);
end
empty = Methods.CellposeDetect.centroidsToSupervoxels(zeros(0,3), Methods.ColorReadout(data));
assert(isequal(size(empty.color),[0 3]));
fprintf('COLOR_READOUT=PASS\n');
end
