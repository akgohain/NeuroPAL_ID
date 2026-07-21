classdef NeuroPALImage
    %NEUROPALIMAGE Convert various image formats to a NeuroPAL format.
    %
    %   NeuroPAL files contain 4 variable:
    %      data = the image data (x,y,z,c)
    %      info = the image information
    %           scale = pixel scale in microns (x,y,z)
    %           RGBW = the (R,G,B,W) color channel indices (nan = no data)
    %           GFP = the GFP color channel index(s) (can be empty)
    %           DIC = the DIC channel index (can be empty)
    %           gamma = the gamma correction for the image
    %      prefs = the user preferences
    %           RGBW = the (R,G,B,W) color channel indices (nan = no data)
    %           GFP = the GFP color channel index(s) (can be empty)
    %           DIC = the DIC channel index (can be empty)
    %           gamma = the gamma correction for the image
    %           rotate.horizontal = rotate horizontal?
    %           rotate.vertical = rotate vertical?
    %      worm = the worm information
    %           body = 'Whole Worm', 'Head', 'Midbody', 'Anterior Midbody'.
    %                  'Central Midbody', 'Posterior Midbody', or 'Tail'
    %           age = 'Adult', 'L4', L3', 'L2, 'L1', or '3-Fold'
    %           sex = 'XX' or 'XO'
    %           strain = strain name
    %           notes = experimental notes
    %      mp = matching pursuit (neuron detection) parameters
    %      neurons = the neurons in the image
    
    
    %% Public methods.
    methods (Static)
        function [data, info, prefs, worm, mp, neurons, np_file, id_file] = open(file)
            %OPEN Open an image in NeuroPAL format.
            %
            % Input:
            %   file = the NeuroPAL format filename
            %
            % Output:
            %   data = the image data
            %   info = the image information
            %   prefs = the user preferences
            %   worm = the worm information
            %   mp = matching pursuit (neuron detection) parameters
            %   neurons = the neurons in the image
            %	np_file = the NeuroPAL image file
            %	id_file = the NeuroPAL ID file

            % Initialize the packages.
            import DataHandling.*;

            % Is the user accidentally trying to open the ID file?
            id_file_ext = '_ID.mat';
            if endsWith(file, id_file_ext)
                file = strrep(file, id_file_ext, '.mat');
            end
            
            % Get the file extension.
            [~, ~, ext] = fileparts(file);
            if isempty(ext)
                error('Unknown image format: "%s"', file);
            end
            ext = lower(ext);

            % Determine the NeuroPAL filename.
            np_file = strrep(file, ext, '.mat');

            if strcmp(ext, '.nd2')
                nt = DataHandling.Helpers.nd2.get_timepoints(file);
                if nt > 1
                    error('DataHandling:NeuroPALImage:ND2VideoInImageLoader', ...
                        ['This ND2 contains %d timepoints and is a video. ' ...
                         'Open it from the Video Tracking loader instead of the NeuroPAL image loader.'], nt);
                end
            end

            % Is the file already in NeuroPAL format?
            if ~exist(np_file,'file')
                Program.Handlers.dialogue.add_task(sprintf('Converting %s file to NeuroPAL_ID file...', ext));
                conversion_cleanup = onCleanup(@() Program.Handlers.dialogue.resolve());
                switch lower(ext)
                    case '.mat' % NeuroPAL format
                        error('File not found: "%s"', file);
                    case '.czi' % Zeiss format
                        NeuroPALImage.convertCZI(file);
                    case '.nd2' % Nikon format
                        DataHandling.Helpers.nd2.to_npal(file);
                        % NeuroPALImage.convertND2(file);
                    case {'.lif'} % Leica format
                        NeuroPALImage.convertAny(file);
                    case {'.ims'} % Imaris format
                        NeuroPALImage.convertAny(file);
                    case {'.tif','.tiff'} % TIFF format
                        NeuroPALImage.convertAny(file);
                    case {'.h5'} % Vlab format
                        NeuroPALImage.convertAny(file);   
                    case {'.nwb'} % NWB  format
                        NeuroPALImage.convertNWB(file);
                    otherwise % Unknown format
                        error('Unknown image format: "%s"', file);
                end
                clear conversion_cleanup
            end
            
            % Did we manage to convert the file?
            if ~exist(np_file,'file')
                error('Cannot read/convert: "%"', np_file);
            end
            
            % Load the file.
            [data, info, prefs, worm, mp, neurons, id_file] = ...
                NeuroPALImage.loadNP(np_file);

            Program.Validation.fill_channels(data);
        end

    end
    
    
    %% Private variables.
    properties (Constant, Access = private)

        % Default gamma values.
        gamma_default = 0.8;
        CZI_gamma_default = 0.5;
    end
    
    
    %% Private methods.
    methods (Static, Access = private)
        
        function [data, info, prefs, worm, mp, neurons, id_file] = loadNP(image_file)
            %LOADNP Load an image in NeuroPAL format.
            %
            % Input:
            %   image_file = the NeuroPAL image filename
            %
            % Output:
            %   id_file = the NeuroPAL ID filename
            %   data = the image data
            %   info = the image information
            %   prefs = the user preferences
            %   worm = the worm information
            %   mp = matching pursuit (neuron detection) parameters
            %   neurons = the neurons in the image
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;

            Program.Handlers.dialogue.step('Loading NeuroPAL_ID file...');
            
            % Open the image file.
            np_data = load(image_file);
            if ~isfield(np_data, 'data') || ...
                    ~isfield(np_data, 'info') || ...
                    ~isfield(np_data, 'prefs')
                error('Misformatted NeuroPAL file: "%s"', image_file);
            end
            
            % Setup the image file contents.
            data = np_data.data;
            info = np_data.info;
            prefs = np_data.prefs;
            worm = [];
            if isfield(np_data, 'worm')
                worm = np_data.worm;
            end
            
            % Get the image file version.
            version = 0;
            if isfield(np_data, 'version')
                version = np_data.version;
            end
            
            % Check the image file version.
            if version < 1

                % Correct the worm info.
                worm.body = prefs.body_part;
                worm.age = 'Adult';
                worm.sex = 'XX';
                worm.strain = '';
                worm.notes = '';
                prefs = rmfield(prefs, 'body_part');
                
                % Update the file version.
                version = ProgramInfo.version;
                save(image_file, 'version', 'prefs', 'worm', '-append', '-v7.3');
            end

            % Sanitize prefs to avoid invalid channel indices in the GUI.
            if ~isfield(prefs, 'RGBW') || isempty(prefs.RGBW)
                prefs.RGBW = nan(1, 4);
            end
            if ~isfield(prefs, 'DIC')
                prefs.DIC = nan;
            end
            if ~isfield(prefs, 'GFP')
                prefs.GFP = nan;
            end

            nc = size(data, 4);
            if nc < 1
                prefs.RGBW = nan(1, 4);
                prefs.DIC = nan;
                prefs.GFP = nan;
            else
                prefs.RGBW = prefs.RGBW(:)';
                if numel(prefs.RGBW) < 4
                    prefs.RGBW(end+1:4) = nan;
                end
                prefs.RGBW = round(prefs.RGBW(1:4));
                invalid_rgbw = isnan(prefs.RGBW) | prefs.RGBW < 1 | prefs.RGBW > nc;
                prefs.RGBW(invalid_rgbw) = nan;

                % DIC: keep only a valid scalar index, otherwise NaN.
                if isempty(prefs.DIC)
                    prefs.DIC = nan;
                elseif isscalar(prefs.DIC)
                    if prefs.DIC < 1 || prefs.DIC > nc
                        prefs.DIC = nan;
                    end
                else
                    valid_dic = prefs.DIC(prefs.DIC >= 1 & prefs.DIC <= nc);
                    if isempty(valid_dic)
                        prefs.DIC = nan;
                    else
                        prefs.DIC = valid_dic(1);
                    end
                end

                % GFP: keep only a valid scalar index, otherwise NaN.
                if isempty(prefs.GFP)
                    prefs.GFP = nan;
                elseif isscalar(prefs.GFP)
                    if prefs.GFP < 1 || prefs.GFP > nc
                        prefs.GFP = nan;
                    end
                else
                    valid_gfp = prefs.GFP(prefs.GFP >= 1 & prefs.GFP <= nc);
                    if isempty(valid_gfp)
                        prefs.GFP = nan;
                    else
                        prefs.GFP = valid_gfp(1);
                    end
                end

                % Fill missing color roles with distinct, unused channels
                % when possible. Assigning every unknown role to channel 1
                % makes partially-described CZI/NWB files appear grayscale
                % and silently duplicates the same data three times.
                missing_rgbw = find(~isfinite(prefs.RGBW));
                reserved = prefs.RGBW(isfinite(prefs.RGBW));
                if isfinite(prefs.DIC)
                    reserved(end + 1) = prefs.DIC;
                end
                if isfinite(prefs.GFP)
                    reserved(end + 1) = prefs.GFP;
                end
                candidates = setdiff(1:nc, unique(reserved), 'stable');
                fallback = setdiff(1:nc, prefs.RGBW(isfinite(prefs.RGBW)), 'stable');
                candidates = unique([candidates, fallback, 1:nc], 'stable');
                for slot = missing_rgbw
                    if isempty(candidates)
                        prefs.RGBW(slot) = 1;
                    else
                        prefs.RGBW(slot) = candidates(1);
                        candidates(1) = [];
                    end
                end
            end
            
            % Open the ID file or try to load neuron data from associated NWB file.
            version = 0;
            mp = [];
            mp.hnsz = round(round(3./info.scale')/2)*2+1;
            if size(mp.hnsz,1) > 1
                mp.hnsz = mp.hnsz';
            end
            mp.k = 0;
            mp.exclusion_radius = 1.5;
            mp.min_eig_thresh = 0.1;
            sp = [];
            neurons = [];
            id_file = strrep(image_file, '.mat', '_ID.mat');
            
            % First, try to load from NWB file if it exists and companion ID file doesn't
            nwb_file = strrep(image_file, '.mat', '.nwb');
            if exist(nwb_file, 'file') && ~exist(id_file, 'file')
                if DataHandling.Helpers.nwb.has_neuropal_segmentation(nwb_file)
                    Program.Helpers.debug_event('NWB', ...
                        ['NWB segmentation metadata found in "%s", but automatic ' ...
                         'MatNWB neuron import is skipped during image load.'], ...
                        nwb_file);
                end
            end
            
            % If we didn't get data from NWB, try the traditional ID file approach
            if isempty(neurons) && exist(id_file, 'file')

                % Load the neurons file.
                id_data = load(id_file);

                % Get the ID file version.
                if isfield(id_data, 'version')
                    version = id_data.version;
                end

                % Setup the file contents.
                if isfield(id_data, 'mp_params') && isstruct(id_data.mp_params)
                    mp = id_data.mp_params;
                end
                if ~isstruct(mp)
                    mp = struct();
                end
                if ~isfield(mp, 'hnsz')
                    mp.hnsz = round(round(3./info.scale')/2)*2+1;
                end
                if size(mp.hnsz,1) > 1
                    mp.hnsz = mp.hnsz';
                end
                if ~isfield(mp, 'k')
                    mp.k = 0;
                end
                if ~isfield(mp, 'exclusion_radius')
                    mp.exclusion_radius = 1.5;
                end
                if ~isfield(mp, 'min_eig_thresh')
                    mp.min_eig_thresh = 0.1;
                end

                % Check the ID file version.
                % Version > 1.
                if version > 1
                    if isfield(id_data, 'neurons')
                        neurons = id_data.neurons;
                    end

                % Version 1.
                elseif version == 1

                    % Create the neurons.
                    if isfield(id_data, 'sp')
                        sp = id_data.sp;
                    end
                    neurons = Neurons.Image(sp, worm.body, 'scale', info.scale);

                    % Update the file version.
                    version = ProgramInfo.version;
                    mp_params = mp;
                    save(id_file, 'version', 'neurons', 'mp_params', '-v7.3');
                
                % No version.
                elseif version < 1

                    % Are there any neurons?
                    if isfield(id_data, 'sp')
                        sp = id_data.sp;
                    end
                    if ~isempty(sp)
                        
                        % Correct the neuron colors.
                        if ~isfield(sp, 'color_readout')
                            
                            % Set the neuron patch size.
                            patch_hsize = [3,3,0];
                            
                            % Compute the data.
                            data_RGBW = double(data(:,:,:,prefs.RGBW));
                            data_zscored = ...
                                Methods.Preprocess.zscore_frame(double(data_RGBW));
                            
                            % Read the patch colors.
                            num_neurons = size(sp.color,1);
                            sp.color_readout = nan(num_neurons,4);
                            for i = 1:num_neurons
                                patch = Methods.Utils.subcube(data_zscored, ...
                                    round(sp.mean(i,:)), patch_hsize);
                                sp.color_readout(i,:) = ...
                                    median(reshape(patch, ...
                                    [numel(patch)/size(patch, 4), size(patch, 4)]), ...
                                    'omitnan');
                            end
                        end
                        
                        % Clean up the old sp fields.
                        if isfield(sp, 'mean')
                            sp.positions = sp.mean;
                            sp.covariances = sp.cov;
                            sp = rmfield(sp, {'mean', 'cov'});
                        end
                    end
                    
                    % Create the neurons.
                    neurons = Neurons.Image(sp, worm.body, 'scale', info.scale);
                    
                    % Clean up the old mp fields.
                    if ~isfield(mp, 'exclusion_radius')
                        old_mp = mp;
                        mp  = [];
                        mp.hnsz = old_mp.hnsz;
                        mp.k = old_mp.k;
                        mp.exclusion_radius = 1.5;
                        mp.min_eig_thresh = 0.1;
                    end
                    mp_params = mp;
                    
                    % Update the file version.
                    version = ProgramInfo.version;
                    save(id_file, 'version', 'neurons', 'mp_params', '-v7.3');
                end
            end
        end

        function np_file = convertCZI(czi_file)
            %CONVERTCZI Convert a CZI file to NeuroPAL format.
            %
            % czi_file = the CZI file to convert
            % np_file = the NeuroPAL format file
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;
            
            % Open the file.
            [image_data, ~] = DataHandling.imreadCZI(czi_file);
            data = image_data.data;
            image_data.data = [];
            
            % Fix the image orientation and scale.
            % Note: image dimensions are different than matrix dimensions
            % images = (height, width, depth) and matrices = (x,y,z). To
            % convert between the two, we need to switch dimensions 1 and 2.
            data_order = 1:ndims(data);
            data_order(1) = 2;
            data_order(2) = 1;
            data = permute(data, data_order);
            image_data.scale(1) = image_data.scale(2);
            image_data.scale(2) = image_data.scale(2);
            
            % Setup the NP file data.
            info.file = czi_file;
            info.scale = image_data.scale * 1000000; % convert to microns
            info.DIC = image_data.dicChannel;
            
            % Determine the color channels.
            colors = image_data.colors;
            colors = round(colors/max(colors(:)));
            info.RGBW = nan(4,1);
            info.GFP = nan;
            for i = 1:size(colors,1)
                switch char(colors(i,:))
                    case [1,0,0] % red
                        info.RGBW(1) = i;
                    case [0,1,0] % green
                        info.RGBW(2) = i;
                    case [0,0,1] % blue
                        info.RGBW(3) = i;
                    case [1,1,1] % white
                        if i ~= info.DIC
                            info.RGBW(4) = i;
                        end
                    otherwise % GFP
                        info.GFP = i;
                end
            end
            
            % Did we find the GFP channel?
            if isnan(info.GFP) && size(colors,1) > 4
                
                % Assume the first unused channel is GFP.
                unused = setdiff(1:size(colors,1), info.RGBW);
                info.GFP = unused(1);
            end
            
            % Determine the gamma.
            %info.gamma = 1;
            %keys = lower(meta_data.keys);
            %gamma_i = find(contains(keys, 'gamma'),1);
            %if ~isempty(gamma_i)
            %    info.gamma = str2double(meta_data.values(gamma_i));
            %end
            info.gamma = DataHandling.NeuroPALImage.CZI_gamma_default;
            
            % Initialize the user preferences.
            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(size(data,3) / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;
            
            % Initialize the worm info.
            worm.body = 'Head';
            worm.age = 'Adult';
            worm.sex = 'XX';
            worm.strain = '';
            worm.notes = '';
                
            % Save the CZI file to our MAT file format.
            np_file = strrep(czi_file, 'czi', 'mat');
            version = ProgramInfo.version;
            save(np_file, 'version', 'data', 'info', 'prefs', 'worm', '-v7.3');
            clear data image_data
        end
        
        function np_file = convertND2(nd2_file)
            %CONVERTND2 Convert an ND2 file to NeuroPAL format.
            %
            % nd2_file = the ND2 file to convert
            % np_file = the NeuroPAL format file

            np_file = DataHandling.Helpers.nd2.convert_to( ...
                'npal', nd2_file);
        end

        function np_file = convertNWB(nwb_file)
            %CONVERTNWB Convert an NWB file to NeuroPAL format.
            %
            % nwb_file = the NWB file to convert
            % np_file = the NeuroPAL format file
            
            % Prefer direct HDF5/HDMF image conversion. MatNWB parses the
            % whole file and can fail on unrelated acquisition objects or
            % broken ExternalLinks before reaching the NeuroPAL image.
            np_file = DataHandling.NeuroPALImage.convertNWB_H5(nwb_file);
        end

        function np_file = convertNWB_H5(nwb_file)
            %CONVERTNWB_H5 Minimal NeuroPAL image conversion without MatNWB.
            %
            % Some valid NWB files trip MatNWB while parsing unrelated
            % acquisition series metadata. For image loading, we only need
            % the raw NeuroPAL image volume and a small amount of metadata,
            % all of which are available directly through HDF5.

            image_info = DataHandling.Helpers.nwb.image_data_info(nwb_file);
            image_group = image_info.group_path;
            image_volume_group = image_info.imaging_volume_path;

            layout = DataHandling.Helpers.nwb.image_layout(image_info);
            nc = layout.output_dims(4);

            info = struct();
            info.file = nwb_file;
            info.scale = DataHandling.Helpers.nwb.h5_read_numeric( ...
                nwb_file, [image_volume_group '/grid_spacing'], []);
            if isempty(info.scale)
                info.scale = DataHandling.Helpers.nwb.h5_read_numeric( ...
                    nwb_file, [image_group '/imaging_volume/grid_spacing'], [1 1 1]);
            end
            info.scale = double(info.scale(:).');
            [info.RGBW, info.DIC, info.GFP] = ...
                DataHandling.Helpers.nwb.infer_image_channels( ...
                    nwb_file, image_group, nc, 1:min(4, nc));
            info.gamma = DataHandling.Helpers.nwb.image_gamma( ...
                nwb_file, nc, DataHandling.NeuroPALImage.gamma_default);

            location = DataHandling.NeuroPALImage.h5_read_string( ...
                nwb_file, [image_volume_group '/location'], '');
            if isempty(location)
                location = DataHandling.NeuroPALImage.h5_read_string( ...
                    nwb_file, [image_group '/imaging_volume/location'], 'Head');
            end
            worm.body = DataHandling.NeuroPALImage.normalize_body(location);
            worm.age = DataHandling.NeuroPALImage.normalize_age( ...
                DataHandling.NeuroPALImage.h5_read_string( ...
                    nwb_file, '/general/subject/growth_stage', 'Adult'));
            worm.sex = DataHandling.NeuroPALImage.normalize_sex( ...
                DataHandling.NeuroPALImage.h5_read_string(nwb_file, '/general/subject/sex', 'XX'));
            worm.strain = DataHandling.NeuroPALImage.h5_read_string( ...
                nwb_file, '/general/subject/strain', '');
            worm.notes = DataHandling.NeuroPALImage.h5_read_string( ...
                nwb_file, '/general/subject/description', '');

            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(layout.output_dims(3) / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;

            [folder, name] = fileparts(nwb_file);
            np_file = fullfile(folder, [name '.mat']);
            version = Program.ProgramInfo.version;
            metadata = struct('version', version, 'info', info, ...
                'prefs', prefs, 'worm', worm);
            report = DataHandling.Helpers.nwb.stream_image_to_mat( ...
                nwb_file, image_info, np_file, metadata);
            Program.Helpers.debug_event('NWBConversion', ...
                ['Converted "%s" to "%s" using %d bounded chunks ' ...
                 '(chunk depth %d, resumed=%d).'], ...
                nwb_file, np_file, report.chunks_written, ...
                report.chunk_z, report.resumed);
        end

        function tf = h5_exists(file, path)
            tf = false;
            try
                h5info(file, path);
                tf = true;
            catch
            end
        end

        function value = h5_read_string(file, path, default_value)
            value = char(string(default_value));
            if ~DataHandling.NeuroPALImage.h5_exists(file, path)
                return
            end
            try
                raw = h5read(file, path);
                if iscell(raw)
                    raw = raw{1};
                end
                if isa(raw, 'uint8') || isa(raw, 'int8')
                    value = char(raw(:).');
                else
                    value = char(string(raw));
                end
            catch
                value = char(string(default_value));
            end
        end

        function body = normalize_body(location)
            valid_locations = {'Whole Worm', 'Head', 'Midbody', 'Anterior Midbody', ...
                'Central Midbody', 'Posterior Midbody', 'Tail'};
            body = 'Head';
            location = lower(char(string(location)));
            for j = 1:numel(valid_locations)
                if contains(lower(valid_locations{j}), location)
                    body = valid_locations{j};
                    return
                end
            end
        end

        function sex = normalize_sex(raw_sex)
            raw_sex = char(string(raw_sex));
            if any(strcmp(raw_sex, {'XO', 'O', 'o', 'M', 'm', 'Male', 'male'}))
                sex = 'XO';
            else
                sex = 'XX';
            end
        end

        function age = normalize_age(raw_age)
            raw_age = upper(strtrim(char(string(raw_age))));
            switch raw_age
                case {'ADULT', 'A', 'YA', 'YOUNG ADULT', 'YOUNG_ADULT', 'DAY 1 ADULT'}
                    age = 'Adult';
                case {'L4', 'L4 LARVA', 'L4_LARVA'}
                    age = 'L4';
                case {'L3', 'L3 LARVA', 'L3_LARVA'}
                    age = 'L3';
                case {'L2', 'L2 LARVA', 'L2_LARVA'}
                    age = 'L2';
                case {'L1', 'L1 LARVA', 'L1_LARVA'}
                    age = 'L1';
                otherwise
                    age = 'Adult';
            end
        end
        
        function [neurons, mp_params] = loadNeuronDataFromNWB(nwb_data, body_part, scale)
            %LOADNEURONDATAFROMNWB Load neuron annotations and detection parameters from NWB file
            %
            % This function extracts neuron data that was previously stored in companion ID files
            % but is now embedded within the NWB file using the ndx-multichannel-volume extension.
            %
            % Input:
            %   nwb_data = NWB file object loaded with nwbRead
            %   body_part = worm body part ('Head', 'Tail', etc.)
            %   scale = image scale for neuron creation
            %
            % Output:
            %   neurons = Neurons.Image object with loaded neuron data
            %   mp_params = detection parameters structure
            
            neurons = [];
            mp_params = [];
            
            try
                % Check if neuron annotation data exists in the NWB file
                if ~any(ismember(nwb_data.processing.keys, 'NeuronAnnotations'))
                    Program.Helpers.debug_log('No NeuronAnnotations processing module found in NWB file\n');
                    return;
                end
                
                neuron_module = nwb_data.processing.get('NeuronAnnotations');
                Program.Helpers.debug_log('Found NeuronAnnotations processing module\n');
                
                % Load neuron annotations table
                if any(ismember(neuron_module.dynamictable.keys, 'NeuronAnnotations'))
                    annotations_table = neuron_module.dynamictable.get('NeuronAnnotations');
                    
                    % Extract annotation data
                    user_annotations = annotations_table.vectordata.get('user_annotation').data.load();
                    annotation_confidences = annotations_table.vectordata.get('annotation_confidence').data.load();
                    is_annotation_on = annotations_table.vectordata.get('is_annotation_on').data.load();
                    is_emphasized = annotations_table.vectordata.get('is_emphasized').data.load();
                    deterministic_ids = annotations_table.vectordata.get('deterministic_id').data.load();
                    probabilistic_ids_str = annotations_table.vectordata.get('probabilistic_ids').data.load();
                    probabilistic_probs = annotations_table.vectordata.get('probabilistic_probs').data.load();
                    ranks = annotations_table.vectordata.get('rank').data.load();
                    
                    % Convert pipe-separated probabilistic IDs back to matrix format
                    % (The Neuron constructor expects probabilistic_ids as a matrix where each row is a neuron)
                    Program.Helpers.debug_log('DEBUG: Converting %d probabilistic ID strings to matrix format...\n', length(probabilistic_ids_str));
                    
                    % First, convert strings to cell arrays
                    prob_id_cells = cell(length(probabilistic_ids_str), 1);
                    max_ids = 0;
                    for i = 1:length(probabilistic_ids_str)
                        if ~isempty(probabilistic_ids_str{i})
                            split_ids = split(probabilistic_ids_str{i}, '|');
                            % Ensure each ID is a character vector, not string
                            prob_id_cells{i} = cellfun(@char, split_ids, 'UniformOutput', false);
                            max_ids = max(max_ids, length(prob_id_cells{i}));
                            if i == 1
                                Program.Helpers.debug_log('DEBUG: First prob IDs: %s -> %s\n', probabilistic_ids_str{i}, strjoin(prob_id_cells{i}, ', '));
                                Program.Helpers.debug_log('DEBUG: First ID type: %s\n', class(prob_id_cells{i}{1}));
                            end
                        else
                            prob_id_cells{i} = {};
                        end
                    end
                    
                    % Convert to matrix format (pad with empty strings)
                    if max_ids > 0
                        probabilistic_ids = cell(length(probabilistic_ids_str), max_ids);
                        for i = 1:length(probabilistic_ids_str)
                            for j = 1:length(prob_id_cells{i})
                                probabilistic_ids{i, j} = prob_id_cells{i}{j};
                            end
                            % Fill remaining columns with empty strings
                            for j = (length(prob_id_cells{i}) + 1):max_ids
                                probabilistic_ids{i, j} = '';
                            end
                        end
                        Program.Helpers.debug_log('DEBUG: Created probabilistic_ids matrix of size %dx%d\n', size(probabilistic_ids, 1), size(probabilistic_ids, 2));
                    else
                        probabilistic_ids = {};
                    end
                    
                    num_neurons = length(user_annotations);
                    Program.Helpers.debug_log('Found %d neurons in annotations table\n', num_neurons);
                    
                    % Debug: Check the annotation status values
                    Program.Helpers.debug_log('DEBUG: Sample is_annotation_on values: [%g, %g, %g, %g, %g]\n', ...
                        is_annotation_on(1), is_annotation_on(2), is_annotation_on(3), is_annotation_on(4), is_annotation_on(5));
                    Program.Helpers.debug_log('DEBUG: Unique is_annotation_on values: %s\n', mat2str(unique(is_annotation_on)));
                else
                    Program.Helpers.debug_log('No NeuronAnnotations table found in processing module\n');
                    return;
                end
                
                % Load neuron properties table
                if any(ismember(neuron_module.dynamictable.keys, 'NeuronProperties'))
                    properties_table = neuron_module.dynamictable.get('NeuronProperties');
                    
                    % Extract property data
                    positions = properties_table.vectordata.get('positions').data.load();
                    colors = properties_table.vectordata.get('colors').data.load();
                    color_readouts = properties_table.vectordata.get('color_readouts').data.load();
                    baselines = properties_table.vectordata.get('baselines').data.load();
                    covariances_flat = properties_table.vectordata.get('covariances').data.load();
                    aligned_xyzRGBs = properties_table.vectordata.get('aligned_xyzRGB').data.load();
                    
                    Program.Helpers.debug_log('DEBUG: Loaded property data shapes:\n');
                    Program.Helpers.debug_log('  positions: %s\n', mat2str(size(positions)));
                    Program.Helpers.debug_log('  colors: %s\n', mat2str(size(colors)));
                    Program.Helpers.debug_log('  color_readouts: %s\n', mat2str(size(color_readouts)));
                    Program.Helpers.debug_log('  baselines: %s\n', mat2str(size(baselines)));
                    Program.Helpers.debug_log('  covariances_flat: %s\n', mat2str(size(covariances_flat)));
                    Program.Helpers.debug_log('  aligned_xyzRGBs: %s\n', mat2str(size(aligned_xyzRGBs)));
                    
                    % Debug: Check actual position values
                    if ~isempty(positions) && size(positions, 1) >= 3
                        Program.Helpers.debug_log('DEBUG: Sample position values:\n');
                        for debug_i = 1:min(3, size(positions, 1))
                            Program.Helpers.debug_log('  Neuron %d positions: [%.3f, %.3f, %.3f]\n', debug_i, ...
                                positions(debug_i, 1), positions(debug_i, 2), positions(debug_i, 3));
                        end
                        Program.Helpers.debug_log('  Position data type: %s\n', class(positions));
                        Program.Helpers.debug_log('  Position range: X=[%.3f, %.3f], Y=[%.3f, %.3f], Z=[%.3f, %.3f]\n', ...
                            min(positions(:,1)), max(positions(:,1)), ...
                            min(positions(:,2)), max(positions(:,2)), ...
                            min(positions(:,3)), max(positions(:,3)));
                    end
                    
                    % Reshape covariances from flat format back to 3x3xN
                    % The data was stored as reshape(permute(covariances, [3, 1, 2]), [num_neurons, 9])
                    % So we need to reshape back and permute to get [3, 3, N] format expected by Neurons.Neuron.unmarshall
                    if size(covariances_flat, 2) == 9 && size(covariances_flat, 1) == num_neurons
                        % Data is stored as [num_neurons x 9], reshape back to [num_neurons, 3, 3] then permute to [3, 3, num_neurons]
                        covariances_temp = reshape(covariances_flat, [num_neurons, 3, 3]);
                        covariances = permute(covariances_temp, [2, 3, 1]); % [3, 3, num_neurons]
                    elseif size(covariances_flat, 1) == 9 && size(covariances_flat, 2) == num_neurons
                        % Data is stored as [9 x num_neurons], transpose and reshape
                        covariances_temp = reshape(covariances_flat', [num_neurons, 3, 3]);
                        covariances = permute(covariances_temp, [2, 3, 1]); % [3, 3, num_neurons]
                    else
                        Program.Helpers.debug_log('WARNING: Unexpected covariance data shape, creating default covariances\n');
                        covariances = repmat(eye(3), [1, 1, num_neurons]);
                    end
                    
                    Program.Helpers.debug_log('DEBUG: Reshaped covariances: %s\n', mat2str(size(covariances)));
                    
                    % The Neurons.Neuron.unmarshall function expects covariances(i,:,:) to work
                    % This means we need covariances to be [num_neurons, 3, 3], not [3, 3, num_neurons]
                    covariances = permute(covariances, [3, 1, 2]); % Convert to [num_neurons, 3, 3]
                    Program.Helpers.debug_log('DEBUG: Final covariances for unmarshall: %s\n', mat2str(size(covariances)));
                    Program.Helpers.debug_log('Found neuron properties for %d neurons\n', num_neurons);
                else
                    Program.Helpers.debug_log('No NeuronProperties table found in processing module\n');
                    return;
                end
                
                % Create superpixels structure for Neurons.Image constructor
                sp = struct();
                sp.positions = positions;
                sp.color = colors;
                sp.color_readout = color_readouts;
                sp.baseline = baselines;
                sp.covariances = covariances;
                sp.aligned_xyzRGB = aligned_xyzRGBs;
                
                % Add annotation data
                sp.annotation = user_annotations;
                sp.annotation_confidence = annotation_confidences;
                sp.is_annotation_on = is_annotation_on;
                sp.is_emphasized = is_emphasized;
                
                % Add auto ID data
                sp.deterministic_id = deterministic_ids;
                sp.probabilistic_ids = probabilistic_ids;
                sp.probabilistic_probs = probabilistic_probs;
                sp.rank = ranks;
                
                % Debug the superpixels structure
                Program.Helpers.debug_log('DEBUG: Superpixels structure fields and sizes:\n');
                fields = fieldnames(sp);
                for i = 1:length(fields)
                    field = fields{i};
                    value = sp.(field);
                    if isnumeric(value)
                        Program.Helpers.debug_log('  %s: %s %s\n', field, class(value), mat2str(size(value)));
                    elseif iscell(value)
                        Program.Helpers.debug_log('  %s: %s (length: %d)\n', field, class(value), length(value));
                    else
                        Program.Helpers.debug_log('  %s: %s\n', field, class(value));
                    end
                end
                
                % Load atlas version if available
                if any(ismember(neuron_module.nwbdatainterface.keys, 'AtlasVersion'))
                    Program.Helpers.debug_log('DEBUG: Loading atlas version...\n');
                    atlas_version_data = neuron_module.nwbdatainterface.get('AtlasVersion');
                    sp.atlas_version = atlas_version_data.data.load();
                    Program.Helpers.debug_log('DEBUG: Loaded atlas version: %s\n', sp.atlas_version);
                else
                    Program.Helpers.debug_log('DEBUG: No atlas version found in NWB file\n');
                end
                
                % Create neurons object
                Program.Helpers.debug_log('DEBUG: Attempting to create Neurons.Image object...\n');
                Program.Helpers.debug_log('DEBUG: Using scale: [%.6f, %.6f, %.6f]\n', scale(1), scale(2), scale(3));
                Program.Helpers.debug_log('DEBUG: Using body_part: %s\n', body_part);
                try
                    neurons = Neurons.Image(sp, body_part, 'scale', scale);
                    Program.Helpers.debug_log('Successfully loaded %d neurons from NWB file\n', num_neurons);
                    
                    % Debug: Check the actual positions in the created neurons object
                    if ~isempty(neurons) && ~isempty(neurons.neurons) && length(neurons.neurons) >= 3
                        Program.Helpers.debug_log('DEBUG: Checking created neuron positions:\n');
                        for debug_i = 1:min(3, length(neurons.neurons))
                            pos = neurons.neurons(debug_i).position;
                            Program.Helpers.debug_log('  Created neuron %d position: [%.3f, %.3f, %.3f]\n', debug_i, pos(1), pos(2), pos(3));
                        end
                    end
                catch neuron_create_ME
                    Program.Helpers.debug_log('ERROR creating Neurons.Image: %s\n', neuron_create_ME.message);
                    Program.Helpers.debug_log('Stack trace: %s\n', getReport(neuron_create_ME));
                    
                    % Try to diagnose the covariance issue
                    Program.Helpers.debug_log('DEBUG: Investigating covariance issue...\n');
                    Program.Helpers.debug_log('  covariances size: %s\n', mat2str(size(sp.covariances)));
                    Program.Helpers.debug_log('  num_neurons: %d\n', num_neurons);
                    if size(sp.covariances, 3) ~= num_neurons
                        Program.Helpers.debug_log('  MISMATCH: covariances 3rd dimension (%d) != num_neurons (%d)\n', ...
                            size(sp.covariances, 3), num_neurons);
                        % Try to fix by creating default covariances
                        Program.Helpers.debug_log('  Creating default identity covariances...\n');
                        sp.covariances = repmat(eye(3), [1, 1, num_neurons]);
                        neurons = Neurons.Image(sp, body_part, 'scale', scale);
                        Program.Helpers.debug_log('Successfully created neurons with default covariances\n');
                    else
                        rethrow(neuron_create_ME);
                    end
                end
                
            catch ME
                warning(ME.identifier, 'Could not load neuron annotation data from NWB file: %s', ME.message);
                Program.Helpers.debug_log('Stack trace: %s\n', getReport(ME));
                neurons = [];
            end
            
            try
                % Load detection parameters
                if any(ismember(nwb_data.processing.keys, 'DetectionParameters'))
                    detection_module = nwb_data.processing.get('DetectionParameters');
                    
                    if any(ismember(detection_module.dynamictable.keys, 'DetectionParameters'))
                        detection_table = detection_module.dynamictable.get('DetectionParameters');
                        
                        % Extract parameter data
                        param_names = detection_table.vectordata.get('parameter_name').data.load();
                        param_values = detection_table.vectordata.get('parameter_value').data.load();
                        
                        % Reconstruct mp_params structure
                        mp_params = struct();
                        for i = 1:length(param_names)
                            param_name = param_names{i};
                            param_value_str = param_values{i};
                            
                            % Convert string back to appropriate data type
                            if contains(param_value_str, '[') && contains(param_value_str, ']')
                                % Vector/matrix parameter
                                rows = split(strip(extractBetween( ...
                                    string(param_value_str), '[', ']')), ';');
                                numeric_rows = cellfun(@(row) sscanf( ...
                                    strrep(row, ',', ' '), '%f').', cellstr(rows), ...
                                    'UniformOutput', false);
                                row_widths = cellfun(@numel, numeric_rows);
                                if ~isempty(row_widths) && all(row_widths == row_widths(1))
                                    mp_params.(param_name) = vertcat(numeric_rows{:});
                                else
                                    mp_params.(param_name) = param_value_str;
                                end
                            else
                                % Scalar parameter
                                param_value = str2double(param_value_str);
                                if ~isnan(param_value)
                                    mp_params.(param_name) = param_value;
                                else
                                    mp_params.(param_name) = param_value_str;
                                end
                            end
                        end
                        
                        Program.Helpers.debug_log('Loaded detection parameters from NWB file\n');
                    end
                end
                
            catch ME
                warning(ME.identifier, 'Could not load detection parameters from NWB file: %s', ME.message);
                mp_params = [];
            end
        end
        
        function np_file = convertAny(any_file)
            %CONVERTANY Convert any file to NeuroPAL format.
            %
            % any_file = the ND2 file to convert
            % np_file = the NeuroPAL format file
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;
            
            % Open the file.
            if strcmp(any_file(end-3:end), '.lif')
                [image_data, ~] = DataHandling.imreadLif(any_file);
            elseif strcmp(any_file(end-2:end), '.h5')
                [image_data, ~] = DataHandling.imreadVlab(any_file);
            else
                [image_data, ~] = DataHandling.imreadAny(any_file);
            end
            data = image_data.data;
            
            % Fix the image orientation and scale.
            % Note: image dimensions are different than matrix dimensions
            % images = (height, width, depth) and matrices = (x,y,z). To
            % convert between the two, we need to switch dimensions 1 and 2.
            data_order = 1:ndims(data);
            data_order(1) = 2;
            data_order(2) = 1;
            data = permute(data, data_order);
            image_data.scale(1) = image_data.scale(2);
            image_data.scale(2) = image_data.scale(2);
            
            % Setup the NP file data.
            info.file = any_file;
            info.scale = image_data.scale;
            info.DIC = image_data.dicChannel;
            
            % Determine the color channels.
            colors = image_data.colors;
            colors = round(colors/max(colors(:)));
            info.RGBW = nan(4,1);
            info.GFP = nan;
            for i = 1:size(colors,1)
                switch char(colors(i,:))
                    case [1,0,0] % red
                        info.RGBW(1) = i;
                    case [0,1,0] % green
                        info.RGBW(2) = i;
                    case [0,0,1] % blue
                        info.RGBW(3) = i;
                    case [1,1,1] % white
                        if i ~= info.DIC
                            info.RGBW(4) = i;
                        end
                    otherwise % GFP
                        info.GFP = i;
                end
            end
            
            % Did we find the GFP channel?
            if isnan(info.GFP) && size(colors,1) > 4
                
                % Assume the first unused channel is GFP.
                unused = setdiff(1:size(colors,1), info.RGBW);
                info.GFP = unused(1);
            end
            
            % Determine the gamma.
            %info.gamma = 1;
            %keys = lower(meta_data.keys);
            %gamma_i = find(contains(keys, 'gamma'),1);
            %if ~isempty(gamma_i)
            %    info.gamma = str2double(meta_data.values(gamma_i));
            %end
            info.gamma = DataHandling.NeuroPALImage.gamma_default;
            
            % Initialize the user preferences.
            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(size(data,3) / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;
            
            % Initialize the worm info.
            worm.body = 'Head';
            worm.age = 'Adult';
            worm.sex = 'XX';
            worm.strain = '';
            worm.notes = '';
            
            % Save the file to our MAT file format.
            suffix = strfind(any_file, '.');
            if isempty(suffix)
                suffix = length(any_file);
            end
            np_file = cat(2, any_file(1:(suffix(end) - 1)), '.mat');
            version = ProgramInfo.version;
            save(np_file, 'version', 'data', 'info', 'prefs', 'worm', '-v7.3');
        end
    end
end
