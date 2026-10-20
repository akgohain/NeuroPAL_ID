classdef ArtifactRemoval
    %ARTIFACTREMOVAL Stage pixel cleanup without deleting neuron annotations.
    methods (Static)
        function changed = run(app, mode)
            changed = false;
            try
                changed = Program.ArtifactRemoval.apply(app, mode);
            catch ME
                app.logEvent('Artifacts', getReport(ME, 'extended', 'hyperlinks', 'off'), 0);
                uialert(app.CELL_ID, ME.message, 'Artifact removal');
            end
        end

        function changed = apply(app, mode, options)
            if nargin < 3, options = struct(); end
            Program.HeavyJob.assertIdle();
            context = Program.ArtifactRemoval.prepare(app, mode);
            changed = false;
            switch context.mode
                case 'manual'
                    if isfield(options, 'ConfirmFcn')
                        answer = options.ConfirmFcn();
                    else
                        answer = uiconfirm(app.CELL_ID, ...
                            ['Outline an artifact on the projection. The outlined pixels will be cleared ' ...
                            'in the assigned image channels across all Z slices. Neuron IDs and centers are kept.'], ...
                            'Manually remove artifacts', 'Options', {'Remove', 'Cancel'}, ...
                            'DefaultOption', 1, 'CancelOption', 2);
                    end
                    if ~strcmp(answer, 'Remove'), return; end
                    projection = Program.Helpers.main_display_projection(app);
                    if isempty(projection) || ~isequal(size(projection, [1 2]), context.dims(1:2))
                        error('NeuroPAL:ArtifactPreview', ...
                            'The NeuroPAL image preview is unavailable. Reopen the image before removing artifacts.');
                    end
                    if isfield(options, 'MaskFcn')
                        mask = options.MaskFcn(projection);
                    else
                        mask = Methods.Preprocess.manual_artifact_removal(projection, 'YXC');
                    end
                    if isempty(mask), return; end
                case 'automatic'
                    job = Program.HeavyJob.acquire('Automatic artifact removal');
                    cleanup = onCleanup(@() delete(job));
                    mask = Methods.Preprocess.automatic_artifact_mask(context.data, context.rgb);
                    clear cleanup
            end
            Program.ArtifactRemoval.checkContext(app, context);
            mask = Program.ArtifactRemoval.checkMask(mask, context);
            if ~any(mask(:)), return; end
            Program.ArtifactRemoval.ensureProcessing(app);
            Program.ArtifactRemoval.checkContext(app, context);
            job = Program.HeavyJob.acquire([context.mode ' artifact removal']);
            cleanup = onCleanup(@() delete(job));
            output = context.data;
            for c = reshape(context.channels, 1, [])
                for z = 1:context.dims(3)
                    if strcmp(context.mode, 'manual'), plane_mask = mask;
                    else, plane_mask = mask(:, :, z); end
                    plane = output(:, :, z, c);
                    plane(plane_mask) = 0;
                    output(:, :, z, c) = plane;
                end
            end
            if isequaln(output, context.data), return; end
            Program.ArtifactRemoval.publish(app, output, options);
            changed = true;
        end

        function context = prepare(app, mode)
            mode = lower(char(string(mode)));
            if ~ismember(mode, {'manual', 'automatic'})
                error('NeuroPAL:ArtifactMode', 'Choose manual or automatic artifact removal.');
            end
            data = app.image_data;
            if isempty(data) || ~(isnumeric(data) || islogical(data)) || ~isreal(data) || ndims(data)>4
                error('NeuroPAL:ArtifactImage', ...
                    ['Open a NeuroPAL image volume before removing artifacts. This command edits the ' ...
                    'NeuroPAL image, not the Video Tracking recording.']);
            end
            if ~strcmp(app.VolumeDropDown.Value, 'Colormap')
                error('NeuroPAL:ArtifactView', ...
                    'Select the NeuroPAL image (Colormap) in Image Processing before removing artifacts. Video processing settings have been kept.');
            end
            prefs = app.image_prefs;
            if ~isstruct(prefs) || ~isscalar(prefs) || ~isfield(prefs, 'RGBW') || ...
                    ~isnumeric(prefs.RGBW) || ~isreal(prefs.RGBW) || ...
                    isempty(prefs.RGBW) || numel(prefs.RGBW)>4
                error('NeuroPAL:ArtifactChannels', 'Assign the image channels before removing artifacts.');
            end
            mapping = double(prefs.RGBW(:)');
            selected = mapping(~isnan(mapping));
            if isempty(selected) || any(~isfinite(selected) | selected<1 | ...
                    selected~=round(selected) | selected>size(data,4))
                error('NeuroPAL:ArtifactChannels', ...
                    'The image channel assignments are invalid. Choose available source channels and try again.');
            end
            rgb = [];
            if strcmp(mode, 'automatic')
                if numel(mapping)<3 || any(~isfinite(mapping(1:3))) || numel(unique(mapping(1:3)))~=3
                    error('NeuroPAL:ArtifactRGB', ...
                        'Automatic removal needs three distinct red, green and blue source channels. Use manual removal for one or two channels.');
                end
                rgb = mapping(1:3);
            end
            dims = size(data); dims(end+1:4) = 1;
            details = whos('data');
            working_bytes = 2*double(details.bytes);
            if strcmp(mode, 'automatic')
                % Include normalized RGB, connected-component masks and labels.
                working_bytes = working_bytes + prod(double(dims(1:3)))*64;
            end
            if working_bytes > 4*DataHandling.Helpers.npal_mat.materialization_limit_bytes()
                error('NeuroPAL:ArtifactMemory', ...
                    'Artifact removal exceeds the working-memory budget for this image. Crop or downsample the image first.');
            end
            context = struct('mode', mode, 'data', data, 'dims', dims, ...
                'channels', unique(selected, 'stable'), 'rgb', rgb, ...
                'prefs', prefs, 'file', app.image_file);
        end

        function checkContext(app, context)
            if ~isequaln(app.image_file, context.file) || ...
                    ~strcmp(app.VolumeDropDown.Value, 'Colormap') || ...
                    ~isequaln(app.image_prefs, context.prefs) || ~isequaln(app.image_data, context.data)
                error('NeuroPAL:ArtifactSourceChanged', ...
                    'The image or processing settings changed while the artifact selection was open. No pixels were changed; try again.');
            end
        end

        function mask = checkMask(mask, context)
            expected = context.dims(1:2);
            if strcmp(context.mode, 'automatic'), expected(3) = context.dims(3); end
            actual = size(mask); actual(end+1:numel(expected)) = 1;
            if ~(islogical(mask) || isnumeric(mask)) || ~isreal(mask) || ...
                    ~isequal(actual, expected) || any(~isfinite(mask(:)) | (mask(:)~=0 & mask(:)~=1))
                error('NeuroPAL:ArtifactMask', 'The artifact selection does not match the image. No pixels were changed.');
            end
            mask = logical(mask);
        end

        function publish(app, output, options)
            previous = struct('data', app.image_data, 'zscored', app.image_data_zscored, ...
                'neurons', app.image_neurons, 'id_file', app.id_file, ...
                'mode', app.VolumeDropDown.Value, 'flags', app.flags, 'selected', app.selected_neuron, ...
                'session', Program.ProcessingSession.get(app), ...
                'id_snapshot', getappdata(app.CELL_ID, 'manual_id_file_snapshot'));
            dirty_existed = isappdata(app.CELL_ID, 'proc_runtime_dirty');
            previous_dirty = [];
            if dirty_existed, previous_dirty = getappdata(app.CELL_ID, 'proc_runtime_dirty'); end
            try
                Program.ProcessingSession.checkpointPixels(app);
                app.image_neurons = Program.ProcessingSession.copyNeurons(previous.neurons);
                app.image_data = output;
                app.image_data_zscored = [];
                Program.ProcessingSession.stageIDs(app);
                setappdata(app.CELL_ID, 'proc_runtime_dirty', true);
                Program.Helpers.main_display_view_cache(app, []);
                Program.GUIHandling.clear_processing_preview_cache(app);
                Program.ProcessingSession.refreshColors(app);
                if isfield(options, 'RefreshFcn')
                    options.RefreshFcn();
                else
                    Program.Routines.ID.render();
                    Program.Routines.Processing.render();
                end
                Program.ArtifactRemoval.rebindSelection(app);
                Program.GUIHandling.update_processing_commit_state(app);
            catch ME
                app.image_data = previous.data;
                app.image_data_zscored = previous.zscored;
                app.image_neurons = previous.neurons;
                app.selected_neuron = previous.selected;
                app.id_file = previous.id_file;
                app.VolumeDropDown.Value = previous.mode;
                app.flags = previous.flags;
                if isempty(previous.session)
                    Program.ProcessingSession.clear(app);
                else
                    setappdata(app.CELL_ID, 'processing_session', previous.session);
                end
                if dirty_existed
                    setappdata(app.CELL_ID, 'proc_runtime_dirty', previous_dirty);
                elseif isappdata(app.CELL_ID, 'proc_runtime_dirty')
                    rmappdata(app.CELL_ID, 'proc_runtime_dirty');
                end
                Program.Helpers.main_display_view_cache(app, []);
                Program.GUIHandling.clear_processing_preview_cache(app);
                % Restore an already-painted preview as well as its source pixels.
                try
                    Program.Routines.ID.render();
                catch redraw_error
                    ME=addCause(ME,redraw_error);
                end
                try
                    Program.Routines.Processing.render();
                    Program.GUIHandling.update_processing_commit_state(app);
                catch redraw_error
                    ME=addCause(ME,redraw_error);
                end
                try
                    Program.ArtifactRemoval.rebindSelection(app);
                catch selection_error
                    ME=addCause(ME,selection_error);
                end
                if isempty(previous.id_snapshot)
                    if isappdata(app.CELL_ID, 'manual_id_file_snapshot')
                        rmappdata(app.CELL_ID, 'manual_id_file_snapshot');
                    end
                else
                    setappdata(app.CELL_ID, 'manual_id_file_snapshot', previous.id_snapshot);
                end
                rethrow(ME);
            end
        end

        function rebindSelection(app)
            index=app.selected_neuron;
            if ~isempty(index) && isscalar(index) && isfinite(index) && index==round(index) && ...
                    ~isempty(app.image_neurons) && index>=1 && index<=numel(app.image_neurons.neurons)
                % Keep the owned draft attached to the copied model and staged ID file.
                Program.GUI.ManualIDController.select(app,index);
            end
        end

        function ensureProcessing(app)
            snapshot=Program.ProcessingSession.get(app);
            if ~isempty(snapshot) && strcmp(snapshot.path,app.image_file)
                return;
            end
            reader_matches=false;
            if isa(app.proc_image,'matlab.io.MatFile')
                reader_matches=strcmp(app.proc_image.Properties.Source,app.image_file);
            end
            if isempty(snapshot) && reader_matches && Program.GUIHandling.processing_tab_rendered(app)
                return;
            end
            if Program.ProcessingSession.dirty(app)
                error('NeuroPAL:ArtifactPendingProcessing', ...
                    'Save or reset the pending Image Processing changes before removing artifacts from this NeuroPAL image.');
            end
            % Initialize this source before checkpointing its processing controls.
            tab=app.TabGroup.SelectedTab;
            cleanup=onCleanup(@() Program.ArtifactRemoval.restoreTab(app,tab));
            Program.Routines.Processing.load_file('image',app.image_file);
        end

        function restoreTab(app,tab)
            if isvalid(app) && ~isempty(tab) && isvalid(tab)
                app.TabGroup.SelectedTab=tab;
            end
        end
    end
end
