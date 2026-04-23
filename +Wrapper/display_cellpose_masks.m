function display_cellpose_masks(masksMatPath, varargin)
%DISPLAY_CELLPOSE_MASKS  Z-MIP: RGB and Cellpose labels from *masks.mat
%
%   For files produced by +CellPose/scripts/matlab_cellpose_cli.py:
%   variables image_XYZC, masks_3D, masks_stitched (3rd dim = Z).
%
%   USAGE
%     display_cellpose_masks                    % file picker
%     display_cellpose_masks(<full path to *_masks.mat>)   % must exist on disk
%     <full path> example (this repo on your machine):
%       /Users/swethasaseendran/Documents/MATLAB/DEV/NeuroPAL_ID/+CellPose/Output/000715_sub11_masks.mat
%     display_cellpose_masks(p, 'ZDim', 3)   % default
%     display_cellpose_masks(p, 'PlotCentroids', true)  % centroid marks on MIPs
%
%   Name-Value
%     'PlotCentroids' — (default false) if true, mark each instance centroid on the
%         Z-MIP (mean of row/col in the 2D label MIP, matching the displayed image).
%         Label 0 is background and is ignored.
%
%   From command line, call as a package (repo root on path), e.g.:
%     Wrapper.display_cellpose_masks( ...
%       '/Users/swethasaseendran/Documents/MATLAB/DEV/NeuroPAL_ID/+CellPose/Output/000715_sub11_masks.mat', ...
%       'PlotCentroids', true);
%
%   If RGB looks transposed vs Python, your .mat may be (X,Y,3,Z) (scipy) vs (X,Y,Z,3) — this
%   function permutes the former to (X,Y,Z,3) so Z is always dim 3. Masks stay (X,Y,Z), Z=3.

p = inputParser;
addParameter(p, 'ZDim', 3, @(n) isnumeric(n) && isscalar(n) && n == floor(n) && n >= 1);
addParameter(p, 'PlotCentroids', false, @islogical);
parse(p, varargin{:});
plotCent = p.Results.PlotCentroids;
% ZDim (default 3) reserved for custom layouts; auto-permute above handles (X,Y,3,Z) -> (X,Y,Z,3)
useIpt = exist('label2rgb', 'file') == 2 && exist('imoverlay', 'file') == 2;
cc = [0.1 0.9 0.9];  % plot color: cyan, visible on RGB and yellow overlay

if nargin < 1 || (isstring(masksMatPath) && strlength(masksMatPath) == 0) || ...
   (ischar(masksMatPath) && isempty(masksMatPath))
    [f, pth] = uigetfile('*_masks.mat', 'Select *_masks.mat (matlab_cellpose_cli output)');
    if isequal(f, 0)
        return;
    end
    masksMatPath = fullfile(pth, f);
end

if exist(masksMatPath, 'file') ~= 2
    error('display_cellpose_masks:NotFound', 'File not found: %s', char(masksMatPath));
end

S = load(masksMatPath, 'image_XYZC', 'masks_3D', 'masks_stitched');
if ~isfield(S, 'image_XYZC') || ~isfield(S, 'masks_3D')
    error('display_cellpose_masks:Format', 'Need image_XYZC and masks_3D: %s', ...
        char(masksMatPath));
end

I = S.image_XYZC;
M3 = S.masks_3D;
if isfield(S, 'masks_stitched') && ~isempty(S.masks_stitched)
    Ms = S.masks_stitched;
else
    Ms = [];
end

if length(size(I)) ~= 4
    error('display_cellpose_masks:Shape', 'image_XYZC must be 4D (X,Y,Z,C) or (X,Y,C,Z), got: %s', mat2str(size(I)));
end

% Canonical layout: (X,Y,Z,3). SciPy v7 .mat can appear in MATLAB as (X,Y,3,Z).
S4 = size(I);
if S4(3) == 3 && S4(4) > 1 && S4(4) ~= 3
    I = permute(I, [1, 2, 4, 3]);
end
% After permute, I is (X,Y,Z,3). Masks may be (X,Y,Z) or (Z,X,Y) (Cellpose); Z-MIP
% must max along the axis whose length equals size(I,3).
Xn = size(I, 1);
Yn = size(I, 2);
Zd = size(I, 3);
% After (X,Y,3,Z) -> (X,Y,Z,3) permute above, depth is always dimension 3
zDimI = 3;
m3MIP = local_mip_mask_xy(M3, Xn, Yn, Zd);
if ~isempty(Ms)
    mSMIP = local_mip_mask_xy(Ms, Xn, Yn, Zd);
else
    mSMIP = [];
end

imgMIP = max(I, [], zDimI);
imgMIP = squeeze(imgMIP);
% imshow must receive MxNx3 uint8 (or MxN grayscale); never MxNxZ with Z>3
if size(imgMIP, 3) ~= 3
    error( ...
        'display_cellpose_masks:Imshow', ...
        ['MIP of image is not MxNx3 (got size %s). ' ...
         'If .mat is (X,Y,Z,3) try not permuting, or set ZDim (see help). ' ...
         '0-based Python axes are 1-based in MATLAB; this error is the array shape, not 0/1.'], ...
        mat2str(size(imgMIP)));
