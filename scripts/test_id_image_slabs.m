function test_id_image_slabs()
% Check single-slice exports, slab boundaries, and flipped display ranges.
assert(isequal(Output.Illustration.idImageSlabs(1, 1, 1, 1, false), [1 1]));
assert(isequal(Output.Illustration.idImageSlabs(1, 10, 3, 10, false), ...
    [1 3; 4 6; 7 9; 10 10]));
assert(isequal(Output.Illustration.idImageSlabs(3, 8, 2, 10, true), ...
    [7 8; 5 6; 3 4]));
for flipped = [false true]
    slabs = Output.Illustration.idImageSlabs(2, 9, 3, 12, flipped);
    slices = [];
    for i = 1:size(slabs, 1)
        slices = [slices slabs(i, 1):slabs(i, 2)]; %#ok<AGROW>
    end
    assert(numel(slices) == 8 && numel(unique(slices)) == 8);
    if flipped, assert(isequal(sort(slices), 4:11));
    else, assert(isequal(sort(slices), 2:9)); end
end
fprintf('ID_IMAGE_SLICE_BOUNDARIES=PASS\n');
end
