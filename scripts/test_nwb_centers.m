function test_nwb_centers()
%TEST_NWB_CENTERS Check zero-based masks, weighted ROIs, and malformed indices.
file = [tempname '.nwb']; cleanup = onCleanup(@() delete(file));
base = '/processing/NeuroPAL/NeuroPALSegmentation/NeuroPALNeurons';
mask = [0 2 6; 2 0 4; 0 0 2; 1 3 1];
h5create(file, [base '/voxel_mask'], size(mask));
h5write(file, [base '/voxel_mask'], mask);
h5create(file, [base '/voxel_mask_index'], 2);
h5write(file, [base '/voxel_mask_index'], [2; 3]);
[positions, labels] = DataHandling.Helpers.read_nwb_centers(file);
assert(isequal(positions, [1.5 2.5 1; 5 7 3]) && numel(labels) == 2);
h5write(file, [base '/voxel_mask_index'], [2; 2]);
try
    DataHandling.Helpers.read_nwb_centers(file);
    error('test:MissingError', 'Invalid ROI indices were accepted.');
catch ME
    assert(strcmp(ME.identifier, 'DataHandling:NWBImport:Mask'));
end
fprintf('NWB_CENTERS_WEIGHTED_ZERO_BASED_VALIDATION=PASS\n');
end
