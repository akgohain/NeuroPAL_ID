function test_histmatch_memory()
%TEST_HISTMATCH_MEMORY Check legacy output parity and native-size work products.

levels = reshape(uint8(0:255), 8, 16, 2);
rgb = cat(4, levels, flip(levels, 1), flip(levels, 2));
fixtures = {rgb, zeros(3,4,2,3,'uint8'), ...
    repmat(uint8(127),3,4,2,3), repmat(uint8(1),3,4,2,3), ...
    cat(4, rgb, repmat(uint8(255),8,16,2))};
for i = 1:numel(fixtures)
    input = fixtures{i};
    expected = local_legacy_match(uint64(input));
    actual = Methods.MatchHist(uint64(input));
    assert(isa(actual,'uint64') && isequal(actual,expected));
    actual = Methods.MatchHist(input,'uint8');
    assert(isa(actual,'uint8') && isequal(actual,uint8(expected)));
end

float_rgb = single(rgb) / 255;
float_rgb(1,1,1,1) = NaN;
float_rgb(2,1,1,2) = Inf;
float_rgb(:,:,:,3) = NaN;
constant_rgb = repmat(single(0.25),3,4,2,3);
constant_rgb(1,1,1,1) = NaN;
constant_rgb(2,1,1,2) = Inf;
wide_rgb = cat(4, uint16(rgb)*16, uint16(levels)*257);
source_fixtures = {rgb, uint16(rgb)*16, wide_rgb, int16(rgb)-100, ...
    single(rgb)/255, double(rgb)*3.7-200, float_rgb, constant_rgb, ...
    zeros(3,4,2,3,'uint16'), nan(3,4,2,3,'single'), ...
    repmat(uint64(flintmax)+uint64(1),3,4,2,3)};
channel_orders = {[1 2 3 4], [3 1 2 4], [NaN 0 99]};
for i = 1:numel(source_fixtures)
    input = source_fixtures{i};
    for j = 1:numel(channel_orders)
        order = channel_orders{j};
        expected = local_legacy_run(input,order);
        actual = Methods.run_histmatch(input,order);
        assert(strcmp(class(actual),class(input)));
        assert(isequaln(actual,expected), 'Histogram restoration changed for fixture %d.',i);
    end
end

% One reference frame, including multiple lookup blocks per channel.
plane = repmat(uint8(0:255),175,2);
input = repmat(plane,1,1,25,3);
matched = Methods.MatchHist(input,'uint8');
restored = Methods.run_histmatch(input,[1 2 3]);
for ch = 1:3
    small = repmat(reshape(uint8(0:255),1,256,1),1,1,1,3);
    expected = uint8(local_legacy_match(uint64(small)));
    expected_plane = repmat(expected(:,:,:,ch),175,2);
    assert(isequal(matched(:,:,:,ch),repmat(expected_plane,1,1,25)));
end
assert(isequal(matched,restored));
arrays = whos('input','matched','restored');
assert(all([arrays.bytes] == 175*512*25*3));
assert(all(strcmp({arrays.class},'uint8')));
fprintf('HISTMATCH_MEMORY=PASS native_frame_bytes=%d matched_bytes=%d\n', ...
    arrays(1).bytes,arrays(2).bytes);
end

function newim = local_legacy_match(A)
% Preserve the former uint64 mapping and voxel loop as a small-fixture oracle.
root = fileparts(fileparts(mfilename('fullpath')));
reference = load(fullfile(root,'Data','Models','avg_hist.mat'),'avg_hist');
im_flat = reshape(A,[],size(A,4));
newim = zeros(size(A),'uint64');
M = zeros(3,max(A(:)),'uint64');
for ch = 1:3
    chan_flat = im_flat(:,ch);
    chan_hist = reference.avg_hist(:,ch);
    usemax = double(max(chan_flat(:)));
    counts = histcounts(chan_flat,linspace(0,usemax+1,usemax+2));
    cdf = cumsum(counts)/numel(chan_flat);
    sumref = cumsum(double(transpose(chan_hist)));
    cdf_ref = sumref/max(sumref);
    n_ref_bins = numel(chan_hist);
    for idx = 1:usemax+1
        [~,ind] = min(abs(cdf(idx)-cdf_ref));
        if n_ref_bins <= 1 || usemax <= 0
            mapped_value = 0;
        else
            mapped_value = round(((ind-1)/(n_ref_bins-1))*usemax);
        end
        M(ch,idx) = mapped_value;
    end
    for i = 1:size(A,1)
        for j = 1:size(A,2)
            for k = 1:size(A,3)
                newim(i,j,k,ch) = M(ch,A(i,j,k,ch)+1)-1;
            end
        end
    end
end
end

function restored = local_legacy_run(image_data,RGBW)
rgb_idx = double(RGBW(1:min(3,numel(RGBW))));
rgb_idx = rgb_idx(rgb_idx >= 1 & rgb_idx <= size(image_data,4));
if numel(rgb_idx) < 3
    rgb_idx = 1:min(3,size(image_data,4));
end
source_rgb = image_data(:,:,:,rgb_idx(1:3));
display_rgb = Program.Helpers.to_user_uint8(source_rgb);
matched_uint8 = uint8(local_legacy_match(uint64(display_rgb)));
restored = zeros(size(source_rgb),'like',source_rgb);
for ch = 1:size(source_rgb,4)
    reference = source_rgb(:,:,:,ch);
    ref_double = double(reference);
    finite_mask = isfinite(ref_double);
    if ~any(finite_mask(:)), continue; end
    ref_vals = ref_double(finite_mask);
    ref_min = min(ref_vals,[],'all');
    ref_max = max(ref_vals,[],'all');
    if ~isfinite(ref_min) || ~isfinite(ref_max) || ref_max <= ref_min
        restored(:,:,:,ch) = cast(ref_double,class(reference));
        continue
    end
    matched = double(matched_uint8(:,:,:,ch))/255;
    restored_channel = matched*(ref_max-ref_min)+ref_min;
    if ~isfloat(reference)
        restored_channel = min(max(round(restored_channel),ref_min),ref_max);
    end
    restored(:,:,:,ch) = cast(restored_channel,class(reference));
end
end
