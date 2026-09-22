function [image, metadata] = imreadVlab(filename)
%IMREADVLAB Read in VLab image data from a given folder.
%
%   [IMAGE, METADATA] = IMREADVLAB(FILENAME)
%
%   Input:
%   folder - the folder containing the data
%
%   Outputs:
%   image - the image, a struct with fields:
%       pixels     = the number of pixels as (x,y,z)
%       scale      = the pixel scale, in microns, as (x,y,z)
%       channels   = the names of the channels
%       colors     = the color for each channel as (R,G,B)
%       dicChannel = the DIC channel number
%       lasers     = the laser wavelength for each channel
%       emissions  = the emsspyeion band for each channel as (min,max)
%       data       = the image data as (x,y,z,channel)
%   metadata - the meta data, a struct with fields:
%       keys      = the meta data keys (the names for the meta data)
%       values    = the meta data values (the values for the meta data)
%       hashtable = a Java Hashtable of keys and their values

% Initialize the image data.
image = [];
metadata = [];

% Assume the data is h5
[folder, ~] = fileparts(filename);

% read metadata
f = fopen(fullfile(folder, "metadata.json"));
chars = fread(f, '*char');
fclose(f);
vlab_meta = jsondecode(chars');

info = h5info(filename, '/data');
dims = double(info.Dataspace.Size);
DataHandling.Helpers.npal_mat.check_materialization(filename, ...
    struct('size', dims(1:4), 'class', 'decoded', ...
    'bytes', prod(dims(1:4)) * info.Datatype.Size));

first_frame = h5read(filename, '/data', ...
    [1, 1, 1, 1, 1], ...
    [vlab_meta.shape_x, vlab_meta.shape_y, vlab_meta.shape_z, vlab_meta.shape_c, 1]);
%image.data = permute(first_frame, [2 1 3 4]);
image.data = first_frame;
image.pixels = [vlab_meta.shape_x, vlab_meta.shape_y, vlab_meta.shape_z];

if isfield(vlab_meta, 'xy_microns')
    
    image.scale = [vlab_meta.xy_microns, ...
        vlab_meta.xy_microns, ...
        vlab_meta.z_microns];
else
    image.scale = [0.4, 0.4, 1.5];
end

nc = vlab_meta.shape_c;
channel_names = {'red', 'green', 'blue', 'RFP', 'GCaMP'};
channel_colors = [1 0 0; 0 1 0; 0 0 1; 1 1 1; 1 0 1];
image.channels = arrayfun(@(c) sprintf('Channel %d', c), 1:nc, 'UniformOutput', false);
image.colors = ones(nc, 3);
known = min(nc, numel(channel_names));
image.channels(1:known) = channel_names(1:known);
image.colors(1:known,:) = channel_colors(1:known,:);
image.dicChannel = nan;
image.lasers = nan(nc,1);
image.emissions = nan(nc,1);

%write metadata
hashtable = java.util.Hashtable;
fNames = fieldnames(vlab_meta);

for k=1:length(fNames) 
        hashtable.put(fNames{k}, vlab_meta.(fNames{k}));
end

keys = arrayfun(@char, hashtable.keySet.toArray, 'UniformOutput', false);
values = cellfun(@(x) hashtable.get(x), keys, 'UniformOutput', false);

metadata.keys = keys;
metadata.values = values;
metadata.hashtable = hashtable;

