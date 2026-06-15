classdef neurons
    
    properties
    end
    
    methods (Static)
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

            % Unselect the selected neuron.
            if ~isempty(app.selected_neuron) && app.image_neurons.neurons(app.selected_neuron).is_selected == true

                % Unselect the neuron.
                app.image_neurons.neurons(app.selected_neuron).is_selected = false;
                app.selected_neuron = [];

                % Disable the ID fields.
                app.AutoIDDropDown.Items = {''};
                app.AutoIDDropDown.Value = '';
                app.IDEditField.Value = '';

                % Disable the input fields.
                app.AutoIDDropDown.Enable = 'off';
                app.IDEditField.Enable = 'off';
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

        function reset()
            app = Program.app;

            app.selected_neuron = [];
            Program.Handlers.neurons.unselect_neuron();
            app.UserNeuronIDsListBox.Items = {};
            app.UserNeuronIDsListBox.ItemsData = [];
            app.UserNeuronIDsListBox.Value = {};
        end
    end
end
