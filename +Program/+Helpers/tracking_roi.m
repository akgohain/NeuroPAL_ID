function roi = tracking_roi(x, y, z)
%TRACKING_ROI Build one observation without allocating earlier time points.

roi = struct('x_slice', x, 'y_slice', y, 'z_slice', z, ...
    'xy_pos', [x y], 'xz_pos', [x z], 'yz_pos', [z y]);
end
