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
% Use acquisition spacing when available, otherwise ask for the missing values.
store = reader.getMetadataStore();
scale = nan(1, 3);
axes = {'X', 'Y', 'Z'};
for axis = 1:3
    value = javaMethod(['getPixelsPhysicalSize' axes{axis}], store, 0);
    if ~isempty(value)
        scale(axis) = double(value.value(ome.units.UNITS.MICROMETER));
    end
end
if zSlices == 1 && ~isfinite(scale(3)), scale(3) = 1; end
if any(~isfinite(scale) | scale <= 0)
    defaults = [0.3 0.3 0.9];
    valid = isfinite(scale) & scale > 0;
    defaults(valid) = scale(valid);
    answer = inputdlg({'X microns/pixel:', 'Y microns/pixel:', 'Z microns/pixel:'}, ...
        'Image Scale', [1 35], arrayfun(@num2str, defaults, 'UniformOutput', false));
    if isempty(answer)
        error('DataHandling:LargeFile:Cancelled', 'Image import canceled.');
    end
    scale = str2double(answer(:).');
    if any(~isfinite(scale) | scale <= 0)
        error('DataHandling:Import:Scale', 'Pixel spacing must contain positive, finite values.');
    end
end
image.scale = scale;

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
% Initialize the channel information.
% Note: assume RGBW format.
image.channels = cell(numChannels,1);
image.colors = nan(numChannels,3);
names = {'Red', 'Green', 'Blue'};
colors = eye(3);
for i = 1:numChannels
    if i <= 3
        image.channels{i} = names{i};
        image.colors(i,:) = colors(i,:);
    else
        image.channels{i} = 'White';
        image.colors(i,:) = [1 1 1];
    end
end
image.dicChannel = nan;

% Initialize the image excitation/emission information.
image.lasers = nan(numChannels,1);
image.emissions = nan(numChannels,1);

% Organize the image volume one plane at a time.
image.pixels = double([reader.getSizeX(); reader.getSizeY(); reader.getSizeZ()]);
image.data = DataHandling.Helpers.bioformats_image.read(reader, filename);
end
