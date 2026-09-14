classdef bioformats_image
    %BIOFORMATS_IMAGE Read a static image without retaining intermediate planes.

    methods (Static)
        function [reader, cleanup, metadata] = open(filename)
            reader = bfGetReader(filename);
            cleanup = onCleanup(@() reader.close());
            reader.setSeries(0);
            DataHandling.Helpers.bioformats_image.check(reader, filename);
            metadata = reader.getSeriesMetadata();
            javaMethod('merge', 'loci.formats.MetadataTools', ...
                reader.getGlobalMetadata(), metadata, 'Global ');
        end

        function dims = check(reader, filename)
            dims = double([reader.getSizeX(), reader.getSizeY(), ...
                reader.getSizeZ(), reader.getSizeC()]);
            if reader.getSizeT() ~= 1 || reader.getRGBChannelCount() ~= 1
                error('DataHandling:Import:UnsupportedLayout', ...
                    'Static image import requires one time point and separate channel planes: %s', filename);
            end
            bytes = double(javaMethod('getBytesPerPixel', ...
                'loci.formats.FormatTools', reader.getPixelType()));
            pixels = struct('size', dims, 'class', 'decoded', ...
                'bytes', prod(dims) * max(2, bytes));
            DataHandling.Helpers.npal_mat.check_materialization(filename, pixels);
        end

        function data = read(reader, filename)
            dims = DataHandling.Helpers.bioformats_image.check(reader, filename);
            data = zeros(dims, 'uint16');
            for c = 1:dims(4)
                for z = 1:dims(3)
                    index = reader.getIndex(z - 1, c - 1, 0) + 1;
                    data(:, :, z, c) = bfGetPlane(reader, index)';
                end
            end
        end
    end
end
