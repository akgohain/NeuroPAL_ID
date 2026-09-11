classdef npal_mat
    %NPAL_MAT Inspect NeuroPAL MAT files without materializing image pixels.

    methods (Static)
        function fields = load_fields(path, include_data)
            names = {'version', 'info', 'prefs', 'worm'};
            if include_data
                names = [{'data'}, names];
            end
            variables = whos('-file', path);
            if include_data
                pixels = variables(strcmp({variables.name}, 'data'));
                if ~isempty(pixels)
                    DataHandling.Helpers.npal_mat.check_materialization(path, pixels);
                end
            end
            names = intersect(names, {variables.name}, 'stable');
            if isempty(names)
                fields = struct();
            else
                fields = load(path, names{:});
            end
        end

        function source = open_source(path)
            variables = whos('-file', path);
            names = {variables.name};
            if ~all(ismember({'data', 'info', 'prefs'}, names))
                error('DataHandling:NeuroPALImage:InvalidMAT', ...
                    'Misformatted NeuroPAL file: "%s"', path);
            end
            pixels = variables(strcmp(names, 'data'));
            supports_partial = H5F.is_hdf5(path);
            if ~supports_partial && pixels.bytes > 128 * 1024^2
                error('DataHandling:NeuroPALImage:NonChunkedMAT', ...
                    'Large MAT files require Version 7.3 for lazy access. Convert "%s" to Version 7.3 before opening it in Image Processing.', path);
            end
            metadata = DataHandling.Helpers.npal_mat.load_fields(path, false);
            dims = pixels.size;
            dims(end+1:4) = 1;
            reader = matfile(path);
            source = struct('path', char(path), 'reader', reader, ...
                'dims', dims, 'source_class', pixels.class, ...
                'bytes', pixels.bytes, 'metadata', metadata, ...
                'supports_partial', supports_partial, ...
                'read_plane', @(z, c) reader.data(:, :, z, c));
        end

        function bytes = materialization_limit_bytes()
            configured = str2double(getenv('NEUROPAL_IMAGE_MAX_MIB'));
            if ~isfinite(configured) || configured <= 0 || ~isfinite(configured * 1024^2)
                configured = 512;
            end
            bytes = max(1, floor(configured * 1024^2));
        end

        function check_materialization(path, pixels)
            limit = DataHandling.Helpers.npal_mat.materialization_limit_bytes();
            if pixels.bytes > limit
                error('DataHandling:NeuroPALImage:MaterializationLimit', ...
                    ['Image "%s" contains %.1f MiB (%d bytes) of %s pixels with dimensions %s, ' ...
                    'above the %.1f MiB main-view loading limit. Inspect it via Image Processing ' ...
                    '(lazy MAT access), create a smaller source, or explicitly increase ' ...
                    'NEUROPAL_IMAGE_MAX_MIB. This limit covers native pixels, not total working memory.'], ...
                    path, pixels.bytes / 1024^2, pixels.bytes, pixels.class, ...
                    mat2str(pixels.size), limit / 1024^2);
            end
        end
    end
end
