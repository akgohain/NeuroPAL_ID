function test_tracking_roi()
%TEST_TRACKING_ROI Preserve indexed tracks and empty gaps during import.

frames = [200 4 1 200 7 4];
for kind = {'double', 'single', 'uint16'}
    baseline = struct();
    actual = [];
    for i = 1:numel(frames)
        t = frames(i);
        coords = cast([i i+10 i+20], kind{1});
        previous = struct();
        previous(t).x_slice = coords(1);
        previous(t).y_slice = coords(2);
        previous(t).z_slice = coords(3);
        previous(t).xy_pos = coords([1 2]);
        previous(t).xz_pos = coords([1 3]);
        previous(t).yz_pos = coords([3 2]);
        roi = Program.Helpers.tracking_roi(coords(1),coords(2),coords(3));
        assert(isscalar(roi) && isequaln(roi,previous(t)));
        if i == 1
            baseline = previous;
            actual = roi([]);
            actual(t) = roi;
        else
            baseline(t) = previous(t);
            actual(t) = roi;
        end
        assert(isequaln(actual,baseline));
    end
end
fprintf('TRACKING_ROI=PASS\n');
end
