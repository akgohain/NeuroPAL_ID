function bit_depth = h5_video_bit_depth(path, dataset, start, count)
%H5_VIDEO_BIT_DEPTH Infer bit depth from one H5 sample.

bit_depth = [];
sample = h5read(path, dataset, start, count);
switch class(sample)
    case 'uint8'
        bit_depth = 8;
    case 'uint16'
        bit_depth = 16;
    case 'uint32'
        bit_depth = 32;
    case 'uint64'
        bit_depth = 64;
end
end
