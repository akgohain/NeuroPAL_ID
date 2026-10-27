classdef GUIPreferences < handle
    %GUIPreferences GUI preferences.
    
    % Constant GUI properties.
    properties (Constant, Access = public)
        
        % Version.
        %version = Program.ProgramInfo.version;
        
        % Preferences file info.
        prefs_dir = ''; %'NeuroPAL_ID/appdata/';
        prefs_name = '.NeuroPAL_ID_prefs.mat';
    end
    
    % User GUI properties.
    properties (Access = public)
        
        % Preferences file.
        prefs_file = [];
        
        % Data directories.
        image_dir = [];
        trace_path = [];
        seg_path = [];
        
        % Display info.
        GFP_color = [1,1,0]; % GFP reporter color for GUI
        neuron_dot; % neuron dot info: (un)selected marker + line sizes
        is_show_birth_times = false; % show the neuron birth times?
        is_auto_name = true; % auto-complete neuron names?
        is_autoID_updates = true; % auto-update neuron IDs?
        detection_backend = 'mp'; % one of: mp, nn, cellpose, yolo, spotiflow_supervised
        is_MP_detect = true; % are we using MP (or NN) to detect neurons?
    end
    
    % GUI public static methods.
    methods (Static, Access = public)
        function obj = instance()
            %INSTANCE get the GUIPreferences singelton.
             persistent instance;
             if isempty(instance)
                 
                 % Instantiate the class.
                 obj = Program.GUIPreferences();
                 
                 % Setup the preferences file location.
                 root=Runtime.Configuration.userRoot();
                 if ~isfolder(root), mkdir(root); end
                 obj.prefs_file = fullfile(root,obj.prefs_name);
                 
                 % Add the image directory.
                 if ispc
                     user_dir = what('\');
                 else
                     user_dir = what('~/');
                 end
                 obj.image_dir = user_dir.path;
                 
                 % Initilaize the neurons dots.
                obj.neuron_dot.marker.unselected = 40; % unselected neuron marker size
                if ismac % selected neuron marker size
                    obj.neuron_dot.marker.selected = 200;
                else
                    obj.neuron_dot.marker.selected = 100;
                end
                obj.neuron_dot.line = 2; % neuron line size
                % Applied to ID scatter markers in get_slice / renders.draw_z (keep mask on/off identical).
                obj.neuron_dot.marker_size_scale = 0.3;
                obj.neuron_dot.marker_line_scale = 0.3;
                 
                 % Save the instantiation.
                 instance = obj;
             else
               obj = instance;
             end
        end
        
        function saved = save()
            %SAVE save the GUI preferences to their file.
            
            % Instantiate the class.
            obj = Program.GUIPreferences.instance();
            
            saved=false;
            if isequal(getappdata(groot,'npal_prefs_write_blocked'),obj.prefs_file), return; end
            temporary='';
            try
                if isfolder(obj.prefs_file), error('Program:Preferences:Destination','The preference destination is a folder.'); end
                folder=fileparts(obj.prefs_file);
                if ~isfolder(folder), mkdir(folder); end
                temporary=[tempname(folder) '.mat'];
                version = Program.ProgramInfo.version;
                GUI_prefs = obj;
                save(temporary, 'version', 'GUI_prefs');
                [ok,message]=movefile(temporary,obj.prefs_file,'f');
                if ~ok, error('Program:Preferences:Write','%s',message); end
                saved=true;
            catch ME
                if ~isempty(temporary) && isfile(temporary), delete(temporary); end
                warning('Program:Preferences:Write','Display preferences were not saved; this session remains usable. %s',ME.message);
            end
        end
        
        function is_loaded = load()
            %LOAD load the GUI preferences from their file.
            
            % Instantiate the class.
            obj = Program.GUIPreferences.instance();
            
            % Load the preferences.
            is_loaded = false;
            if exist(obj.prefs_file, 'file')
                is_loaded = true;
                try
                    prefs = load(obj.prefs_file);
                    if ~isfield(prefs,'GUI_prefs'), error('Program:Preferences:Format','Missing GUI preferences.'); end
                    Program.GUIPreferences.read(prefs.GUI_prefs);
                catch ME
                    backup=[obj.prefs_file '.unreadable-' char(java.util.UUID.randomUUID()) '.mat'];
                    ok=false;
                    if isfile(obj.prefs_file)
                        try, [ok,~]=copyfile(obj.prefs_file,backup); catch, end
                    end
                    if ~ok, setappdata(groot,'npal_prefs_write_blocked',obj.prefs_file); end
                    warning('Program:Preferences:Read','Saved display preferences could not be read. Defaults remain available. Original preferences: %s. %s',obj.prefs_file,ME.message);
                end
            end
        end
        
        function read(prefs)
            %READ read and store the GUI preferences.
            
            % Instantiate the class.
            obj = Program.GUIPreferences.instance();
            
            if ~(isstruct(prefs) || isa(prefs,'Program.GUIPreferences')) || ~isscalar(prefs)
                error('Program:Preferences:Format','Invalid GUI preferences.');
            end
            value=Program.GUIPreferences.value(prefs,'image_dir',obj.image_dir);
            if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value) && ~ismissing(value))
                if isfolder(value), obj.image_dir=char(value); end
            end
            value=Program.GUIPreferences.value(prefs,'GFP_color',[1 1 0]);
            if ~isnumeric(value) || ~isreal(value) || numel(value)~=3 || any(~isfinite(value(:)) | value(:)<0 | value(:)>1)
                value=[1 1 0];
            end
            obj.GFP_color=double(value(:)');
            dot=struct('marker',struct('selected',100+100*ismac,'unselected',40),'line',2, ...
                'marker_size_scale',.3,'marker_line_scale',.3);
            incoming=Program.GUIPreferences.value(prefs,'neuron_dot',struct());
            if isstruct(incoming) && isscalar(incoming)
                if isfield(incoming,'marker') && isstruct(incoming.marker) && isscalar(incoming.marker)
                    for field={'selected','unselected'}
                        key=field{1}; value=Program.GUIPreferences.value(incoming.marker,key,NaN);
                        if Program.GUIPreferences.inRange(value,1,100000), dot.marker.(key)=value; end
                    end
                end
                for field={'line','marker_size_scale','marker_line_scale'}
                    key=field{1};value=Program.GUIPreferences.value(incoming,key,NaN);
                    if Program.GUIPreferences.inRange(value,eps,50), dot.(key)=value; end
                end
            end
            obj.neuron_dot=dot;
            for field={'is_show_birth_times','is_auto_name','is_autoID_updates','is_MP_detect'}
                key=field{1}; value=Program.GUIPreferences.value(prefs,key,obj.(key));
                if (isnumeric(value) || islogical(value)) && isscalar(value) && isreal(value) && ismember(value,[0 1])
                    obj.(key)=logical(value);
                end
            end
            value=Program.GUIPreferences.value(prefs,'detection_backend',obj.detection_backend);
            if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value) && ~ismissing(value))
                obj.detection_backend=char(value);
            end
            obj.detection_backend = Program.GUIPreferences.normalize_detection_backend( ...
                obj.detection_backend, obj.is_MP_detect);
            obj.is_MP_detect = strcmp(obj.detection_backend, 'mp');
        end

        function [marker_size_scale, marker_line_scale] = neuron_marker_display_scales()
            %NEURON_MARKER_DISPLAY_SCALES Scatter SizeData / LineWidth scale for ID view markers.
            % Fixed values so neuron dots look the same when opening a file, when toggling
            % Cellpose masks, and across get_slice vs renders.draw_z redraw paths. Stored
            % neuron_dot.marker_*_scale prefs are not applied here (they remain for compatibility).
            marker_size_scale = 0.3;
            marker_line_scale = 0.3;
        end

        function backend = get_detection_backend(varargin)
            %GET_DETECTION_BACKEND Return the normalized detector backend label.
            if nargin >= 1 && isa(varargin{1}, 'Program.GUIPreferences')
                obj = varargin{1};
            else
                obj = Program.GUIPreferences.instance();
            end
            backend = Program.GUIPreferences.normalize_detection_backend( ...
                obj.detection_backend, obj.is_MP_detect);
        end

        function set_detection_backend(varargin)
            %SET_DETECTION_BACKEND Store the detector backend and legacy flag.
            if nargin == 1
                obj = Program.GUIPreferences.instance();
                backend = varargin{1};
            elseif nargin == 2 && isa(varargin{1}, 'Program.GUIPreferences')
                obj = varargin{1};
                backend = varargin{2};
            else
                error('Program:GUIPreferences:InvalidBackendCall', ...
                    'set_detection_backend expects either (backend) or (obj, backend).');
            end
            backend = Program.GUIPreferences.normalize_detection_backend(backend, true);
            obj.detection_backend = backend;
            obj.is_MP_detect = strcmp(backend, 'mp');
        end
        
        function dot = inputNeuronDot()
            %INPUTNEURONDOT get the neuron dot info from the user.
            
            % Instantiate the class.
            obj = Program.GUIPreferences.instance();
            
            % Initialize the input dialog.
            title = 'Neuron Dots';
            prompt = {'Selected neuron dot size:', ...
                'Unselected neuron dot size:', ...
                'Neuron line size:'};
            definput = {num2str(obj.neuron_dot.marker.selected), ...
                num2str(obj.neuron_dot.marker.unselected), ...
                num2str(obj.neuron_dot.line)};
            dims = [1 35];
            
            % Get the user input.
            dot = [];
            answer = inputdlg(prompt, title, dims, definput);
            if isempty(answer)
                return;
            end
            
            % Parse the user input.
            dot.marker.selected = round(str2double(answer{1}));
            dot.marker.unselected = round(str2double(answer{2}));
            dot.line = round(str2double(answer{3}));
            numbers=[dot.marker.selected dot.marker.unselected dot.line];
            if any(~isfinite(numbers)) || any(numbers(1:2)>100000) || numbers(3)>50
                dot=[];
                uialert(Program.window,'Enter finite neuron sizes up to 100000 and a line width up to 50.','Neuron dots');
                return;
            end
            
            % Check the user input.
            if dot.marker.selected < 1
                dot.marker.selected = 1;
            end
            if dot.marker.unselected < 1
                dot.marker.unselected = 1;
            end
            if dot.line < 1
                dot.line = obj.neuron_dot.line;
            end
            
            % Store the user input.
            obj.neuron_dot.marker.selected = dot.marker.selected;
            obj.neuron_dot.marker.unselected = dot.marker.unselected;
            obj.neuron_dot.line = dot.line;
        end
        
        function color = inputGFPColor()
            %INPUTGFPCOLOR get the GFP reporter color from the user.
            
            % Instantiate the class.
            obj = Program.GUIPreferences.instance();
            
            % Determine the current value.
            value = 1;
            if isequaln(obj.GFP_color, [1,1,0]) % 'yellow'
                value = 1;
            elseif isequaln(obj.GFP_color, [0,1,1]) % 'cyan'
                value = 2;
            elseif isequaln(obj.GFP_color, [1,0,1]) % 'magenta'
                value = 3;
            elseif isequaln(obj.GFP_color, [1,1,1]) % 'white'
                value = 4;
            elseif isequaln(obj.GFP_color, [1,0,0]) % 'red'
                value = 5;
            elseif isequaln(obj.GFP_color, [0,1,0]) % 'green'
                value = 6;
            elseif isequaln(obj.GFP_color, [0,0,1]) % 'blue'
                value = 7;
            end
            
            % Initialize the input dialog.
            title = 'GFP Reporter Color';
            prompt = 'Color for the GFP reporter channel:';
            list = {'yellow', 'cyan', 'magenta', 'white', ...
                'red', 'green', 'blue'};
            [color_i,~] = listdlg('PromptString', prompt, 'Name', title, ...
                'ListString', list, 'InitialValue', value, ...
                'SelectionMode', 'single');
            
            % Get the user input.
            color = [];
            if isempty(color_i)
                return;
            end
            
            % Parse and store the user input.
            color = list{color_i};
            switch color
                case 'yellow'
                    obj.GFP_color = [1,1,0];
                case 'cyan'
                    obj.GFP_color = [0,1,1];
                case 'magenta'
                    obj.GFP_color = [1,0,1];
                case 'white'
                    obj.GFP_color = [1,1,1];
                case 'red'
                    obj.GFP_color = [1,0,0];
                case 'green'
                    obj.GFP_color = [0,1,0];
                case 'blue'
                    obj.GFP_color = [0,0,1];
            end
        end
    end
    
    
    %% PRIVATE.
    
    % GUI private methods.
    methods (Static, Access = private)
        % Hide the constructor.
        function obj = GUIPreferences()
        end
    end

    methods (Static, Access = private)
        function value = value(source,name,fallback)
            value=fallback;
            if (isstruct(source) && isfield(source,name)) || (isobject(source) && isprop(source,name))
                value=source.(name);
            end
        end
        function yes = inRange(value,low,high)
            yes=isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && value>=low && value<=high;
        end
        function backend = normalize_detection_backend(backend, is_mp_detect)
            %NORMALIZE_DETECTION_BACKEND Canonicalize persisted detector backend values.
            if nargin < 1 || isempty(backend)
                backend = '';
            end
            if nargin < 2
                is_mp_detect = true;
            end

            backend = lower(strtrim(char(string(backend))));
            switch backend
                case {'mp', 'matching_pursuit'}
                    backend = 'mp';
                case {'nn', 'neural', 'neural_network'}
                    backend = 'nn';
                case {'cellpose', 'cp'}
                    backend = 'cellpose';
                case {'yolo', 'yolov8'}
                    backend = 'yolo';
                case {'detection_moe', 'moe'}
                    backend = 'detection_moe';
                case {'spotiflow', 'spotiflow_supervised'}
                    backend = 'spotiflow_supervised';
                otherwise
                    if is_mp_detect
                        backend = 'mp';
                    else
                        backend = 'nn';
                    end
            end
        end
    end
end
