function newim = MatchHist(A, output_class)
%MATCHHIST Match RGB histograms using a lookup table.
% Output class defaults to uint64 for existing callers.
arguments
    A
    output_class (1,1) string = "uint64"
end

method_dir = fileparts(mfilename('fullpath'));
avg_hist_path = fullfile(method_dir, '..', 'Data', 'Models', 'avg_hist.mat');
reference = load(avg_hist_path, 'avg_hist');
avg_hist = reference.avg_hist;

im_flat = reshape(A, [], size(A,4));
newim = zeros(size(A), char(output_class));
channel_values = size(im_flat, 1);
% Limit double lookup indices to 8 MiB.
block_values = 1024 * 1024;

for ch = 1:3
    chan_flat = im_flat(:,ch);
    chan_hist = avg_hist(:,ch);
    usemax = double(max(chan_flat(:)));
    counts = histcounts(chan_flat, linspace(0, usemax+1, usemax+2));
    cdf = cumsum(counts) / numel(chan_flat);
    sumref = cumsum(double(transpose(chan_hist)));
    cdf_ref = sumref / max(sumref);

    % Preserve nearest-CDF matching and the first minimum on ties.
    mapping = zeros(usemax+1, 1, char(output_class));
    n_ref_bins = numel(chan_hist);
    for idx = 1:usemax+1
        [~, ind] = min(abs(cdf(idx) - cdf_ref));
        if n_ref_bins <= 1 || usemax <= 0
            mapped_value = 0;
        else
            mapped_value = round(((ind - 1) / (n_ref_bins - 1)) * usemax);
        end
        % Preserve the legacy uint64 subtraction's saturation at zero.
        mapping(idx) = max(mapped_value - 1, 0);
    end

    channel_offset = (ch - 1) * channel_values;
    for first = 1:block_values:channel_values
        last = min(first + block_values - 1, channel_values);
        % Convert before adding one to avoid uint8 saturation at 255.
        indices = double(chan_flat(first:last)) + 1;
        newim(channel_offset + (first:last)) = mapping(indices);
    end
end
end