end
imgMIP = im2uint8(imgMIP);

[cx, cy, ~] = local_centroids_from_label2d_mip(m3MIP);

f = figure('Name', 'Cellpose Z-MIP', 'Color', 'w', 'NumberTitle', 'off');
tiled = tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
title(tiled, 'Cellpose outputs (Z-Maximum Intensity Projection)');

nexttile(tiled);
imshow(imgMIP, []);
if plotCent
    local_hold_scatter_centroids(gca, cx, cy, cc, 1);
end
title('Volume RGB (Z-MIP)');

nexttile(tiled);
% R2020b+: 4th arg to label2rgb must be 'shuffle' | 'noshuffle' | 'contrasting-neighbors' (not 'Shuffled')
if useIpt
    imshow(label2rgb(m3MIP, parula(256), [0.82 0.82 0.82], 'shuffle'), []);
else
    imagesc(m3MIP);
    axis image;
    set(gca, 'YDir', 'normal', 'XTick', [], 'YTick', []);
    colormap(gray(256));
    colorbar;
end
if plotCent
    local_hold_scatter_centroids(gca, cx, cy, cc, 0.4);
end
title('3D run — labels (Z-MIP)');

nexttile(tiled);
if ~isempty(mSMIP) && any(mSMIP(:) > 0)
    if useIpt
        imshow(label2rgb(mSMIP, parula(256), [0.82 0.82 0.82], 'shuffle'), []);
    else
        imagesc(mSMIP);
        axis image;
        set(gca, 'YDir', 'normal', 'XTick', [], 'YTick', []);
        colormap(gray(256));
        colorbar;
    end
    if plotCent
        [cxs, cys, ~] = local_centroids_from_label2d_mip(mSMIP);
        local_hold_scatter_centroids(gca, cxs, cys, [1 0.3 0.1], 0.5);
    end
    title('2D+stitch — labels (Z-MIP)');
else
    axis off;
    text(0.5, 0.5, 'No masks\_stitched in file', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center');
    title('2D+stitch');
end

nexttile(tiled);
if useIpt
    ovl = imoverlay(imgMIP, m3MIP > 0, 'yellow');
    imshow(ovl, []);
else
    b = im2double(imgMIP);
    w = m3MIP > 0;
    b = b * 0.65;
    b(:, :, 1) = b(:, :, 1) + 0.35 * double(w);
    b(:, :, 2) = b(:, :, 2) + 0.35 * double(w);
    imshow(b, []);
end
if plotCent
    local_hold_scatter_centroids(gca, cx, cy, [0.05 0.1 0.6], 1.2);
end
title('RGB Z-MIP + 3D foreground (yellow)');

end

function [cx, cy, ids] = local_centroids_from_label2d_mip(m2d)
% 2D label MIP: plot coords are (col,row) = (x, y) for imshow, i.e. mean(c) and mean(r)
L = double(m2d);
ids = unique(L(:));
ids = ids(ids > 0);
n = numel(ids);
cx = nan(n, 1);
cy = nan(n, 1);
for t = 1:n
    [r, c] = find(L == ids(t));
    if isempty(r)
        continue
    end
    cx(t) = mean(c);
    cy(t) = mean(r);
end
ke = isfinite(cx) & isfinite(cy);
ids = ids(ke);
cx = cx(ke);
cy = cy(ke);
end

function local_hold_scatter_centroids(ax, cx, cy, col, mk)
% Plot (+) on image axes. mk scales markers.
if isempty(cx) || isempty(cy) || numel(cx) ~= numel(cy)
    return
end
hold(ax, 'on');
hL = plot(ax, cx, cy, '+', 'Color', col, 'MarkerSize', 4 * max(mk, 0.1), 'LineWidth', 1.4 * max(mk, 0.1), ...
    'Clipping', 'on');
hold(ax, 'off');
if isgraphics(hL)
    uistack(hL, 'top');
end
end

function mip = local_mip_mask_xy(M, x, y, zd)
% Z-MIP of 3D mask to (x,y) to match image; M may be (x,y,zd) or (zd,x,y), etc.
M = double(M);
if ndims(M) > 3
    M = squeeze(M);
end
if ~ismember(zd, size(M))
    error('display_cellpose_masks:MaskZ', 'Mask size %s has no length zd=%d', mat2str(size(M)), zd);
end
d = find(size(M) == zd, 1, 'first');
mip = max(M, [], d);
% max along one axis of a 3D array can leave a singleton (e.g. 1x525x147) — must squeeze
mip = squeeze(mip);
if isequal(size(mip), [y, x])
    mip = mip.';
end
if ~isequal(size(mip), [x, y])
    error('display_cellpose_masks:MaskMIP', 'MIP %s does not match image XY (%d,%d)', mat2str(size(mip)), x, y);
end
end
