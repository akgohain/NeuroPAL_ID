classdef npal_mat
    %NPAL_MAT Inspect NeuroPAL MAT files without materializing image pixels.

    methods (Static)
        function fields = load_fields(path, include_data)
            names = {'version', 'info', 'prefs', 'worm'};
            if include_data
                names = [{'data'}, names];
            end
            variables = whos('-file', path);
            headers=variables(ismember({variables.name},{'version','info','prefs','worm'}));
            if sum(double([headers.bytes]))>64*1024^2
                error('DataHandling:NeuroPALImage:MetadataLimit', ...
                    'The NeuroPAL header exceeds 64 MiB. Check the image metadata before opening this file.');
            end
            if include_data
                pixels = variables(strcmp({variables.name}, 'data'));
                if ~isempty(pixels)
                    DataHandling.Helpers.npal_mat.check_pixels(pixels);
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
            DataHandling.Helpers.npal_mat.check_pixels(pixels);
            supports_partial = H5F.is_hdf5(path);
            if ~supports_partial && pixels.bytes > 128 * 1024^2
                error('DataHandling:NeuroPALImage:NonChunkedMAT', ...
                    'Large MAT files require Version 7.3 for lazy access. Convert "%s" to Version 7.3 before opening it in Image Processing.', path);
            end
            metadata = DataHandling.Helpers.npal_mat.load_fields(path, false);
            dims = pixels.size;
            dims(end+1:4) = 1;
            worm=[]; if isfield(metadata,'worm'), worm=metadata.worm; end
            [metadata.info,metadata.prefs,metadata.worm]=DataHandling.Helpers.npal_metadata.normalize( ...
                metadata.info,metadata.prefs,worm,dims);
            reader = matfile(path);
            source = struct('path', char(path), 'reader', reader, ...
                'dims', dims, 'source_class', pixels.class, ...
                'bytes', pixels.bytes, 'metadata', metadata, ...
                'supports_partial', supports_partial, ...
                'read_plane', @(z, c) reader.data(:, :, z, c));
        end

        function check_pixels(pixels)
            supported={'logical','uint8','uint16','uint32','uint64','int8','int16','int32','int64','single','double'};
            if ~isscalar(pixels) || ~any(strcmp(pixels.class,supported)) || any(pixels.size==0) || ...
                    numel(pixels.size)>4 || (isfield(pixels,'complex') && pixels.complex) || ...
                    (isfield(pixels,'sparse') && pixels.sparse)
                error('DataHandling:NeuroPALImage:InvalidPixels', ...
                    'A NeuroPAL image must contain a nonempty, real numeric Y × X × Z × channel array. Open a single volume rather than a time series.');
            end
        end

        function bytes = materialization_limit_bytes()
            configured = Runtime.Environment.resource('image_max_mib');
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
                    '(lazy MAT access), create a smaller source, or increase Image max MiB under ' ...
                    'Tools > Models & runtimes > Resources. This limit covers native pixels, not total working memory.'], ...
                    path, pixels.bytes / 1024^2, pixels.bytes, pixels.class, ...
                    mat2str(pixels.size), limit / 1024^2);
            end
        end
    end
end
