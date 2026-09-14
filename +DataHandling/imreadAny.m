function [image, metadata] = imreadAny(filename)
%IMREADANY Read in any image format (all purpose reader).
%
%   [IMAGE, METADATA] = IMREADANY(FILENAME)
%
%   Input:
%   filename - the filename of the ND2 image
%
%   Outputs:
%   image - the image, a struct with fields:
%       pixels     = the number of pixels as (x,y,z)
%       scale      = the pixel scale, in meters, as (x,y,z)
%       channels   = the names of the channels
%       colors     = the color for each channel as (R,G,B)
%       dicChannel = the DIC channel number
%       lasers     = the laser wavelength for each channel
%       emissions  = the emssion band for each channel as (min,max)
%       data       = the image data as (x,y,z,channel)
%   metadata - the meta data, a struct with fields:
%       keys      = the meta data keys (the names for the meta data)
%       values    = the meta data values (the values for the meta data)
%       hashtable = a Java Hashtable of keys and their values

% Open the file.
[reader, reader_cleanup, hashtable] = ...
    DataHandling.Helpers.bioformats_image.open(filename);

% Initialize the image data.
image = [];
metadata = [];

% Extract the metadata.
keys = arrayfun(@char, hashtable.keySet.toArray, 'UniformOutput', false);
values = cellfun(@(x) hashtable.get(x), keys, 'UniformOutput', false);

% Get the image dimensions.
zSlices = double(reader.getSizeZ());
numChannels = double(reader.getSizeC());
if numChannels < 3
    error('DataHandling:Import:Channels', ...
        '"%s" has less than 3 color channels!', filename);
end

% Get the image scale.
scale = inputdlg({'X & Y microns/pixel:','Z microns/pixel:'}, ...
    'Image Scale', [1 35], {'0.3','0.9'});
if isempty(scale)
    return;
else
    xy_scale = str2double(scale{1});
    z_scale = str2double(scale{2});
    image.scale = [xy_scale, xy_scale, z_scale];
end

% Get the image size.
yPixels = double(reader.getSizeY());
xPixels = double(reader.getSizeX());

% Organize the metadata.
metadata.keys = keys;
metadata.values = values;
metadata.hashtable = hashtable;

% Initialize the image volume information.
image.pixels = [ ...
    xPixels; ...
    yPixels; ...
    zSlices];
image.scale = [ ...
    xy_scale; ...
    xy_scale; ...
    z_scale];

% Initialize the channel information.
% Note: assume RGBW format.
image.channels = cell(numChannels,1);
image.colors = nan(numChannels,3);
image.channels{1} = 'Red';
image.channels{2} = 'Green';
image.channels{3} = 'Blue';
image.colors(1,:) = [1,0,0];
image.colors(2,:) = [0,1,0];
image.colors(3,:) = [0,0,1];
for i = 4:numChannels
    image.colors(i,:) = [1,1,1];
    image.channels{i} = 'White';
end
image.dicChannel = nan;

% Initialize the image excitation/emission information.
image.lasers = nan(numChannels,1);
image.emissions = nan(numChannels,1);

% Organize the image volume one plane at a time.
image.pixels = double([reader.getSizeX(); reader.getSizeY(); reader.getSizeZ()]);
image.data = DataHandling.Helpers.bioformats_image.read(reader, filename);
end
