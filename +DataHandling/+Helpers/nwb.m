classdef nwb

    properties (Access = public, Constant)
    end
    
    methods (Static)
        function path = volume_path(new_path)
            persistent instance

            if isempty(instance) || exist('new_path', 'var')
                instance = types.untyped.SoftLink(new_path);
            end

            path = instance;
        end

        function [positions, labels] = load_tracks(filepath)
            nwb_file = nwbRead(filepath);
            x_coords = nwb_file.processing.get('NeuroPAL').dynamictable.get('TrackedNeurons').vectordata.get('x').data.load();
            y_coords = nwb_file.processing.get('NeuroPAL').dynamictable.get('TrackedNeurons').vectordata.get('y').data.load();
            z_coords = nwb_file.processing.get('NeuroPAL').dynamictable.get('TrackedNeurons').vectordata.get('z').data.load();

            frames = nwb_file.processing.get('NeuroPAL').dynamictable.get('TrackedNeurons').vectordata.get('t').data.load();
            if min(frames) == 0
                frames = frames + 1;
            end

            labels = nwb_file.processing.get('NeuroPAL').dynamictable.get('TrackedNeurons').vectordata.get('neuron_id').data.load();
            positions = [frames(:), x_coords(:), y_coords(:), z_coords(:)];
            labels = cellstr(string(labels(:)))';
        end

        function [obj, metadata] = open(file)
            if Program.states.instance().is_video
                DataHandling.Helpers.nwb.volume_path('/acquisition/CalciumImageSeries');
            else
                DataHandling.Helpers.nwb.volume_path('/acquisition/NeuroPALImageRaw');
            end

            f = nwbRead(file);
            target_module = DataHandling.Helpers.nwb.volume_path;

            metadata = struct( ...
                'path', {file}, ...
                'order', {target_module.deref(f).imaging_volume.deref(f).opticalchannelplus}, ...
                'nx', {target_module.deref(f).data.internal.dims(2)}, ...
                'ny', {target_module.deref(f).data.internal.dims(1)}, ...
                'nz', {target_module.deref(f).data.internal.dims(3)}, ...
                'nc', {target_module.deref(f).data.internal.dims(4)}, ...
                'has_dic', {1}, ...
                'has_gfp', {1}, ...
                'bit_depth', {str2double(target_module.deref(f).data.internal.dataType(5:end))}, ...
                'rgbw', {[target_module.deref(f).RGBW_channels.load()]'}, ...
                'scale', {[0 0 0]});

            if numel(target_module.deref(f).data.internal.dims) > 4
                metadata.nt = target_module.deref(f).data.internal.dims(5);
            else
                metadata.nt = 1;
            end

            if Program.states.instance().is_lazy
                obj = f;
            else
                obj = target_module.deref(f).data.load();
            end

        end

        function metadata = image_data_info(file)
            %IMAGE_DATA_INFO Return HDF5 metadata for the NeuroPAL image volume.
            %
            % This intentionally avoids nwbRead. Some files contain valid
            % NWB/NDX data that older MatNWB releases cannot fully parse
            % because of unrelated acquisition objects. The NWB/HDMF
            % on-disk representation exposes neurodata_type attributes and
            % the underlying data dataset directly, which is enough for
            % image size probing and fallback conversion.

            acquisition = h5info(file, '/acquisition');
            candidate_template = struct('group_path', '', 'data_path', '', ...
                'imaging_volume_path', '', 'name', '', 'dims', [], 'datatype', [], ...
                'chunk_size', [], 'bytes_per_sample', 0, 'num_bytes', 0);
            candidates = repmat(candidate_template, 1, numel(acquisition.Groups));
            candidate_count = 0;

            for i = 1:numel(acquisition.Groups)
                group = acquisition.Groups(i);
                neurodata_type = DataHandling.Helpers.nwb.h5_attr(group, 'neurodata_type', '');
                if ~strcmp(char(string(neurodata_type)), 'MultiChannelVolume')
                    continue
                end

                if isempty(group.Datasets)
                    continue
                end
                data_idx = find(strcmp({group.Datasets.Name}, 'data'), 1);
                if isempty(data_idx)
                    continue
                end

                data_path = [group.Name '/data'];
                data_info = h5info(file, data_path);
                dims = double(data_info.Dataspace.Size);
                bytes_per_sample = DataHandling.Helpers.nwb.h5_datatype_bytes(data_info.Datatype);
                slash_idx = find(group.Name == '/', 1, 'last');
                if isempty(slash_idx)
                    group_name = group.Name;
                else
                    group_name = group.Name(slash_idx + 1:end);
                end

                imaging_volume_path = DataHandling.Helpers.nwb.link_target_path( ...
                    file, [group.Name '/imaging_volume']);

                candidate_count = candidate_count + 1;
                candidates(candidate_count) = struct( ...
                    'group_path', group.Name, ...
                    'data_path', data_path, ...
                    'imaging_volume_path', imaging_volume_path, ...
                    'name', group_name, ...
                    'dims', dims, ...
                    'datatype', data_info.Datatype, ...
                    'chunk_size', double(data_info.ChunkSize), ...
                    'bytes_per_sample', bytes_per_sample, ...
                    'num_bytes', prod(dims) * bytes_per_sample);
            end
            candidates = candidates(1:candidate_count);

            if isempty(candidates)
                error('DataHandling:Helpers:NWB:NoImageVolume', ...
                    ['No acquisition group with neurodata_type ' ...
                     'MultiChannelVolume and a data dataset was found.']);
            end

            names = string({candidates.name});
            preferred = find(strcmpi(names, 'NeuroPALImageRaw'), 1);
            if isempty(preferred)
                preferred = 1;
            end
            metadata = candidates(preferred);
        end

        function num_bytes = image_data_size_bytes(file)
            metadata = DataHandling.Helpers.nwb.image_data_info(file);
            num_bytes = metadata.num_bytes;
        end

        function target_path = link_target_path(file, path)
            target_path = path;
            try
                fid = H5F.open(file, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
                cleanup = onCleanup(@() H5F.close(fid));
                link_info = H5L.get_info(fid, path, 'H5P_DEFAULT');
                if link_info.type == H5ML.get_constant_value('H5L_TYPE_SOFT')
                    target_path = H5L.get_val(fid, path, 'H5P_DEFAULT');
                    if isa(target_path, 'uint8') || isa(target_path, 'int8')
                        target_path = char(target_path(:).');
                    end
                end
            catch
                target_path = path;
            end
        end

        function value = h5_attr(info, name, default_value)
            value = default_value;
            if ~isfield(info, 'Attributes') || isempty(info.Attributes)
                return
            end

            idx = find(strcmp({info.Attributes.Name}, name), 1);
            if isempty(idx)
                return
            end
            value = info.Attributes(idx).Value;
            if iscell(value) && isscalar(value)
                value = value{1};
            end
            if isa(value, 'uint8') || isa(value, 'int8')
                value = char(value(:).');
            end
        end

        function tf = h5_exists(file, path)
            tf = false;
            try
                h5info(file, path);
                tf = true;
            catch
            end
        end

        function value = h5_read_numeric(file, path, default_value)
            value = default_value;
            if ~DataHandling.Helpers.nwb.h5_exists(file, path)
                return
            end
            try
                value = h5read(file, path);
            catch
                value = default_value;
            end
        end

        function values = h5_read_string_vector(file, path)
            values = strings(1, 0);
            if ~DataHandling.Helpers.nwb.h5_exists(file, path)
                return
            end

            try
                raw = h5read(file, path);
                if iscell(raw)
                    values = string(raw(:)).';
                elseif isstring(raw)
                    values = raw(:).';
                elseif ischar(raw)
                    values = string(cellstr(raw)).';
                else
                    values = string(raw(:)).';
                end
            catch
                values = strings(1, 0);
            end
        end

        function [rgbw, dic, gfp] = infer_image_channels(nwb_file, image_group, nc, default_rgbw)
            if nargin < 4 || isempty(default_rgbw)
                default_rgbw = 1:min(4, nc);
            end

            rgbw = DataHandling.Helpers.nwb.h5_read_numeric( ...
                nwb_file, [image_group '/RGBW_channels'], default_rgbw);
            rgbw = double(rgbw(:).');
            if ~isempty(rgbw) && min(rgbw) <= 0
                rgbw = rgbw + 1;
            end
            rgbw = rgbw(isfinite(rgbw));
            rgbw = round(rgbw);
            rgbw = rgbw(rgbw >= 1 & rgbw <= nc);
            if numel(rgbw) < 4
                fallback = setdiff(1:min(4, nc), rgbw, 'stable');
                rgbw = [rgbw fallback];
            end
            rgbw = rgbw(1:min(4, numel(rgbw)));

            image_info = DataHandling.Helpers.nwb.image_data_info(nwb_file);
            volume_paths = unique(string({ ...
                [image_group '/imaging_volume'], ...
                image_info.imaging_volume_path}), 'stable');

            channel_names = strings(1, 0);
            for i = 1:numel(volume_paths)
                channel_names = DataHandling.Helpers.nwb.h5_read_string_vector( ...
                    nwb_file, char(strcat(volume_paths(i), "/order_optical_channels/channels")));
                if ~isempty(channel_names)
                    break
                end
            end
            num_named_channels = numel(channel_names);

            gfp = nan;
            if ~isempty(channel_names)
                normalized = lower(channel_names);
                gfp_idx = find(contains(normalized, 'gcamp') | ...
                    contains(normalized, 'gfp'), 1);
                if ~isempty(gfp_idx) && gfp_idx <= nc
                    gfp = gfp_idx;
                end
            end
            if isnan(gfp) && nc > numel(rgbw)
                unused = setdiff(1:nc, rgbw, 'stable');
                if ~isempty(unused)
                    gfp = unused(1);
                end
            end

            dic = nan;
            if num_named_channels > 0 && nc > num_named_channels
                dic = nc;
            end
        end

        function gamma = image_gamma(file, nc, default_gamma)
            if nargin < 3 || isempty(default_gamma)
                default_gamma = 0.8;
            end

            gamma = DataHandling.Helpers.nwb.h5_read_numeric( ...
                file, '/processing/NeuroPAL/NeuroPAL_ID/gammas', []);
            if isempty(gamma)
                gamma = DataHandling.Helpers.nwb.h5_read_numeric( ...
                    file, '/processing/NeuroPAL_IDSettings/gammas', []);
            end
            if isempty(gamma)
                gamma = default_gamma;
            end

            gamma = double(gamma(:).');
            if numel(gamma) > nc
                gamma = gamma(1:nc);
            end
        end

        function tf = has_neuropal_segmentation(file)
            candidate_paths = { ...
                '/processing/NeuroPAL/NeuroPALSegmentation', ...
                '/processing/NeuroPAL/ImageSegmentation', ...
                '/processing/NeuroPAL/VolumeSegmentation', ...
                '/processing/NeuroPAL/NeuroPALNeurons'};
            tf = false;
            for i = 1:numel(candidate_paths)
                if DataHandling.Helpers.nwb.h5_exists(file, candidate_paths{i})
                    tf = true;
                    return
                end
            end
        end

        function bytes = h5_datatype_bytes(datatype)
            bytes = [];
            if isfield(datatype, 'Size') && ~isempty(datatype.Size)
                bytes = double(datatype.Size);
            end

            if isempty(bytes) || ~isfinite(bytes) || bytes <= 0
                type_text = '';
                if isfield(datatype, 'Type')
                    type_text = char(string(datatype.Type));
                elseif isfield(datatype, 'Class')
                    type_text = char(string(datatype.Class));
                end
                bits = regexp(type_text, '\d+', 'match', 'once');
                if ~isempty(bits)
                    bytes = str2double(bits) / 8;
                end
            end

            if isempty(bytes) || ~isfinite(bytes) || bytes <= 0
                bytes = 2;
            end
        end

        function layout = image_layout(image_info)
            source_dims = double(image_info.dims(:).');
            if numel(source_dims) ~= 4 || any(source_dims < 1)
                error('DataHandling:Helpers:NWB:UnsupportedImageDimensions', ...
                    'Expected a four-dimensional MultiChannelVolume; found %s.', ...
                    mat2str(source_dims));
            end

            % Preserve the orientation behavior of the established loader.
            % Normal NDX files are [Y X Z C]. Some older exports are
            % [C Z Y X] and require the historical [3 4 2 1] permutation.
            if source_dims(4) == min(source_dims)
                layout.source_z_axis = 3;
                layout.permutation = 1:4;
                layout.output_dims = source_dims;
            else
                layout.source_z_axis = 2;
                layout.permutation = [3 4 2 1];
                layout.output_dims = source_dims(layout.permutation);
            end
            layout.source_dims = source_dims;
            layout.output_z_count = layout.output_dims(3);
        end

        function report = stream_image_to_mat(nwb_file, image_info, np_file, metadata)
            %STREAM_IMAGE_TO_MAT Transactionally copy an NWB image volume.
            % Reads bounded HDF5 hyperslabs, checkpoints each committed
            % z-range, resumes matching partial files, and atomically exposes
            % the completed MAT file only after validation.

            layout = DataHandling.Helpers.nwb.image_layout(image_info);
            sample = h5read(nwb_file, image_info.data_path, ...
                ones(1, numel(layout.source_dims)), ...
                ones(1, numel(layout.source_dims)));
            output_class = class(sample);
            bytes_per_element = DataHandling.Helpers.large_file.bytes_per_element(output_class);
            raw_output_bytes = prod(layout.output_dims) * bytes_per_element;
            partial_file = DataHandling.Helpers.large_file.partial_path(np_file);

            expected_state = struct( ...
                'schema_version', 1, ...
                'source', DataHandling.Helpers.large_file.source_signature(nwb_file), ...
                'data_path', image_info.data_path, ...
                'source_dims', layout.source_dims, ...
                'output_dims', layout.output_dims, ...
                'output_class', output_class, ...
                'completed_z', 0, ...
                'chunk_count', 0, ...
                'status', 'partial');

            resumed = false;
            state = expected_state;
            if exist(partial_file, 'file') == 2
                resumed = DataHandling.Helpers.nwb.can_resume_image_conversion( ...
                    partial_file, expected_state);
                if resumed
                    saved = load(partial_file, 'conversion_state');
                    state = saved.conversion_state;
                else
                    delete(partial_file);
                end
            end

            existing_bytes = 0;
            if resumed
                details = dir(partial_file);
                existing_bytes = details.bytes;
            end
            DataHandling.Helpers.large_file.assert_sufficient_disk_space( ...
                partial_file, raw_output_bytes, existing_bytes);

            if ~resumed
                conversion_state = state;
                save(partial_file, '-struct', 'metadata', '-v7.3');
                save(partial_file, 'conversion_state', '-append');
                target = matfile(partial_file, 'Writable', true);
                last_index = num2cell(layout.output_dims);
                target.data(last_index{:}) = cast(0, output_class);
            else
                target = matfile(partial_file, 'Writable', true);
            end

            memory_budget = DataHandling.Helpers.large_file.memory_budget_bytes();
            plane_elements = prod(layout.source_dims) / ...
                layout.source_dims(layout.source_z_axis);
            working_bytes_per_plane = plane_elements * bytes_per_element * 2.5;
            chunk_z = max(1, floor(memory_budget / working_bytes_per_plane));
            chunk_z = min(chunk_z, layout.output_z_count);
            if isfield(image_info, 'chunk_size') && ~isempty(image_info.chunk_size) && ...
                    numel(image_info.chunk_size) >= layout.source_z_axis
                storage_chunk_z = max(1, image_info.chunk_size(layout.source_z_axis));
                if storage_chunk_z <= chunk_z
                    chunk_z = max(storage_chunk_z, ...
                        floor(chunk_z / storage_chunk_z) * storage_chunk_z);
                end
            end

            handle = Program.Handlers.dialogue.active();
            try
                if ~isempty(handle) && isvalid(handle) && isprop(handle, 'Cancelable')
                    handle.Cancelable = 'on';
                end
            catch
            end

            cancel_after = str2double(getenv('NEUROPAL_IO_CANCEL_AFTER_CHUNKS'));
            if ~isfinite(cancel_after) || cancel_after < 1
                cancel_after = inf;
            end

            start_z = state.completed_z + 1;
            for z_start = start_z:chunk_z:layout.output_z_count
                if DataHandling.Helpers.large_file.cancel_requested()
                    error('DataHandling:LargeFile:Cancelled', ...
                        'Conversion cancelled. Progress is saved in %s.', partial_file);
                end

                z_end = min(z_start + chunk_z - 1, layout.output_z_count);
                source_start = ones(1, numel(layout.source_dims));
                source_count = layout.source_dims;
                source_start(layout.source_z_axis) = z_start;
                source_count(layout.source_z_axis) = z_end - z_start + 1;
                chunk = h5read(nwb_file, image_info.data_path, source_start, source_count);
                if ~isequal(layout.permutation, 1:4)
                    chunk = permute(chunk, layout.permutation);
                end
                target.data(:, :, z_start:z_end, :) = chunk;

                state.completed_z = z_end;
                state.chunk_count = state.chunk_count + 1;
                target.conversion_state = state;
                Program.Handlers.dialogue.set_value(z_end / layout.output_z_count);
                Program.Handlers.dialogue.step(sprintf( ...
                    'Converted NWB slices %d-%d of %d', ...
                    z_start, z_end, layout.output_z_count));

                if state.chunk_count >= cancel_after
                    error('DataHandling:LargeFile:Cancelled', ...
                        'Conversion cancelled after a test checkpoint. Progress is saved in %s.', ...
                        partial_file);
                end
            end

            details = whos(target, 'data');
            if isempty(details) || ~isequal(double(details.size), layout.output_dims) || ...
                    ~strcmp(details.class, output_class)
                error('DataHandling:LargeFile:VerificationFailed', ...
                    'The streamed output failed size or type verification.');
            end

            state.status = 'complete';
            target.conversion_state = state;
            clear target
            DataHandling.Helpers.large_file.promote(partial_file, np_file);

            report = struct( ...
                'output_file', np_file, ...
                'resumed', resumed, ...
                'chunks_written', state.chunk_count, ...
                'chunk_z', chunk_z, ...
                'output_dims', layout.output_dims, ...
                'output_class', output_class, ...
                'raw_output_bytes', raw_output_bytes);
        end

        function tf = can_resume_image_conversion(partial_file, expected)
            tf = false;
            try
                saved = load(partial_file, 'conversion_state');
                if ~isfield(saved, 'conversion_state')
                    return
                end
                actual = saved.conversion_state;
                fields = {'schema_version', 'source', 'data_path', 'source_dims', ...
                    'output_dims', 'output_class'};
                for index = 1:numel(fields)
                    field = fields{index};
                    if ~isfield(actual, field) || ...
                            ~isequaln(actual.(field), expected.(field))
                        return
                    end
                end
                reader = matfile(partial_file);
                details = whos(reader, 'data');
                tf = ~isempty(details) && ...
                    isequal(double(details.size), expected.output_dims) && ...
                    strcmp(details.class, expected.output_class) && ...
                    actual.completed_z >= 0 && ...
                    actual.completed_z <= expected.output_dims(3);
            catch
                tf = false;
            end
        end

        function obj = get_plane(varargin)
            target_module = DataHandling.Helpers.nwb.volume_path;
            metadata = DataHandling.file.metadata;
            t = Program.GUIHandling.current_frame;
        
            p = inputParser;
            addOptional(p, 'x', 1:metadata.nx);
            addOptional(p, 'y', 1:metadata.ny);
            addOptional(p, 'z', 1:metadata.nz);
            addOptional(p, 'c', 1:metadata.nc);
            addOptional(p, 't', t);
            parse(p, varargin{:});
        
            file = target_module.deref(DataHandling.file.current_file).data;
            if DataHandling.file.is_video
                obj = file(p.Results.y, p.Results.x, p.Results.z, p.Results.c, p.Results.t);
            else
                obj = file(p.Results.y, p.Results.x, p.Results.z, p.Results.c);
            end
        end

        function names = get_channel_names(f, module)
            optical_channels = module.imaging_volume.deref(f).opticalchannel;
            names = keys(optical_channels);
            names = string(names);
        end

    end
end
