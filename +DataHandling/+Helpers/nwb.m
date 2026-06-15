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

        function path = search(file, module)
            % to be merged from loader branch
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
                'bit_depth', {str2num(target_module.deref(f).data.internal.dataType(5:end))}, ...
                'rgbw', {[target_module.deref(f).RGBW_channels.load()]'}, ...
                'scale', {[0 0 0]});

            if length(target_module.deref(f).data.internal.dims) > 4
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
            candidates = struct('group_path', {}, 'data_path', {}, ...
                'imaging_volume_path', {}, 'name', {}, 'dims', {}, 'datatype', {}, ...
                'bytes_per_sample', {}, 'num_bytes', {});

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

                candidates(end + 1) = struct( ... %#ok<AGROW>
                    'group_path', group.Name, ...
                    'data_path', data_path, ...
                    'imaging_volume_path', imaging_volume_path, ...
                    'name', group_name, ...
                    'dims', dims, ...
                    'datatype', data_info.Datatype, ...
                    'bytes_per_sample', bytes_per_sample, ...
                    'num_bytes', prod(dims) * bytes_per_sample);
            end

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
            fid = [];
            try
                fid = H5F.open(file, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
                cleanup = onCleanup(@() H5F.close(fid)); %#ok<NASGU>
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
            if iscell(value) && numel(value) == 1
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

        function np_file = to_npal(file, is_video)
            %CONVERTNWB Convert an NWB file to NeuroPAL format.
            %
            % nwb_file = the NWB file to convert
            % np_file = the NeuroPAL format file

            if nargin < 2
                app = Program.app;
                is_video = Program.Validation.agnostic_vol_check();
            end

            f = nwbRead(file);                                              % Get reader object.

            if is_video
                module = f.acquisition.get('CalciumImageSeries');
                dim_permutation = [4 3 2 1 5];
            else
                module = f.acquisition.get('NeuroPALImageRaw');
                dim_permutation = [1 1 1 1 1];
            end

            dims = module.data.internal.dims([dim_permutation]);

            nx = dims(2);                                                       % Get width.
            ny = dims(1);                                                       % Get height.
            nz = dims(3);                                                       % Get depth.
            nc = dims(5);                                                       % Get channel count.

            if is_video
                nt = dims(6);                                                    % Get frame count.
            else
                nt = 1;
            end

            bit_depth = module.data.dataType;

            data = [];                                                          % Initialize data as proportionate zero array.

            info = struct('file', {file});                                      % Initialize info struct.
            info.scale = module.imaging_volume.deref(f).grid_spacing.load();    % Set image scale
            info.scale = info.scale(:)';

            channels = DataHandling.Helpers.nwb.get_channel_names(f, module);   % Get channel names.
            channels = Program.Handlers.channels.parse_info(channels);          % Get channel indices from names.

            if isprop(module, 'RGBW_channels')
                info.RGBW = module.RGBW_channels.load();
                info.RGBW = info.RGBW(:)';
            else
                info.RGBW = channels(1:4);                                      % Set RGBW indices.
            end

            info.DIC = channels(5);                                             % Set DIC if present, else set to 0.
            info.GFP = channels(6);                                             % Set GFP is present, else set to 0.
            info.bit_depth = bit_depth;
            
            % Determine the gamma.
            info.gamma = Program.Handlers.channels.config{'default_gamma'};     % Set gamma to default since we can't get it from ND2 hashtable.
            
            % Initialize the user preferences.
            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(nz / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;
            
            % Initialize the worm info.
            worm.body = strrep(module.imaging_volume.deref(f).reference_frame, 'Worm ', '');
            worm.age = f.general_subject.growth_stage;
            worm.sex = Program.Validation.parse_sex(f.general_subject.sex);
            worm.strain = f.general_subject.strain;
            worm.notes = f.general_subject.description;
            
            % Save the ND2 file to our MAT file format.
            np_file = strrep(file, 'nd2', 'mat');
            version = Program.information.version;
            save(np_file, 'version', 'data', 'info', 'prefs', 'worm', '-v7.3');

            DataHandling.Helpers.nwb.write_data(np_file, module.data, [ny nx nz nc nt]);
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

        function write_data(np_file, data_pipe, dims)
            Program.Handlers.dialogue.add_task('Writing data...');
            np_write = matfile(np_file, "Writable", true);

            nx = dims(2);                                                       % Get width.
            ny = dims(1);                                                       % Get height.
            nz = dims(3);                                                       % Get depth.
            nc = dims(5);                                                       % Get channel count.
            nt = dims(6);                            

            np_write.data = zeros( ...
                ny, nx, ...
                nz, nc, nt, ...
                Program.config.defaults{'class'});

            if nt > 1
                for t=1:nt
                    Program.Handlers.dialogue.set_value(t/nt);
                    this_frame = data_pipe(:, :, :, :, t);
                    np_write.data(:, :, :, :, t) = DataHandling.Types.to_standard(this_frame);
                end
                
            else
                for z=1:nz
                    Program.Handlers.dialogue.set_value(z/nz);
                    this_slice = data_pipe(:, :, z, :)
                    np_write.data(:, :, z, :) = DataHandling.Types.to_standard(this_slice);
                end
            end

            Program.Handlers.dialogue.resolve();
        end
    end
end
