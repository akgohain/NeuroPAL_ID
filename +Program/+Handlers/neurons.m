classdef neurons
    
    properties
    end
    
    methods (Static)
        function [double_click, token] = begin_click(app, hit, target)
            % Keep separate click sequences for each image or neuron target.
            persistent clock
            if isempty(clock), clock = tic; end
            previous = getappdata(app.CELL_ID, 'neuron_click_sequence');
            if ~isempty(previous) && ~Program.Handlers.neurons.click_source_matches(app, previous)
                previous.pending = false;
            end
            point = double(hit.IntersectionPoint(1:2));
            z = round(app.ZSlider.Value);
            neuron_index = sscanf(char(string(target)), 'neuron:%d');
            target = [char(string(app.image_file)), '|', char(string(target))];
            [double_click, state] = Program.Handlers.neurons.advance_click( ...
                previous, point, z, target, hit.Button, toc(clock), app.mouse_clicked.double_click_delay);
            state.file = app.image_file; state.tab = app.TabGroup.SelectedTab;
            state.revision = Program.Helpers.main_display_source_revision(app);
            state.neuron_index = []; state.neuron = [];
            if isscalar(neuron_index) && ~isempty(app.image_neurons) && ...
                    neuron_index >= 1 && neuron_index <= numel(app.image_neurons.neurons)
                state.neuron_index = neuron_index;
                state.neuron = app.image_neurons.neurons(neuron_index);
            end
            setappdata(app.CELL_ID, 'neuron_click_sequence', state);
            token = state.serial;
        end

        function pending = is_pending_click(app, token)
            % A second click or a different target cancels the delayed selection.
            pending = false;
            if ~isvalid(app) || ~isvalid(app.CELL_ID), return; end
            state = getappdata(app.CELL_ID, 'neuron_click_sequence');
            if ~isempty(state)
                pending = state.pending && state.serial == token && ...
                    Program.Handlers.neurons.click_source_matches(app, state);
            end
        end

        function matches = click_source_matches(app, state)
            matches = false;
            if ~all(isfield(state, {'file', 'tab', 'revision', 'neuron_index', 'neuron'})), return; end
            matches = state.z == round(app.ZSlider.Value) && strcmp(state.file, app.image_file) && ...
                isequal(state.tab, app.TabGroup.SelectedTab) && ...
                isequal(state.revision, Program.Helpers.main_display_source_revision(app));
            if matches && ~isempty(state.neuron_index)
                matches = ~isempty(app.image_neurons) && ...
                    state.neuron_index <= numel(app.image_neurons.neurons) && ...
                    isequal(app.image_neurons.neurons(state.neuron_index), state.neuron);
            end
        end

        function [double_click, state] = advance_click(previous, point, z, target, button, time, delay)
            % A double-click must stay on the same target and slice, nearby in XY.
            serial = 1; double_click = button == 2;
            if ~isempty(previous)
                serial = previous.serial + 1;
                if button == 1 && previous.pending && previous.button == 1
                    double_click = time >= previous.time && time - previous.time <= delay && ...
                        previous.z == z && strcmp(previous.target, target) && ...
                        sum((previous.point(:) - point(:)).^2) <= 4^2;
                end
            end
            state = struct('serial', serial, 'time', time, 'point', point, ...
                'z', z, 'target', target, 'button', button, ...
                'pending', button == 1 && ~double_click);
        end

        function finish_id_save(app)
            % Release the edit guard even when saving raises an error.
            if isvalid(app)
                app.is_saving_ID = false;
            end
        end

        function initialize(neurons)
            app = Program.app;

            if ~isempty(neurons)
                app.image_neurons = neurons;
                Program.Routines.GUI.enable_neurons;                        % Program.GUIHandling.gui_lock(app, 'enable', 'neuron_gui');
            else
                body = 'Head';
                if isfield(app.worm, 'body') && ~isempty(app.worm.body)
                    body = app.worm.body;
                end
                app.image_neurons = Neurons.Image([], body, 'scale', app.image_um_scale');
            end
        end

        function unselect_neuron(varargin)
            % Unselect the currently selected neuron. Optional argument, re-draw the image?
            % Note: Matlab buffers re-draws so, if you want them to execute in an orderly fashion,
            % you need to only make one call.

            app = Program.app;

            % Clear the selection even when a new detection replaced its neuron array.
            Program.GUI.ManualIDController.unselect(app);
            if ~isempty(app.selected_neuron)

                % Unselect the neuron.
                index = app.selected_neuron;
                if ~isempty(app.image_neurons) && isscalar(index) && isfinite(index) && ...
                        index == round(index) && index >= 1 && index <= numel(app.image_neurons.neurons)
                    app.image_neurons.neurons(index).is_selected = false;
                end
                app.selected_neuron = [];

                % Disable the ID fields.
                app.AutoIDDropDown.Items = {''};
                app.AutoIDDropDown.Value = '';
                Program.GUI.ManualIDInput.setValue(app, '');

                % Disable the input fields.
                app.AutoIDDropDown.Enable = 'off';
                Program.GUI.ManualIDInput.setEnabled(app, 'off');
                app.AutoIDButton.Enable = 'off';
                app.UserIDButton.Enable = 'off';

                % Redraw the Z-slice.
                is_redraw = true; % re-draw the image?
                if ~isempty(varargin)
                    is_redraw = varargin{1};
                end
                if is_redraw

                    % Give the GUI time to update.
                    pause(0.2);

                    % Re-draw (same path as Z-slider / mask toggle: get_slice).
                    Program.Routines.ID.get_slice(app.ZSlider, app.image_view, app.XY);
                end
            end
        end

        function save_id_file()
            % Save the current identities without crossing the app's
            % private-method boundary from an external package routine.
            app = Program.app;
            if isempty(app.id_file) || isempty(app.image_neurons)
                return
            end

            Program.GUI.ManualIDService.save(app);
        end

        function reset()
            app = Program.app;

            Program.Handlers.neurons.unselect_neuron(false);
            app.selected_neuron = [];
            app.UserNeuronIDsListBox.Items = {};
            app.UserNeuronIDsListBox.ItemsData = [];
            app.UserNeuronIDsListBox.Value = {};
        end
    end
end
