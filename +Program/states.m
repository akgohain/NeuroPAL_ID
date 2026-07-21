classdef states < dynamicprops
    
    properties
    end
    
    methods (Access = public)        
        function set(keyword, value)
            states = Program.states;
            states.(keyword) = value;
            Program.states(states);
        end

        function clear(keyword)
            states = Program.states;
            states = rmfield(states, keyword);
            Program.states(states);
        end
    end

    methods (Static, Access = public)
        function state = instance()
            %INSTANCE Return stable defaults for legacy loader callers.
            %
            % Several format helpers use Program.states.instance(), but the
            % original class never implemented that entry point. Keep this
            % lightweight state struct until those helpers are migrated to
            % the newer app state object.
            persistent state_obj
            if isempty(state_obj)
                state_obj = struct( ...
                    'is_initialized', false, ...
                    'is_video', false, ...
                    'is_lazy', false, ...
                    'debug_mode', false);
            end
            state = state_obj;
        end

        function bool = debug()
            state = Program.states.instance();
            bool = isfield(state, 'debug_mode') && logical(state.debug_mode);
        end

        function now(varargin)
            %NOW Compatibility bridge used by older model objects.
            try
                app = Program.app;
                if ~isempty(app) && isprop(app, 'state') && ...
                        ~isempty(app.state) && ismethod(app.state, 'now')
                    app.state.now(varargin{:});
                end
            catch
            end
        end
    end

    methods (Access = private)
        function obj = states(new_states)
            persistent state_obj

            if nargin > 0
                state_obj = new_states;
            elseif isempty(state_obj)
                state_obj = struct('is_initialized', {0});
            end

            obj = state_obj;
        end
    end
end
