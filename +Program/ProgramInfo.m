classdef ProgramInfo
    %PROGRAMINFO Program information.
    
    % Program constants.
    properties (Constant, Access = public)
        name = 'NeuroPAL Auto ID'; % program name
        version = 1.8; % software version
        version_URL = 'https://raw.githubusercontent.com/amin-nejat/CELL_ID/master/version.info';
        %website_URL = 'http://hobertlab.org/neuropal/';
        website_URL = 'http://yeminilab.com/neuropal/';
        bug_URL = 'https://github.com/amin-nejat/CELL_ID/issues';

        % Dictionary of channel colors and their respective fluorophores.
        fluorophore_map = dictionary( ...
            'red', {{'neptune', 'nep', 'n2.5', 'n25'}}, ...
            'green', {{'cyofp1', 'cyofp', 'cyo'}}, ...
            'blue', {{'bfp'}}, ...
            'white', {{'rfp', 'tagrfp', 'tagrfp1'}}, ...
            'dic', {{'dic', 'dia', 'nomarski', 'phase', 'dic1', 'dic2'}}, ...
            'gfp', {{'gfp', 'gcamp'}});
    end
    
   % Public methods.
    methods (Static)
        function handle = window()
            %WINDOW Retrieve a persistent handle to the active window.
            %
            %   Output:
            %   - handle: The figure handle with the specified name, or
            %       empty if none is found.
        
            active=getappdata(groot,'neuropal_active_app');
            if ~isempty(active) && isvalid(active) && isgraphics(active.CELL_ID)
                handle=active.CELL_ID;
                return;
            end
            % Define a persistent variable that caches the figure handle across calls
            persistent window_handle


            % Check whether the persistent variable is uninitialized.
            is_uninitialized = isempty(window_handle);

            % Check whether the persistent variable references a delete
            % or otherwise invalid graphics object.
            is_invalid = any(~isgraphics(window_handle));
        
            % Check whether the persistent variable references a delete
            % or otherwise invalid graphics object.
            if is_uninitialized || is_invalid
                % If so, find the active window.
                window_handle = findall(groot, 'Name', 'NeuroPAL ID');
            end
            
            % Return the handle to the caller
            handle = window_handle;
        end

        function handle = app()
            %APP Retrieve a persistent handle to the running app instance.
            %
            %   Output:
            %   - handle: The handle to the running application instance
            %       (if it exists), or an empty value otherwise.
        
            active=getappdata(groot,'neuropal_active_app');
            if ~isempty(active) && isvalid(active) && isgraphics(active.CELL_ID)
                handle=active;
                return;
            end
            % Initiate a persistent reference.
            persistent app_handle

            % Check whether the persistent variable is uninitialized.
            is_uninitialized = any(isempty(app_handle));

            % Check whether the persistent variable references a delete
            % or otherwise invalid graphics object.
            is_invalid = any(isa(app_handle, "handle")) ...
                && any(~isvalid(app_handle));
        
            % If the reference is empty or invalid, try to find it.
            if  is_uninitialized || is_invalid               
                window_handle = Program.ProgramInfo.window();
                if ~isempty(window_handle) && isprop(window_handle, 'RunningAppInstance')
                    app_handle = window_handle.RunningAppInstance;
                else
                    app_handle = [];
                end
            end
        
            % Return the persistent variable.
            handle = app_handle;
        end

        function msg = getAboutMsg()
            %GETABOUTMSG Get the about message for display.
            msg = [];
        end
        
        function msg = getKeyboardShortcutsMsg()
            %GETKEYBOARDSHORTCUTSMSG Get the keyboard shortcuts message for
            %  display.
            msg = { ...
                'Manual ID entry'; ...
                'Type an ID to filter names. Up/Down selects a suggestion; Enter stages it.'; ...
                'Tab moves from the ID field to Assign without saving.'; ...
                'Click Assign, or press Enter/Space while Assign is focused, to save.'; ...
                'Escape closes suggestions. Typing or leaving the ID field does not save.'; ...
                'Use Neurons > Undo ID edit to undo a saved annotation.'; ...
                ''; ...
                'Image view (click the image first)'; ...
                'Click a marker to select it. Double-click the image to add a neuron.'; ...
                'Double-click or right-click a marker to delete it.'; ...
                'Left/Right: previous/next Z slice. Up/Down: zoom in/out.'; ...
                '0: color atlas. 1–6: red, green, blue, white, DIC and GFP display.'; ...
                'P: pan. R: reset view. H/J/K: cycle halves/thirds/quarters.'; ...
                'A: toggle Prefill prediction. I: toggle ID labels. B: toggle birth times.'; ...
                ''; ...
                'Video Tracking (click the image first)'; ...
                'Space: play/pause. Left/Right: previous/next frame.'; ...
                'Shift+Left/Right: move 10 frames. Home/End: first/last frame.'; ...
                ''; ...
                'Image and playback shortcuts are ignored while editing text or controls.'};
        end

        function msg = getInstructionsMsg()
            %GETINSTRUCTIONSMSG Describe the current annotation workflow.
            msg = { ...
                'Open an image with File > Open. Check Body, Sex, channel assignments and voxel spacing.'; ...
                ''; ...
                'Manual identification'; ...
                'Double-click the image to add a neuron, or click an existing marker or list row.'; ...
                'Type in ID and choose a suggestion. Click Assign to save it; typing alone does not assign.'; ...
                'Use an exact individual name to resolve L/R. An unresolved family can stay unresolved.'; ...
                'A trailing ? marks a tentative ID. Clear ID and Undo are available in the ID popup.'; ...
                'Human annotations save to the image''s companion _ID.mat. Keep the image and companion files together.'; ...
                'Analysis > Export neuron IDs creates a separate export. MAT preserves the full annotation history and evidence; CSV is a summary with a MAT companion.'; ...
                ''; ...
                'Automatic methods'; ...
                'Choose models and input channels with the gears beside Auto-detect and Auto-ID, then run the method.'; ...
                'Models require their installed assets and runtimes. Review detections and ID suggestions; predictions are not verified biological identities.'; ...
                'Prefill prediction only fills the editor. Assign is still required to save an ID.'; ...
                ''; ...
                'Calcium recordings'; ...
                'Open the recording in Video Tracking. Check Image settings, detect and accept reference centers, then run ZephIR.'; ...
                'Match additional reference frames to existing neuron IDs. Review tracks, extract activity and export activity plus tracks.'; ...
                'Save session preserves the tracking workspace. Activity must be extracted again after changing centers or measurement settings.'};
        end
        
        function latest_version = checkUpdates()
            %CHECKUPDATES Check the software for updates.
            
            % Initialize the version.
            import Program.*;
            
            % Get the latest version info.
            url = ProgramInfo.version_URL;
            str = urlread(url); % webread has a bug!
            
            % Can we connect?
            url_ver = splitlines(str);
            
            % Find the latest software version.
            ver_i = find(contains(url_ver, 'software'), 1);
            ver_str = url_ver{ver_i};
            equal_i = find(ver_str == '=', 1);
            latest_version = str2double(ver_str((equal_i+1):end));
        end
    end
end
