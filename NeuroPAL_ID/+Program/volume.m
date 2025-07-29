classdef volume < handle
    % VOLUME A class that encapsulates a volumetric (or possibly video) dataset.
    %
    % This class depends on helper classes in +DataHandling/+Helpers, one
    % per file format. For example, +DataHandling/+Helpers/nwb.m, 
    % +DataHandling/+Helpers/nd2.m, etc.
    %
    % Example usage:
    %   vol = volume('C:\data\myImage.nwb');
    %   vol.load();        % read metadata
    %   dataSlice = vol.read('z',1);  % read 1st Z-slice
    %   infoStruct = vol.info();
    %
    
    properties
        % References to helper classes for reading/writing the volume
        read_class = [];    % (Not strictly required if we rely on read_obj below)
        read_obj  = [];     % Reader object (e.g. returned by nwbRead, bfGetReader, etc.)
        read_mod = [];      % Reader module returned by nwbRead.

        % Path info
        fmt  = '';          % Extension of the volume path (e.g. 'nwb', 'tiff')
        name = '';          % Name of volume file
        path = '';          % Complete volume path

        % Metadata
        device = [];        % The device used to capture this volume.
        subject = [];       % The subject captured in this volume.
        settings = [];      % NeuroPAL_ID settings for this volume.

        % Cursor
        x = -1;
        y = -1;
        z = -1;
        c = -1;
        t = -1;

        % Dimensionality
        nx = -1;            % Width of the volume
        ny = -1;            % Height of the volume
        nz = -1;            % Depth of the volume
        nc = -1;            % Number of channels
        nt = -1;            % Number of timepoints (frames)
        dims = [];          % Array of size (1,5): [nx, ny, nz, nc, nt]
        native_dims = [];   % Dims as loaded from file

        % Channels
        channels = {};      % Cell array for the names of each channel
        rgb = [];           % Indices of channels corresponding to [R,G,B] if relevant
        
        is_video = -1;      % Boolean indicating video vs. single-volume; -1 if uninitialized
        processing_steps = {};
        
        dtype = 0;       % Datatype numeric code
        dtype_max = [];  % Integer maximum for this volume's datatype.
        dtype_str = '';  % Datatype string, e.g. 'uint8', 'double', etc.
        is_valid_dtype = -1;
    end
    
    %%%--- BEGIN REFACTOR (Error Handling Guide: Logging Properties) ---%%%
    properties (Access = private)
        error_log = {}; % Store error history for debugging
        warning_count = 0;
    end
    %%%--- END REFACTOR ---%%%

    methods
        function obj = volume(path)
            % Constructor for the volume class
            try
                %%%--- BEGIN REFACTOR (Error Handling Guide: Constructor Validation) ---%%%
                obj.validateConstructorInputs(path);
                
                app = Program.app;
                app.state.now('Creating volume');

                [~, ~, fmt] = fileparts(path);
                fmt = fmt(2:end);

                obj.path = path;
                obj.is_video = Program.Validation.lineage() == 2;
                obj.load();
                %%%--- OLD CODE ---%%%
                % app = Program.app;
                % app.state.now('Creating volume');
                % if nargin == 0
                %     error('No path provided for volume class constructor.');
                % elseif isempty(path)
                %     error('Empty path provided for volume class constructor.');
                % else
                %     [~, ~, fmt] = fileparts(path);
                %     fmt = fmt(2:end);
                % 
                %     %%%--- BEGIN BUG FIX (Report #8: Cross-platform path and file existence check) ---%%%
                %     helper_path = fullfile('+DataHandling', '+Helpers', [fmt, '.m']);
                %     if ~isfile(helper_path)
                %         error('No helper script found for format %s.', fmt)
                %     elseif ~isfile(path)
                %         error('Image file does not exist: %s', path)
                %     else
                %         obj.path = path;
                %         obj.is_video = Program.Validation.lineage() == 2;
                %         obj.load();
                %     end
                %     %%%--- OLD CODE ---%%%
                %     % if ~isfile(sprintf("+DataHandling\\+Helpers\\%s.m", fmt))
                %     %     error('No helper script found for format %s.', fmt)
                %     % else
                %     %     obj.path = path;
                %     %     obj.is_video = Program.Validation.lineage() == 2;
                %     %     obj.load();
                %     % end
                %     %%%--- END BUG FIX ---%%%
                % end
                %%%--- END REFACTOR ---%%%
            catch ME
                obj.logError(ME, 'volume', struct('input_path', path));
                rethrow(ME);
            end
        end
        
        function infoStruct = info(obj)
            propList = properties(obj);
            infoStruct = struct();
            for k = 1:numel(propList)
                infoStruct.(propList{k}) = obj.(propList{k});
            end
        end
        
        function load(obj)
            [~, fname, ext] = fileparts(obj.path);
            obj.name = fname;
            if startsWith(ext, '.')
                ext = ext(2:end);
            end
            obj.fmt = ext;
            
            if DataHandling.Helpers.npal.is_npal_file(obj.path)
                obj.read_class = DataHandling.Helpers.npal;
                obj.read_obj = obj.read_class.get_reader(obj.path);
            else
                obj.read_class = DataHandling.Helpers.(obj.fmt);
                obj.read_obj = obj.read_class.get_reader(obj.path);
            end
            
            metadata = obj.read_metadata();
            
            obj.nx = metadata.nx;
            obj.ny = metadata.ny;
            obj.nz = metadata.nz;
            obj.nc = metadata.nc;
            obj.nt = metadata.nt;
            
            %%%--- BEGIN REFACTOR (Error Handling Guide: Dimension Validation) ---%%%
            temp_dims = [obj.nx, obj.ny, obj.nz, obj.nc, obj.nt];
            obj.validateDimensions(temp_dims);
            obj.dims = temp_dims;
            %%%--- OLD CODE ---%%%
            % obj.dims = [obj.nx, obj.ny, obj.nz, obj.nc, obj.nt];
            %%%--- END REFACTOR ---%%%
            
            obj.x = round(obj.nx/2);
            obj.y = round(obj.ny/2);
            obj.z = round(obj.nz/2);
            obj.native_dims = metadata.native_dims;

            if obj.is_video == -1
                obj.is_video = (obj.nt > 1);
            end
            
            if isfield(metadata, 'channels')
                obj.channels = metadata.channels;
                obj.sort_channels();
            end

            if isfield(metadata, 'device')
                obj.device = metadata.device;
            else
                obj.device = struct();
                obj.device.manufacturer = '';
                obj.device.voxel_resolution = [1 1 1];
            end
            
            if isfield(metadata, 'dtype')
                obj.dtype = metadata.dtype;
            end

            if isfield(metadata, 'dtype_str')
                obj.dtype_str = metadata.dtype_str;
            end

            [obj.is_valid_dtype, obj.dtype, obj.dtype_str, obj.dtype_max] = Program.Helpers.resolve_dtype(obj);

            if isfield(metadata, 'subject')
                obj.subject = Program.subject(metadata);
            else
                obj.subject = Program.subject();
            end
            
            obj.validate();
        end
        
        %%%--- BEGIN REFACTOR (Error Handling Guide: Improved Read Method) ---%%%
        function data = read(obj, cursor, varargin)
            try
                if isempty(obj.read_class)
                    throw(MException('Volume:IOError', ...
                        ['Read failed: The volume object is not properly initialized. ' ...
                         'The file reader helper is missing. Try reloading the volume.']));
                end

                create_cursor = ~isempty(varargin);
                have_cursor = exist('cursor', 'var') && isa(cursor, 'Program.GUI.cursor');

                if ~have_cursor
                    try
                        if create_cursor
                            cursor = Program.GUI.cursor.generate(obj.dims, cursor, varargin{:});
                        else
                            cursor = Program.GUI.cursor.generate(obj.dims, 'z', obj.z);
                        end
                    catch ME_cursor
                        throw(MException('Volume:ValidationError', 'Failed to create cursor: %s', ME_cursor.message));
                    end
                end

                obj.validateCursorBounds(cursor);

                try
                    data = obj.read_class.read(obj, 'cursor', cursor);
                catch ME_read
                    throw(MException('Volume:IOError', 'Low-level read failed at cursor %s: %s', ...
                        obj.getCursorDetails(cursor), ME_read.message));
                end

                if isempty(data)
                    cursor_details = obj.getCursorDetails(cursor);
                    obj.logWarning('Volume:EmptyData', ...
                        ['Read operation returned empty data for cursor at %s. ' ...
                         'The requested slice or frame might be out of bounds or contain no valid data.'], ...
                         cursor_details);
                end

                if ~isa(data, obj.dtype_str)
                    try
                        data = cast(data, obj.dtype_str);
                    catch ME_cast
                        throw(MException('Volume:TypeCastError', ...
                            'Failed to cast data to expected type %s: %s', obj.dtype_str, ME_cast.message));
                    end
                end

            catch ME
                obj.logError(ME, 'read', struct('cursor', cursor));
                rethrow(ME);
            end
        end
        %%%--- OLD CODE ---%%%
        % function data = read(obj, cursor, varargin)
        %     % DK Error checker
        %     if isempty(obj.read_class)
        %         error(['Read failed: The volume object is not properly initialized. ' ...
        %                'The file reader helper is missing. Try reloading the volume.']);
        %     end
        %     % DK End
        % 
        %     create_cursor = ~isempty(varargin);
        %     have_cursor = exist('cursor', 'var') ...
        %         && isa(cursor, 'Program.GUI.cursor');
        % 
        %     if ~have_cursor
        %         if create_cursor
        %             cursor = Program.GUI.cursor.generate(obj.dims, ...
        %                 cursor, varargin{:});
        %         else
        %             cursor = Program.GUI.cursor.generate( ...
        %                 obj.dims, 'z', obj.z);
        %         end
        %     end
        % 
        %     data = obj.read_class.read(obj, ...
        %         'cursor', cursor);
        % 
        %     %%%--- BEGIN BUG FIX (Report #6: Safer empty data warning) ---%%%
        %     if isempty(data)
        %         if isprop(cursor, 'z') && isprop(cursor, 't') && isprop(cursor, 'c')
        %             cursor_details = sprintf('Z:%d, T:%d, C:%d', cursor.z, cursor.t, cursor.c);
        %         else
        %             cursor_details = 'Unknown cursor position';
        %         end
        %         warning(['Read operation returned empty data for cursor at %s. ' ...
        %                  'The requested slice or frame might be out of bounds or contain no valid data.'], ...
        %                  cursor_details);
        %     end
        %     %%%--- OLD CODE ---%%%
        %     % if isempty(data)
        %     %     %warning(['Read operation returned empty data. The requested slice or frame ' ...
        %     %     %         'might be out of bounds or contain no valid data.']);
        %     %     cursor_details = sprintf('Z:%d, T:%d, C:%d', cursor.z, cursor.t, cursor.c);
        %     %     warning(['Read operation returned empty data for cursor at %s. ' ...
        %     %              'The requested slice or frame might be out of bounds or contain no valid data.'], ...
        %     %              cursor_details);
        %     % end
        %     %%%--- END BUG FIX ---%%%
        %     % DK End
        % 
        %     % Some formats return double arrays on chunk read.
        %     % Check for this and if so, correct the datatype.
        %     if ~isa(data, obj.dtype_str)
        %         data = cast(data, obj.dtype_str);
        %     end
        % end
        %%%--- END REFACTOR ---%%%

        function mdata = read_metadata(obj)
            config = Program.config;
            mdata = obj.read_class.get_metadata(obj);
            mdata_fields = fieldnames(mdata);
            if any(~ismember( ...
                    mdata_fields, ...
                    config.default.fields.md_volume))

                switch obj.fmt
                    case 'nwb'
                        if obj.is_video ~= -1
                            if obj.is_video
                                obj.read_mod = mdata_fields{ ...
                                    contains(lower(mdata_fields), ...
                                    'calcium')};
                            else
                                obj.read_mod = mdata_fields{ ...
                                    ~contains(lower(mdata_fields), ...
                                    'calcium')};
                            end
        
                            mdata = mdata.(obj.read_mod);

                        else
                            choice = uiconfirm(Program.window, ...
                                "Which volume would you like to load?", ...
                                "NeuroPAL_ID", 'Options', mdata_fields);
                            obj.is_video = contains(lower(choice), ...
                                'calcium');

                            obj.read_mod = choice;
                            mdata = mdata.(choice);
                        end

                    otherwise
                        wtf_idx = find(~ismember( ...
                            mdata_fields, ...
                            config.default.fields.md_volume));
                        wtf_str = mdata_fields{wtf_idx};
                        error("%s datahandling function returned " + ...
                            "unexpected metadata fields in file %s:" + ...
                            "\n%s", upper(obj.fmt), obj.name, ...
                            join(wtf_str, ', '))
                end
            end
        end

        function [array, raw_array] = render(obj, varargin)
            if isempty(varargin)
                cursor = Program.GUI.cursor( ...
                    'volume', obj, ...
                    'interface', Program.state().interface);
            elseif isa(varargin{1}, 'Program.GUI.cursor')
                cursor = varargin{1};
            else
                cursor = Program.GUI.cursor.generate( ...
                    obj.dims, varargin{:});
            end
            
            raw_array = obj.read(cursor);

            sz = size(raw_array);
            sz(4) = 3; 
            array = zeros(sz, 'like', raw_array);

            for ch_idx = cursor.c1:cursor.c2
                channel = obj.channels{ch_idx};
                arr_idx = channel.arr_idx - cursor.c1 + 1;

                if ~channel.is_rendered
                    continue;
                end
                
                channel_data = raw_array(:, :, :, arr_idx);
                adjusted_data = imadjustn(channel_data, channel.lh_in, channel.lh_out, channel.gamma);
                
                if channel.is_rgb
                    rgb_plane_idx = find(obj.rgb == ch_idx);
                    if ~isempty(rgb_plane_idx)
                         array(:, :, :, rgb_plane_idx) = array(:, :, :, rgb_plane_idx) + adjusted_data;
                    end
                else
                    pseudocolor_array = Program.render.generate_pseudocolor(adjusted_data, channel);
                    array = array + pseudocolor_array;
                end
            end
        end
        
        function converted_instance = convert(obj, fmt)
            try
                %%%--- BEGIN REFACTOR (Error Handling Guide: Convert Validation) ---%%%
                if ~ischar(fmt) && ~isstring(fmt)
                    throw(MException('Volume:ValidationError', 'Format must be a string or character array, got %s', class(fmt)));
                end
                fmt = char(fmt);
                if isempty(fmt)
                    throw(MException('Volume:ValidationError', 'Format cannot be empty'));
                end

                if strcmp(obj.fmt, fmt)
                    converted_instance = obj;
                    return;
                end
                
                % This assumes a helper method isFormatSupported exists, which is good practice
                % if ~obj.isFormatSupported(fmt)
                %     throw(MException('Volume:ValidationError', 'Unsupported format "%s"', fmt));
                % end
                %%%--- END REFACTOR ---%%%

                app = Program.app;
                app.state.now("Converting %s.%s to %s format", obj.name, obj.fmt, fmt);
                
                dtype_flag = strcmpi(fmt, 'double') || startsWith(fmt, 'uint');
                if dtype_flag
                    target_dtype = fmt;
                    new_name = sprintf('%s-%s', obj.name, fmt);
                    target_path = strrep(obj.path, obj.name, new_name);
                    target_helper = obj.read_class;
                    target_helper.create(target_path, 'like', obj, 'dtype', target_dtype);
                else
                    target_dtype = obj.dtype_str;
                    if ~strcmp(fmt, 'npal')
                        target_path = strrep(obj.path, obj.fmt, fmt);
                    else
                        npal_name = sprintf('%s-NPAL', obj.name);
                        target_path = strrep(obj.path, obj.name, npal_name);
                        target_path = strrep(target_path, obj.fmt, 'mat');
                    end
                    target_helper = feval(str2func(['DataHandling.Helpers.' fmt]));
                    target_helper.create(target_path, 'like', obj);
                end
                
                if obj.is_video
                    chunking_method = 'framewise';
                else
                    chunking_method = 'slicewise';
                end

                try
                    obj.write_chunk( ...
                        target_path, ...
                        'method', chunking_method, ...
                        'helper', target_helper, ...
                        'dtype', target_dtype);
                catch ME_write
                    if isfile(target_path)
                        try
                            delete(target_path);
                            obj.logWarning('Volume:CleanupSuccess', 'Deleted incomplete file after conversion failure: %s', target_path);
                        catch delete_err
                            obj.logWarning('Volume:CleanupFailed', 'Could not clean up partial file: %s. Error: %s', target_path, delete_err.message);
                        end
                    end
                    rethrow(ME_write);
                end
                
                converted_instance = Program.volume(target_path);
                converted_instance.load();
            catch ME
                obj.logError(ME, 'convert', struct('target_format', fmt));
                rethrow(ME);
            end
        end
        
        function write(obj, varargin)
            p = inputParser();
            addParameter(p, 't', 1);
            addParameter(p, 'z', 1);
            addParameter(p, 'c', []);
            addParameter(p, 'x', []);
            addParameter(p, 'y', []);
            addParameter(p, 'mode', 'chunk');
            addParameter(p, 'arr', []);
            parse(p, varargin{:});
            
            if isempty(p.Results.arr)
                error('You must supply the ''arr'' parameter with data to write.');
            end
            
            writeDataSize = size(p.Results.arr);
            expectedHeight = obj.ny;
            expectedWidth = obj.nx;
            if writeDataSize(1) ~= expectedHeight || writeDataSize(2) ~= expectedWidth
                error(['Write failed: The dimensions of the input array (%d x %d) do not match ' ...
                       'the expected slice dimensions of the volume (%d x %d).'], ...
                       writeDataSize(1), writeDataSize(2), expectedHeight, expectedWidth);
            end

            obj.read_obj.write('mode', p.Results.mode, ...
                               't', p.Results.t, ...
                               'z', p.Results.z, ...
                               'c', p.Results.c, ...
                               'x', p.Results.x, ...
                               'y', p.Results.y, ...
                               'arr', p.Results.arr);
        end

        function update_channels(obj, target)
            %%%--- BEGIN REFACTOR (Error Handling Guide: Channel Index Validation) ---%%%
            if nargin < 2
                c_start = 1;
                c_end = obj.nc;
            else
                obj.validateChannelIndex(target);
                c_start = target;
                c_end = target;
            end
            %%%--- OLD CODE ---%%%
            % if nargin < 2
            %     c_start = 1;
            %     c_end = obj.nc;
            % 
            % elseif isnumeric(target)
            %     if target < 1 || target > obj.nc
            %         error('Channel index %d is out of bounds for this volume (1-%d).', target, obj.nc);
            %     end
            %     c_start = target;
            %     c_end = target;
            % end
            %%%--- END REFACTOR ---%%%

            for tc=c_start:c_end
                obj.channels{tc}.update;
            end

            obj.nc = length(obj.channels);
        end

        function out = get(obj, query)
            query = lower(query);
            out = [];
            switch query
                case 'rgbw'
                    out = cell2mat(cellfun(@(x)(x.arr_idx*x.is_rgb), obj.channels,'UniformOutput', false));
                case {'gfp', 'dic'}
                    found = cell2mat(cellfun(@(x)(x.arr_idx*strcmp(x.color, query)), obj.channels,'UniformOutput', false));
                    if any(found)
                        found = found(found~=0);
                    end
                case 'gamma'
                    out = cell2mat(cellfun(@(x)(x.gamma), obj.channels,'UniformOutput', false));
                otherwise
                    obj.logWarning('Volume:UnknownQuery', ...
                        'The requested property "%s" is not recognized. Valid options are: ''rgbw'', ''gfp'', ''dic'', ''gamma''.', ...
                        query);
            end
        end

        function validate_channels(obj)
            indices_to_remove = [];
            for ch = 1:length(obj.channels)
                if isequal(obj.channels{ch}.fluorophore, 'NA')
                    indices_to_remove(end+1) = ch;
                end
            end
            
            if ~isempty(indices_to_remove)
                obj.channels(indices_to_remove) = [];
            end
            
            obj.nc = length(obj.channels);
        end
        
        %%%--- BEGIN REFACTOR (Error Handling Guide: Health Check Methods) ---%%%
        function [is_healthy, issues] = healthCheck(obj)
            issues = {};
            is_healthy = true;
            try
                if ~isfile(obj.path)
                    issues{end+1} = sprintf('Volume file no longer exists: %s', obj.path);
                    is_healthy = false;
                end
                if isempty(obj.read_class) || isempty(obj.read_obj)
                    issues{end+1} = 'Reader objects are not properly initialized';
                    is_healthy = false;
                end
                if any(obj.dims <= 0)
                    issues{end+1} = sprintf('Invalid dimensions: [%s]', num2str(obj.dims));
                    is_healthy = false;
                end
                if obj.nc ~= length(obj.channels)
                    issues{end+1} = sprintf('Channel count mismatch: nc=%d, channels length=%d', obj.nc, length(obj.channels));
                    is_healthy = false;
                end
                if obj.is_valid_dtype ~= 1
                    issues{end+1} = sprintf('Invalid data type: %s', obj.dtype_str);
                    is_healthy = false;
                end
            catch ME
                issues{end+1} = sprintf('Health check failed unexpectedly: %s', ME.message);
                is_healthy = false;
            end
            if ~is_healthy
                obj.logWarning('Volume:HealthCheckFailed', 'Volume health check failed with %d issues', length(issues));
            end
        end

        function report = getErrorReport(obj)
            report = struct();
            report.error_count = numel(obj.error_log);
            report.warning_count = obj.warning_count;
            report.recent_errors = obj.error_log(max(1, end-9):end); % Last 10 errors
            [is_healthy, issues] = obj.healthCheck();
            report.is_healthy = is_healthy;
            report.health_issues = issues;
            report.volume_info = struct('path', obj.path, 'format', obj.fmt, 'dimensions', obj.dims);
        end
        %%%--- END REFACTOR ---%%%
    end

    methods (Access = private)
        function write_chunk(obj, t_file, varargin)
            p = inputParser();
            addParameter(p, 'method', 'slice');
            addParameter(p, 'helper', obj.read_class);
            addParameter(p, 'dtype', obj.dtype_str);
            parse(p, varargin{:});

            app = Program.app;

            should_convert_dtype = ~strcmpi(p.Results.dtype, obj.dtype_str);
            
            switch p.Results.method
                case {'frame', 'framewise'}
                    app.state.progress('Frame (%.f/%.f)', obj.nt);
                    for this_frame = 1:obj.nt
                        app.state.progress();
                        app.state.progress('Slice (%.f/%.f)', obj.nz);
                        for this_slice = 1:obj.nz
                            app.state.progress();
                            chunk = obj.read('t', this_frame, 'z', this_slice);
                            if numel(size(chunk)) <= 4
                                null_data = zeros(size(chunk, 1), size(chunk, 2), 1, size(chunk, 3), 1, class(chunk));
                                null_data(:, :, 1, :, 1) = chunk;
                                chunk = null_data;
                            end
                            if should_convert_dtype
                                chunk = cast(chunk, p.Results.dtype);
                            end
                            p.Results.helper.write('mode', 'chunk', 'file', t_file, 't', this_frame, 'z', this_slice, 'arr', chunk);
                        end
                    end
                case {'slice', 'slicewise'}
                    app.state.progress('Slice %.f/%.f', obj.nz);
                    for this_slice = 1:obj.nz
                        app.state.progress();
                        chunk = obj.read('z', this_slice);
                        if numel(size(chunk)) <= 3
                            null_data = zeros(size(chunk, 1), size(chunk, 2), 1, size(chunk, 3), class(chunk));
                            null_data(:, :, 1, :) = chunk;
                            chunk = null_data;
                        end
                        if should_convert_dtype
                            chunk = cast(chunk, p.Results.dtype);
                        end
                        p.Results.helper.write('mode', 'chunk', 'file', t_file, 'z', this_slice, 'arr', chunk);
                    end
            end
        end

        function obj = sort_channels(obj)
            order = {'red', 'green', 'blue', 'white', 'dic', 'gfp', 'gcamp'};
            colors = cellfun(@(x)x.color, obj.channels, 'UniformOutput', false);
            [~, idx_in_order] = ismember(colors, order);
            N = numel(idx_in_order);
            gui_idx = zeros(1, N);
            firstOccurrenceUsed = false(1, max(idx_in_order)); 
            duplicates = [];
            unknowns = [];
            for k = 1:N
                idx = idx_in_order(k);
                if idx > 0
                    if ~firstOccurrenceUsed(idx)
                        gui_idx(k) = idx;
                        firstOccurrenceUsed(idx) = true;
                    else
                        duplicates(end+1) = k; %#ok<AGROW>
                    end
                else
                    unknowns(end+1) = k; %#ok<AGROW>
                end
            end
            maxRecognized = max(idx_in_order);
            if isempty(maxRecognized)
                maxRecognized = 0;
            end
            nextAvail = maxRecognized + 1;
            for d = 1:numel(duplicates)
                gui_idx(duplicates(d)) = nextAvail;
                nextAvail = nextAvail + 1;
            end
            for u = 1:numel(unknowns)
                gui_idx(unknowns(u)) = nextAvail;
                nextAvail = nextAvail + 1;
            end
            for k = 1:N
                obj.channels{k}.gui_idx = gui_idx(k);
            end
            if numel(unique(gui_idx)) ~= numel(gui_idx)
                obj.logWarning('Volume:DuplicateGuiIdx', 'Duplicate gui_idx values were generated during channel sorting.');
            end
            [~, obj.rgb] = ismember(sort(gui_idx), gui_idx);
            num_rgb = min(3, numel(obj.rgb));
            obj.rgb = obj.rgb(1:num_rgb);
        end

        function validate(obj)
            if obj.is_video == 1 && obj.nt <= 1
                error('Video volume is flagged, but nt (%.1f) <= 1.', obj.nt);
            end
            if obj.nc ~= length(obj.channels)
                error('Volume has %.f specified channel dimensions, but only %.f channels.', obj.nc, length(obj.channels));
            end
            for c=1:obj.nc
                obj.channels{c}.set('parent', obj);
            end
        end
        
        %%%--- BEGIN REFACTOR (Error Handling Guide: Private Validation and Logging Methods) ---%%%
        function validateConstructorInputs(obj, path)
            if nargin < 2 || isempty(path)
                throw(MException('Volume:ValidationError', 'A non-empty path must be provided.'));
            end
            if ~ischar(path) && ~isstring(path)
                throw(MException('Volume:ValidationError', 'Path must be a string or character array, got %s', class(path)));
            end
            path = char(path);
            if ~isfile(path)
                throw(MException('Volume:IOError', 'Image file does not exist: %s', path));
            end
            [status, attrs] = fileattrib(path);
            if ~status || ~attrs.UserRead
                throw(MException('Volume:IOError', 'Cannot read file (permission denied): %s', path));
            end
            [~,~, fmt] = fileparts(path);
            if isempty(fmt)
                throw(MException('Volume:ValidationError', 'File has no extension: %s', path));
            end
            fmt = fmt(2:end);
            helper_path = fullfile('+DataHandling', '+Helpers', [fmt, '.m']);
            if ~isfile(helper_path)
                throw(MException('Volume:ValidationError', 'No helper script found for format "%s".', fmt));
            end
        end

        function validateDimensions(obj, dims)
            if ~isnumeric(dims) || length(dims) ~= 5
                throw(MException('Volume:ValidationError', 'Dimensions must be a numeric array of length 5'));
            end
            if any(dims <= 0) || any(~isfinite(dims)) || any(dims ~= round(dims))
                throw(MException('Volume:ValidationError', 'All dimensions must be positive finite integers, got: [%s]', num2str(dims)));
            end
        end
        
        function validateChannelIndex(obj, ch_idx)
            if ~isnumeric(ch_idx) || ~isscalar(ch_idx) || ch_idx ~= round(ch_idx)
                throw(MException('Volume:ValidationError', 'Channel index must be a scalar integer, got %g', ch_idx));
            end
            if ch_idx < 1 || ch_idx > obj.nc
                throw(MException('Volume:ValidationError', 'Channel index %d is out of bounds (valid range: 1-%d)', ch_idx, obj.nc));
            end
        end
        
        function validateCursorBounds(obj, cursor)
            if cursor.z < 1 || cursor.z > obj.nz
                throw(MException('Volume:ValidationError', 'Z cursor position %d is out of bounds (1-%d)', cursor.z, obj.nz));
            end
            if cursor.t < 1 || cursor.t > obj.nt
                throw(MException('Volume:ValidationError', 'T cursor position %d is out of bounds (1-%d)', cursor.t, obj.nt));
            end
            if cursor.c1 < 1 || cursor.c2 > obj.nc
                throw(MException('Volume:ValidationError', 'C cursor position [%d-%d] is out of bounds (1-%d)', cursor.c1, cursor.c2, obj.nc));
            end
        end
        
        function details = getCursorDetails(obj, cursor)
            try
                if isprop(cursor, 'z') && isprop(cursor, 't') && isprop(cursor, 'c1')
                    details = sprintf('Z:%d, T:%d, C:%d', cursor.z, cursor.t, cursor.c1);
                else
                    details = 'Unknown cursor position';
                end
            catch
                details = 'Invalid cursor object';
            end
        end

        function logError(obj, ME, method_name, context)
            timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            log_entry = struct('timestamp', timestamp, 'method', method_name, ...
                'error_id', ME.identifier, 'message', ME.message, ...
                'context', context, 'file', obj.path);
            obj.error_log{end+1} = log_entry;
            if length(obj.error_log) > 50
                obj.error_log = obj.error_log(end-49:end);
            end
        end

        function logWarning(obj, warning_id, message, varargin)
            obj.warning_count = obj.warning_count + 1;
            formatted_message = sprintf(message, varargin{:});
            warning(warning_id, formatted_message);
            log_entry = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                'type', 'WARNING', 'warning_id', warning_id, 'message', formatted_message);
            obj.error_log{end+1} = log_entry;
        end
        %%%--- END REFACTOR ---%%%
    end
end
