classdef nwb_stream_export
    %NWB_STREAM_EXPORT Write image planes to a transactional NWB output.

    methods (Static)
        function source = image_source(data)
            if ndims(data) > 4
                error('DataHandling:NWBExport:ImageDimensions', ...
                    'The image export expects YXZC data. Export time series through the video path.');
            end
            dims = size(data);
            dims(end+1:4) = 1;
            source = struct('path', '/acquisition/NeuroPALImageRaw/data', ...
                'dims', dims, 'read_plane', @(t, z, c) data(:, :, z, c));
        end

        function source = video_source(app)
            info = app.video_info;
            dims = [info.ny info.nx info.nz info.nc info.nt];
            source = struct('path', '/acquisition/CalciumImageSeries/data', ...
                'dims', dims, ...
                'source_file', info.file, ...
                'source_signature', DataHandling.Helpers.large_file.source_signature(info.file), ...
                'read_plane', @(t, z, c) DataHandling.Helpers.nwb_stream_export.read_video_plane(app, info, t, z, c));
        end

        function pipe = make_pipe(dims)
            validateattributes(dims, {'numeric'}, ...
                {'vector', 'finite', 'positive', 'integer'});
            chunk = ones(size(dims));
            chunk(1:2) = min(dims(1:2), [256 256]);
            pipe = types.untyped.DataPipe('maxSize', dims, ...
                'dataType', 'uint16', 'axis', numel(dims), ...
                'chunkSize', chunk, 'compressionLevel', 3);
        end

        function write(nwb, final_path, sources, progress, varargin)
            %WRITE Publish only after every source plane has been written.
            if nargin < 4
                progress = [];
            end
            p = inputParser;
            addParameter(p, 'CancelFcn', @() false);
            addParameter(p, 'AdditionalDiskBytes', 0);
            parse(p, varargin{:});
            final_path = char(final_path);
            if isfile(final_path)
                error('DataHandling:NWBExport:FinalExists', ...
                    'The output already exists: %s. Choose a new filename.', final_path);
            end
            budget = DataHandling.Helpers.large_file.memory_budget_bytes();
            output_bytes = p.Results.AdditionalDiskBytes;
            for i = 1:numel(sources)
                dims = sources{i}.dims;
                validateattributes(dims, {'numeric'}, ...
                    {'vector', 'finite', 'positive', 'integer'});
                if ~ismember(numel(dims), [4 5])
                    error('DataHandling:NWBExport:InvalidDimensions', ...
                        'Expected YXZC or YXZCT data, got %s.', mat2str(dims));
                end
                % Reserve room for the input, conversion, and HDF5 buffers.
                if prod(double(dims(1:2))) * 40 > budget
                    error('DataHandling:NWBExport:PlaneTooLarge', ...
                        'One XY plane exceeds the export working-memory budget. Crop the image or increase NEUROPAL_IO_CHUNK_MIB.');
                end
                output_bytes = output_bytes + prod(double(dims)) * 2;
            end
            DataHandling.Helpers.large_file.assert_sufficient_disk_space(final_path, output_bytes);
            [folder, name, ext] = fileparts(final_path);
            if isempty(folder)
                folder = pwd;
            end
            [~, token] = fileparts(tempname(folder));
            partial = fullfile(folder, ['.' name '.' token '.npal-partial' ext]);
            cleanup = onCleanup(@() DataHandling.Helpers.nwb_stream_export.remove_partial(partial));
            DataHandling.Helpers.nwb_stream_export.check_cancel(progress, p.Results.CancelFcn);
            DataHandling.Helpers.nwb_stream_export.update_progress(progress, 'Creating NWB output...', 0);
            DataHandling.Helpers.nwb_stream_export.prepare_existing_datasets(nwb);
            nwbExport(nwb, partial);
            conversions = cell(size(sources));
            for i = 1:numel(sources)
                source = sources{i};
                conversions{i} = DataHandling.Helpers.nwb_stream_export.write_source( ...
                    partial, source, progress, p.Results.CancelFcn);
            end
            if ~isempty(conversions)
                DataHandling.Helpers.nwb_stream_export.write_conversion_notes(partial, conversions);
            end
            DataHandling.Helpers.nwb_stream_export.check_cancel(progress, p.Results.CancelFcn);
            for i = 1:numel(sources)
                DataHandling.Helpers.nwb_stream_export.check_source(sources{i});
            end
            DataHandling.Helpers.large_file.promote(partial, final_path);
            clear cleanup
        end

        function conversion = write_source(path, source, progress, cancel_fcn)
            dims = source.dims;
            shape = dims;
            shape(end+1:5) = 1;
            count = prod(shape(3:5));
            DataHandling.Helpers.nwb_stream_export.check_source(source);
            DataHandling.Helpers.nwb_stream_export.allocate(path, source.path, dims);

            sample = DataHandling.Helpers.nwb_stream_export.read_plane(source, 1, 1, 1, progress, cancel_fcn);
            source_class = class(sample);
            is_float = isfloat(sample);
            low = 0;
            high = 0;
            if is_float
                low = inf;
                high = -inf;
                measured = 0;
                for t = 1:shape(5)
                    for c = 1:shape(4)
                        for z = 1:shape(3)
                            plane = DataHandling.Helpers.nwb_stream_export.read_plane(source, t, z, c, progress, cancel_fcn);
                            if ~strcmp(class(plane), source_class)
                                error('DataHandling:NWBExport:ChangingType', 'Source pixel type changed during export.');
                            end
                            low = min(low, double(min(plane, [], 'all')));
                            high = max(high, double(max(plane, [], 'all')));
                            measured = measured + 1;
                            DataHandling.Helpers.nwb_stream_export.update_progress(progress, ...
                                sprintf('Measuring image range: plane %d/%d...', measured, count), measured / count);
                        end
                    end
                end
                if ~isfinite(high - low)
                    error('DataHandling:NWBExport:OutOfRange', 'Floating-point image range cannot be represented safely.');
                end
            end
            clear sample plane

            written = 0;
            for t = 1:shape(5)
                for c = 1:shape(4)
                    for z = 1:shape(3)
                        plane = DataHandling.Helpers.nwb_stream_export.read_plane(source, t, z, c, progress, cancel_fcn);
                        if ~strcmp(class(plane), source_class)
                            error('DataHandling:NWBExport:ChangingType', 'Source pixel type changed during export.');
                        end
                        if is_float
                            if high > low
                                plane = uint16(round((double(plane) - low) ./ (high - low) .* 65535));
                            else
                                plane = zeros(size(plane), 'uint16');
                            end
                        else
                            if any(plane(:) < 0) || any(plane(:) > 65535)
                                error('DataHandling:NWBExport:OutOfRange', ...
                                    'Integer image values must fit the NWB uint16 schema (0 through 65535).');
                            end
                            plane = uint16(plane);
                        end
                        start = [1 1 z c t];
                        slab = [shape(1:2) 1 1 1];
                        h5write(path, source.path, plane, start(1:numel(dims)), slab(1:numel(dims)));
                        written = written + 1;
                        DataHandling.Helpers.nwb_stream_export.update_progress(progress, ...
                            sprintf('Exporting plane %d/%d...', written, count), written / count);
                    end
                end
            end
            conversion = struct('dataset', source.path, 'source_dtype', source_class, ...
                'conversion', 'lossless_uint16');
            if is_float
                conversion.conversion = 'global_linear_uint16';
                conversion.source_min = low;
                conversion.source_max = high;
            end
            info = h5info(path, source.path);
            if ~isequal(double(info.Dataspace.Size), double(dims))
                error('DataHandling:NWBExport:VerificationFailed', 'Exported volume dimensions do not match the source.');
            end
            probe = h5read(path, source.path, ones(size(dims)), ones(size(dims)));
            if ~isa(probe, 'uint16')
                error('DataHandling:NWBExport:VerificationFailed', 'Exported image dtype is not uint16.');
            end
        end

        function plane = read_plane(source, t, z, c, progress, cancel_fcn)
            DataHandling.Helpers.nwb_stream_export.check_cancel(progress, cancel_fcn);
            plane = source.read_plane(t, z, c);
            if ~(isnumeric(plane) || islogical(plane)) || ~isreal(plane) || ...
                    ~isequal(size(plane), source.dims(1:2)) || any(~isfinite(plane(:)))
                error('DataHandling:NWBExport:InvalidPlane', ...
                    'Source returned a nonfinite, nonnumeric, or incorrectly shaped XY plane.');
            end
        end

        function plane = read_video_plane(app, info, t, z, c)
            if ~isequal(app.video_info, info)
                error('DataHandling:NWBExport:SourceChanged', 'The active video changed during export.');
            end
            [~, ~, ext] = fileparts(info.file);
            switch lower(ext)
                case '.h5'
                    plane = Program.Helpers.read_h5_video_plane(info, t, z, c);
                case {'.nd2', '.tif', '.tiff'}
                    reader = app.getVideoBioformatsReader();
                    plane = app.readVideoBioformatsPlane(reader, z, c, t);
                case '.nwb'
                    dims = size(app.nwb_mod);
                    dims(end+1:5) = 1;
                    if isequal(dims, [info.nc info.nz info.ny info.nx info.nt])
                        % Preserve the existing CZYXT loader's display orientation.
                        plane = app.nwb_mod(c, z, :, :, t);
                    elseif isequal(dims, [info.ny info.nx info.nz info.nc info.nt])
                        plane = app.nwb_mod(:, :, z, c, t);
                    else
                        error('DataHandling:NWBExport:UnsupportedLayout', ...
                            'NWB video dimensions do not match the loaded source metadata.');
                    end
                    plane = reshape(plane, info.ny, info.nx);
                otherwise
                    error('DataHandling:NWBExport:UnsupportedVideo', ...
                        'No bounded plane reader is available for %s.', ext);
            end
        end

        function allocate(path, dataset, dims)
            fid = H5F.open(path, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            file_cleanup = onCleanup(@() H5F.close(fid));
            did = H5D.open(fid, dataset);
            data_cleanup = onCleanup(@() H5D.close(did));
            H5D.set_extent(did, fliplr(dims));
        end

        function check_source(source)
            if isfield(source, 'source_signature') && ...
                    ~isequal(source.source_signature, ...
                    DataHandling.Helpers.large_file.source_signature(source.source_file))
                error('DataHandling:NWBExport:SourceChanged', ...
                    'The source video file changed during export. No output was published.');
            end
        end

        function prepare_existing_datasets(parent)
            % Bound DataPipes target the old file; DataStubs copy on export.
            if isa(parent, 'types.untyped.Set')
                names = parent.keys;
            elseif isa(parent, 'types.untyped.Anon')
                names = {'value'};
            elseif isa(parent, 'types.untyped.MetaClass')
                names = properties(parent);
            else
                return
            end
            for i = 1:numel(names)
                name = names{i};
                if isa(parent, 'types.untyped.Set')
                    value = parent.get(name);
                else
                    value = parent.(name);
                end
                if isa(value, 'types.untyped.DataPipe') && value.isBound
                    stub = types.untyped.DataStub(value.internal.filename, value.internal.path);
                    if isa(parent, 'types.untyped.Set')
                        parent.set(name, stub);
                    else
                        parent.(name) = stub;
                    end
                else
                    DataHandling.Helpers.nwb_stream_export.prepare_existing_datasets(value);
                end
            end
        end

        function write_conversion_notes(path, conversions)
            notes = '';
            fid = H5F.open(path, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            cleanup = onCleanup(@() H5F.close(fid));
            has_general = H5L.exists(fid, '/general', 'H5P_DEFAULT');
            if has_general && H5L.exists(fid, '/general/notes', 'H5P_DEFAULT')
                notes = char(join(string(h5read(path, '/general/notes')), newline));
                H5L.delete(fid, '/general/notes', 'H5P_DEFAULT');
            end
            if ~has_general
                group = H5G.create(fid, '/general', 'H5P_DEFAULT', 'H5P_DEFAULT', 'H5P_DEFAULT');
                H5G.close(group);
            end
            record = ['NeuroPAL_ID pixel export: ' jsonencode(conversions)];
            if ~isempty(notes)
                record = [notes newline record];
            end
            io.writeDataset(fid, '/general/notes', record);
        end

        function check_cancel(progress, callback)
            drawnow limitrate;
            cancelled = callback();
            if isobject(progress) && isvalid(progress) && isprop(progress, 'CancelRequested')
                cancelled = cancelled || progress.CancelRequested;
            end
            if cancelled
                error('DataHandling:NWBExport:Cancelled', 'NWB export cancelled; no output was published.');
            end
        end

        function update_progress(progress, message, value)
            if isobject(progress) && isvalid(progress)
                progress.Message = message;
                if isprop(progress, 'Value')
                    progress.Value = value;
                end
            end
        end

        function remove_partial(path)
            if isfile(path)
                delete(path);
            end
        end
    end
end
