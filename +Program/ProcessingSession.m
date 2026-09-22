classdef ProcessingSession
    %PROCESSINGSESSION Keep image previews and their neuron annotations together.
    methods (Static)
        function capture(app)
            Program.ProcessingSession.clear(app);
            if isappdata(app.CELL_ID,'processing_intensity_range')
                rmappdata(app.CELL_ID,'processing_intensity_range');
            end
            if ~strcmp(app.VolumeDropDown.Value, 'Colormap'), return; end
            folder = tempname; mkdir(folder);
            snapshot = struct('path', app.image_file, 'id_file', app.id_file, ...
                'prefs', app.image_prefs, 'info', app.image_info, ...
                'scale', app.image_um_scale, 'gamma', app.image_gamma, ...
                'neurons', Program.ProcessingSession.copyNeurons(app.image_neurons), ...
                'folder', folder, 'pixels', false, 'lazy', isempty(app.image_data), ...
                'cleanup', onCleanup(@() Program.ProcessingSession.removeFolder(folder)));
            setappdata(app.CELL_ID, 'processing_session', snapshot);
            Program.GUIHandling.capture_processing_defaults(app, 'colormap', true);
        end

        function snapshot = get(app)
            snapshot = [];
            if isappdata(app.CELL_ID, 'processing_session')
                snapshot = getappdata(app.CELL_ID, 'processing_session');
            end
        end

        function ensure(app)
            snapshot = Program.ProcessingSession.get(app);
            if isempty(snapshot), Program.ProcessingSession.capture(app); end
        end

        function checkpointPixels(app)
            Program.ProcessingSession.ensure(app);
            snapshot = Program.ProcessingSession.get(app);
            if snapshot.pixels, return; end
            % Include IDs edited in the main tab since this image was opened.
            snapshot.neurons = Program.ProcessingSession.copyNeurons(app.image_neurons);
            snapshot.id_file = app.id_file;
            % Store the original pixels on disk rather than keeping another volume in RAM.
            if ~isempty(app.image_data)
                data = app.image_data;
                save(fullfile(snapshot.folder, 'pixels.mat'), 'data', '-v7.3');
            end
            snapshot.pixels = true;
            setappdata(app.CELL_ID, 'processing_session', snapshot);
        end

        function stageIDs(app)
            snapshot = Program.ProcessingSession.get(app);
            if ~isempty(snapshot) && snapshot.pixels
                app.id_file = fullfile(snapshot.folder, 'preview_ID.mat');
            end
        end

        function restored = discard(app)
            snapshot = Program.ProcessingSession.get(app);
            restored = ~isempty(snapshot);
            if ~restored, return; end
            if snapshot.pixels
                if snapshot.lazy
                    app.image_data = [];
                else
                    original = load(fullfile(snapshot.folder, 'pixels.mat'), 'data');
                    app.image_data = original.data;
                end
            end
            if snapshot.pixels
                app.image_neurons = Program.ProcessingSession.copyNeurons(snapshot.neurons);
            end
            app.image_file = snapshot.path;
            app.id_file = snapshot.id_file;
            app.proc_image = matfile(snapshot.path);
            app.image_prefs = snapshot.prefs;
            app.image_info = snapshot.info;
            app.image_um_scale = snapshot.scale;
            app.image_gamma = snapshot.gamma;
            if ~snapshot.pixels, Program.ProcessingSession.refreshColors(app); end
            app.image_data_zscored = [];
            app.selected_neuron = [];
            if ~isempty(app.image_neurons)
                for i = 1:numel(app.image_neurons.neurons)
                    app.image_neurons.neurons(i).is_selected = false;
                end
            end
            if isappdata(app.CELL_ID, 'proc_runtime_dirty')
                rmappdata(app.CELL_ID, 'proc_runtime_dirty');
            end
        end

        function tf = dirty(app)
            tf = ~isempty(fieldnames(app.flags));
            if isappdata(app.CELL_ID, 'proc_runtime_dirty')
                tf = tf || logical(getappdata(app.CELL_ID, 'proc_runtime_dirty'));
            end
        end

        function proceed = prepareOpen(app)
            proceed = true;
            if isempty(Program.ProcessingSession.get(app)) || ~Program.ProcessingSession.dirty(app)
                return;
            end
            answer = uiconfirm(app.CELL_ID, 'Save the image-processing changes?', ...
                'Unsaved changes', 'Options', {'Save', 'Discard', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            switch answer
                case 'Save'
                    proceed = Program.Routines.Processing.save();
                case 'Discard'
                    Program.Routines.Processing.reset();
                otherwise
                    proceed = false;
            end
        end

        function clear(app)
            if isappdata(app.CELL_ID, 'processing_session')
                rmappdata(app.CELL_ID, 'processing_session');
            end
        end

        function copy = copyNeurons(neurons)
            copy = [];
            if isempty(neurons), return; end
            copy = Neurons.Image([], 'scale', neurons.scale);
            copy.bodypart = neurons.bodypart;
            copy.atlas_version = neurons.atlas_version;
            if isa(neurons.meta_data, 'containers.Map') && neurons.meta_data.Count > 0
                copy.meta_data = containers.Map(neurons.meta_data.keys, neurons.meta_data.values);
            end
            names = properties(Neurons.Neuron);
            for i = 1:numel(neurons.neurons)
                n = Neurons.Neuron;
                for j = 1:numel(names), n.(names{j}) = neurons.neurons(i).(names{j}); end
                copy.neurons(i) = n;
            end
        end

        function refreshColors(app)
            if isempty(app.image_data) || isempty(app.image_neurons) || isempty(app.image_neurons.neurons)
                return;
            end
            app.image_neurons.update_colors(Methods.ColorReadout(app.image_data), [], app.image_prefs.RGBW);
            app.refreshAutoIDList();
        end

        function run(app, action)
            % Keep failed callbacks usable and retain the pending changes.
            try
                switch action
                    case 'save', Program.Routines.Processing.save();
                    case 'reset', Program.Routines.Processing.reset();
                    case 'rotate', Program.GUIHandling.confirm_processing_rotation(app);
                    case 'mirrorz', Program.GUIHandling.apply_processing_mirror_z(app);
                    case 'crop', Program.Routines.Processing.crop();
                    case 'applycrop', Program.crop_rotate_gui.preview_output(app);
                    case 'normalize', Program.GUIHandling.commit_processing_normalize_colors(app);
                end
            catch ME
                app.logEvent('Processing', getReport(ME, 'extended', 'hyperlinks', 'off'), 0);
                uialert(app.CELL_ID, ME.message, 'Image processing failed');
            end
            Program.GUIHandling.update_processing_commit_state(app);
        end

        function removeFolder(folder)
            if isfolder(folder), rmdir(folder, 's'); end
        end
    end
end
