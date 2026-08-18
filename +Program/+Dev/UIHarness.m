classdef UIHarness
    %UIHARNESS Deterministic screenshot and layout audit support.
    %
    % The harness exercises the real App Designer application. It captures
    % each top-level workflow tab at fixed viewport sizes and writes both
    % screenshots and machine-readable component geometry. The artifacts
    % are intended for visual inspection and regression comparison.

    methods (Static)
        function report = run(varargin)
            parser = inputParser;
            parser.FunctionName = 'Program.Dev.UIHarness.run';
            addParameter(parser, 'OutputDir', '', @(value) ischar(value) || isstring(value));
            addParameter(parser, 'Fixture', '', @(value) ischar(value) || isstring(value));
            addParameter(parser, 'VideoFixture', '', @(value) ischar(value) || isstring(value));
            addParameter(parser, 'Viewports', [1200 760; 1400 880], ...
                @(value) isnumeric(value) && size(value, 2) == 2);
            addParameter(parser, 'KeepOpen', false, @(value) islogical(value) && isscalar(value));
            addParameter(parser, 'FailOnErrors', true, @(value) islogical(value) && isscalar(value));
            parse(parser, varargin{:});

            output_dir = char(string(parser.Results.OutputDir));
            if isempty(output_dir)
                output_dir = fullfile(pwd, '.ui_artifacts', ...
                    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
            end
            if exist(output_dir, 'dir') ~= 7
                mkdir(output_dir);
            end

            fixture = char(string(parser.Results.Fixture));
            if ~isempty(fixture) && exist(fixture, 'file') ~= 2
                error('NeuroPAL:UIHarness:MissingFixture', ...
                    'UI fixture does not exist: %s', fixture);
            end
            video_fixture = char(string(parser.Results.VideoFixture));
            if ~isempty(video_fixture) && exist(video_fixture, 'file') ~= 2
                error('NeuroPAL:UIHarness:MissingVideoFixture', ...
                    'UI video fixture does not exist: %s', video_fixture);
            end

            app = visualize_light;
            fprintf('UI harness: application ready\n');
            assignin('base', 'NEUROPAL_DEV_APP', app);
            cleanup = onCleanup(@() Program.Dev.UIHarness.cleanup_app( ...
                app, parser.Results.KeepOpen));

            figure_handle = app.CELL_ID;
            if ~strcmpi(char(string(figure_handle.WindowState)), 'normal')
                figure_handle.WindowState = 'normal';
            end
            drawnow;

            report = struct();
            report.generated_at = char(datetime('now', 'TimeZone', 'local', ...
                'Format', 'yyyy-MM-dd HH:mm:ss Z'));
            report.matlab_version = version;
            report.fixture = fixture;
            report.video_fixture = video_fixture;
            report.output_dir = output_dir;
            report.viewports = parser.Results.Viewports;
            report.scenarios = struct([]);

            unloaded = Program.Dev.UIHarness.capture_scenario( ...
                app, output_dir, 'unloaded', parser.Results.Viewports);
            report.scenarios = unloaded;

            if ~isempty(fixture)
                Program.Routines.open(fixture);
                drawnow;
                loaded = Program.Dev.UIHarness.capture_scenario( ...
                    app, output_dir, 'loaded', parser.Results.Viewports);
                report.scenarios(end + 1) = loaded;
            end

            if ~isempty(video_fixture)
                fprintf('UI harness: loading video fixture %s\n', video_fixture);
                Program.Routines.Videos.load(video_fixture);
                fprintf('UI harness: video fixture ready\n');
                drawnow;
                video_loaded = Program.Dev.UIHarness.capture_scenario( ...
                    app, output_dir, 'video-loaded', parser.Results.Viewports);
                report.scenarios(end + 1) = video_loaded;
            end

            report.summary = Program.Dev.UIHarness.summarize(report.scenarios);
            report_path = fullfile(output_dir, 'ui-audit.json');
            fid = fopen(report_path, 'w');
            if fid < 0
                error('NeuroPAL:UIHarness:ReportWriteFailed', ...
                    'Cannot write UI report: %s', report_path);
            end
            file_cleanup = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(report, PrettyPrint=true), 'char');
            clear file_cleanup;

            Program.Dev.UIHarness.write_summary(output_dir, report);
            fprintf('NeuroPAL UI audit: %s\n', report_path);
            fprintf('  snapshots: %d\n', report.summary.snapshot_count);
            fprintf('  errors: %d\n', report.summary.error_count);
            fprintf('  warnings: %d\n', report.summary.warning_count);
            clear cleanup;
            Program.Dev.UIHarness.cleanup_app(app, parser.Results.KeepOpen);
            if parser.Results.FailOnErrors && report.summary.error_count > 0
                error('NeuroPAL:UIHarness:LayoutErrors', ...
                    'UI audit found %d structural layout errors. See %s.', ...
                    report.summary.error_count, report_path);
            end
        end
    end

    methods (Static, Access = private)
        function scenario = capture_scenario(app, output_dir, scenario_name, viewports)
            scenario = struct();
            scenario.name = scenario_name;
            scenario.snapshots = struct([]);

            figure_handle = app.CELL_ID;
            original_position = figure_handle.Position;
            original_tab = app.TabGroup.SelectedTab;
            restore = onCleanup(@() Program.Dev.UIHarness.restore_view( ...
                figure_handle, original_position, app.TabGroup, original_tab));

            tabs = flip(app.TabGroup.Children(:));
            for viewport_index = 1:size(viewports, 1)
                requested_size = viewports(viewport_index, :);
                figure_handle.Position(3:4) = requested_size;
                drawnow;

                for tab_index = 1:numel(tabs)
                    tab = tabs(tab_index);
                    app.TabGroup.SelectedTab = tab;
                    drawnow;
                    Program.Dev.UIHarness.prepare_tab_state(app, tab);
                    pause(0.05);
                    snapshot = Program.Dev.UIHarness.capture_snapshot( ...
                        app, output_dir, scenario_name, tab, requested_size, '');
                    scenario.snapshots = Program.Dev.UIHarness.append_snapshot( ...
                        scenario.snapshots, snapshot);
                end

                if strcmpi(scenario_name, 'video-loaded')
                    variants = Program.Dev.UIHarness.capture_tracking_backend_variants( ...
                        app, output_dir, scenario_name, requested_size);
                    for variant_index = 1:numel(variants)
                        scenario.snapshots = Program.Dev.UIHarness.append_snapshot( ...
                            scenario.snapshots, variants(variant_index));
                    end
                end

                % Exercise and preserve the taller processing-sidebar state.
                % This catches scroll/overflow defects hidden by the compact
                % default without making a person click through the app.
                if strcmpi(scenario_name, 'loaded') && ...
                        strcmpi(char(string(app.ImageProcessingTab.Tag)), 'rendered')
                    app.TabGroup.SelectedTab = app.ImageProcessingTab;
                    Program.GUIHandling.handle_processing_advanced_toggle(app);
                    drawnow;
                    snapshot = Program.Dev.UIHarness.capture_snapshot( ...
                        app, output_dir, scenario_name, app.ImageProcessingTab, ...
                        requested_size, 'advanced-expanded');
                    scenario.snapshots = Program.Dev.UIHarness.append_snapshot( ...
                        scenario.snapshots, snapshot);
                    Program.GUIHandling.handle_processing_advanced_toggle(app);
                    drawnow;

                    setappdata(app.CELL_ID, 'proc_runtime_dirty', true);
                    Program.GUIHandling.update_processing_commit_state(app);
                    snapshot = Program.Dev.UIHarness.capture_snapshot( ...
                        app, output_dir, scenario_name, app.ImageProcessingTab, ...
                        requested_size, 'unsaved-preview');
                    scenario.snapshots = Program.Dev.UIHarness.append_snapshot( ...
                        scenario.snapshots, snapshot);
                    rmappdata(app.CELL_ID, 'proc_runtime_dirty');
                    Program.GUIHandling.update_processing_commit_state(app);
                end

                if strcmpi(scenario_name, 'unloaded') && ...
                        isprop(app, 'EnabledebugmenuCheckBox')
                    app.TabGroup.SelectedTab = app.LogTab;
                    app.EnabledebugmenuCheckBox.Value = true;
                    Program.GUIHandling.update_log_debug_visibility(app, true);
                    drawnow;
                    snapshot = Program.Dev.UIHarness.capture_snapshot( ...
                        app, output_dir, scenario_name, app.LogTab, ...
                        requested_size, 'debug-enabled');
                    scenario.snapshots = Program.Dev.UIHarness.append_snapshot( ...
                        scenario.snapshots, snapshot);
                    app.EnabledebugmenuCheckBox.Value = false;
                    Program.GUIHandling.update_log_debug_visibility(app, false);
                    drawnow;
                end
            end
            clear restore;
        end

        function snapshots = capture_tracking_backend_variants( ...
                app, output_dir, scenario_name, requested_size)
            snapshots = struct([]);
            selector = findobj(app.VideoTrackingTab, 'Tag', 'tracking-backend-dropdown');
            if isempty(selector) || ~isvalid(selector(1)) || ...
                    isempty(app.DefaultTabGroup) || ~isvalid(app.DefaultTabGroup) || ...
                    isempty(app.CreditTab) || ~isvalid(app.CreditTab)
                return
            end
            selector = selector(1);
            original_backend = char(string(selector.Value));
            original_workflow_tab = app.DefaultTabGroup.SelectedTab;
            restore = onCleanup(@() Program.Dev.UIHarness.restore_tracking_variant( ...
                app, selector, original_backend, original_workflow_tab));

            app.TabGroup.SelectedTab = app.VideoTrackingTab;
            app.DefaultTabGroup.SelectedTab = app.CreditTab;
            backend_ids = {'zephir', 'ultrack'};
            for index = 1:numel(backend_ids)
                backend_id = backend_ids{index};
                selector.Value = backend_id;
                setappdata(app.CELL_ID, 'tracking_backend', backend_id);
                Program.GUI.update_zephir_video_tab(app);
                drawnow;
                snapshot = Program.Dev.UIHarness.capture_snapshot( ...
                    app, output_dir, scenario_name, app.VideoTrackingTab, ...
                    requested_size, [backend_id, '-run']);
                snapshots = Program.Dev.UIHarness.append_snapshot(snapshots, snapshot);
            end
            clear restore
        end

        function restore_tracking_variant(app, selector, backend, workflow_tab)
            try
                if ~isempty(selector) && isvalid(selector)
                    selector.Value = backend;
                end
                if ~isempty(app) && isvalid(app) && ~isempty(app.CELL_ID) && isvalid(app.CELL_ID)
                    setappdata(app.CELL_ID, 'tracking_backend', backend);
                    if ~isempty(workflow_tab) && isvalid(workflow_tab)
                        app.DefaultTabGroup.SelectedTab = workflow_tab;
                    end
                    Program.GUI.update_zephir_video_tab(app);
                end
                drawnow;
            catch
            end
        end

        function snapshot = capture_snapshot(app, output_dir, scenario_name, ...
                tab, requested_size, variant)
            figure_handle = app.CELL_ID;
            tab_name = Program.Dev.UIHarness.safe_name(tab.Title);
            viewport_name = sprintf('%dx%d', requested_size(1), requested_size(2));
            if isempty(variant)
                base_name = sprintf('%s__%s__%s', ...
                    scenario_name, tab_name, viewport_name);
            else
                base_name = sprintf('%s__%s__%s__%s', ...
                    scenario_name, tab_name, ...
                    Program.Dev.UIHarness.safe_name(variant), viewport_name);
            end
            image_path = fullfile(output_dir, [base_name '.png']);
            exportapp(figure_handle, image_path);

            components = Program.Dev.UIHarness.component_manifest(app);
            issues = Program.Dev.UIHarness.audit_components(components);
            render_issues = Program.Dev.UIHarness.audit_rendered_images( ...
                app, scenario_name, tab);
            issues = [issues, render_issues];
            manifest_path = fullfile(output_dir, [base_name '.json']);
            Program.Dev.UIHarness.write_json(manifest_path, struct( ...
                'scenario', scenario_name, ...
                'variant', variant, ...
                'tab', char(string(tab.Title)), ...
                'requested_viewport', requested_size, ...
                'actual_figure_position', figure_handle.Position, ...
                'components', components, ...
                'issues', issues));

            snapshot = struct();
            snapshot.tab = char(string(tab.Title));
            snapshot.variant = variant;
            snapshot.viewport = requested_size;
            snapshot.actual_figure_position = figure_handle.Position;
            snapshot.image = image_path;
            snapshot.manifest = manifest_path;
            snapshot.issues = issues;
        end

        function snapshots = append_snapshot(snapshots, snapshot)
            if isempty(snapshots)
                snapshots = snapshot;
            else
                snapshots(end + 1) = snapshot;
            end
        end

        function components = component_manifest(app)
            property_names = properties(app);
            components = struct([]);

            for property_index = 1:numel(property_names)
                property_name = property_names{property_index};
                try
                    value = app.(property_name);
                    if ~isscalar(value) || ~isobject(value) || ~isvalid(value) || ...
                            ~isprop(value, 'Parent') || ~isprop(value, 'Position')
                        continue;
                    end
                catch
                    % Non-component app properties are expected here.
                    continue;
                end
                component = value;
                item = struct();
                item.name = property_name;
                item.class = class(component);
                item.parent = Program.Dev.UIHarness.parent_name(component.Parent);
                item.parent_scrollable = Program.Dev.UIHarness.is_scrollable(component.Parent);
                item.visible = Program.Dev.UIHarness.property_text(component, 'Visible');
                item.effective_visible = Program.Dev.UIHarness.is_effectively_visible(component);
                item.enabled = Program.Dev.UIHarness.property_text(component, 'Enable');
                item.tag = Program.Dev.UIHarness.property_text(component, 'Tag');
                item.text = Program.Dev.UIHarness.component_text(component);
                if item.effective_visible
                    item.position = Program.Dev.UIHarness.pixel_position(component, false);
                    item.absolute_position = Program.Dev.UIHarness.pixel_position(component, true);
                    item.parent_size = Program.Dev.UIHarness.parent_size(component.Parent);
                else
                    item.position = [];
                    item.absolute_position = [];
                    item.parent_size = [];
                end
                if isempty(components)
                    components = item;
                else
                    components(end + 1) = item; %#ok<AGROW>
                end
            end
        end

        function issues = audit_components(components)
            issues = struct('severity', {}, 'rule', {}, 'component', {}, 'message', {});
            % Slider thumbs and vertically centered labels can extend a few
            % pixels outside their grid cell without being visually clipped.
            tolerance = 8;

            for component_index = 1:numel(components)
                component = components(component_index);
                if ~component.effective_visible || numel(component.position) ~= 4 || ...
                        contains(component.class, 'Menu')
                    continue;
                end
                position = component.position;
                if position(3) <= 0 || position(4) <= 0
                    issues(end + 1) = Program.Dev.UIHarness.issue( ...
                        'warning', 'collapsed_visible_component', component.name, ...
                        sprintf('Visible component has size %.1f x %.1f.', ...
                        position(3), position(4))); %#ok<AGROW>
                    continue;
                end

                parent_size = component.parent_size;
                % UIAxes pixel bounds include tick labels and axis titles, so
                % getpixelposition can legitimately extend beyond the grid
                % cell even when the plotted content is fully visible.
                audits_parent_bounds = ~contains(component.class, 'UIAxes');
                if audits_parent_bounds && ~component.parent_scrollable && ...
                        numel(parent_size) == 2 && all(parent_size > 0)
                    overflow = [-position(1), -position(2), ...
                        position(1) + position(3) - parent_size(1), ...
                        position(2) + position(4) - parent_size(2)];
                    if any(overflow > tolerance)
                        issues(end + 1) = Program.Dev.UIHarness.issue( ...
                            'warning', 'outside_parent', component.name, ...
                            sprintf('Bounds exceed parent by [L %.1f B %.1f R %.1f T %.1f] px.', ...
                            max(0, overflow(1)), max(0, overflow(2)), ...
                            max(0, overflow(3)), max(0, overflow(4)))); %#ok<AGROW>
                    end
                end

                if ~isempty(component.text) && Program.Dev.UIHarness.is_text_control(component.class)
                    longest_line = max(strlength(splitlines(string(component.text))));
                    estimated_width = 7 * double(longest_line) + 12;
                    clipping_ratio = 0.50;
                    if longest_line >= 16
                        clipping_ratio = 0.75;
                    end
                    if position(3) < clipping_ratio * estimated_width
                        issues(end + 1) = Program.Dev.UIHarness.issue( ...
                            'warning', 'probable_text_clipping', component.name, ...
                            sprintf('Width %.1f px is small for text "%s".', ...
                            position(3), Program.Dev.UIHarness.ellipsize(component.text))); %#ok<AGROW>
                    end
                end
            end
        end

        function issues = audit_rendered_images(app, scenario_name, tab)
            issues = struct('severity', {}, 'rule', {}, 'component', {}, 'message', {});
            if strcmpi(scenario_name, 'unloaded') || ...
                    ~strcmpi(char(string(tab.Title)), 'NeuroPAL ID') || ...
                    isempty(app.image_data) || isempty(app.XY) || ~isvalid(app.XY)
                return;
            end

            expected_size = double(size(app.image_data, [1, 2]));
            image_handles = findobj(app.XY, 'Type', 'Image');
            has_image_slice = false;
            for image_index = 1:numel(image_handles)
                try
                    cdata = image_handles(image_index).CData;
                    cdata_size = size(cdata);
                    if numel(cdata_size) >= 2 && ...
                            isequal(double(cdata_size(1:2)), expected_size)
                        has_image_slice = true;
                        break;
                    end
                catch
                end
            end
            if ~has_image_slice
                issues(end + 1) = Program.Dev.UIHarness.issue( ...
                    'error', 'missing_main_image_slice', 'XY', ...
                    sprintf(['Loaded NeuroPAL view has no rendered image matching ' ...
                    'the expected %d x %d slice.'], expected_size(1), expected_size(2)));
            end
        end

        function summary = summarize(scenarios)
            summary = struct('snapshot_count', 0, 'error_count', 0, 'warning_count', 0);
            for scenario_index = 1:numel(scenarios)
                snapshots = scenarios(scenario_index).snapshots;
                summary.snapshot_count = summary.snapshot_count + numel(snapshots);
                for snapshot_index = 1:numel(snapshots)
                    issues = snapshots(snapshot_index).issues;
                    if isempty(issues)
                        continue;
                    end
                    severities = string({issues.severity});
                    summary.error_count = summary.error_count + nnz(severities == "error");
                    summary.warning_count = summary.warning_count + nnz(severities == "warning");
                end
            end
        end

        function prepare_tab_state(app, tab)
            if tab ~= app.ImageProcessingTab || ...
                    ~strcmpi(char(string(app.ImageProcessingTab.Tag)), 'raw') || ...
                    isempty(app.image_file)
                return;
            end

            setappdata(app.CELL_ID, 'proc_skip_crop_recommendation', true);
            cleanup = onCleanup(@() Program.Dev.UIHarness.clear_appdata( ...
                app.CELL_ID, 'proc_skip_crop_recommendation'));
            Program.Routines.Processing.load_file('image', app.image_file);
            drawnow;
            clear cleanup;
        end

        function clear_appdata(handle, key)
            if ~isempty(handle) && isvalid(handle) && isappdata(handle, key)
                rmappdata(handle, key);
            end
        end

        function write_summary(output_dir, report)
            summary_path = fullfile(output_dir, 'README.txt');
            fid = fopen(summary_path, 'w');
            if fid < 0
                return;
            end
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, 'NeuroPAL UI audit\n');
            fprintf(fid, 'Generated: %s\n', report.generated_at);
            fprintf(fid, 'Fixture: %s\n', report.fixture);
            fprintf(fid, 'Video fixture: %s\n', report.video_fixture);
            fprintf(fid, 'Snapshots: %d\n', report.summary.snapshot_count);
            fprintf(fid, 'Layout errors: %d\n', report.summary.error_count);
            fprintf(fid, 'Layout warnings: %d\n', report.summary.warning_count);
            fprintf(fid, '\nInspect PNG files directly. JSON sidecars contain component bounds and diagnostics.\n');
            clear cleanup;
        end

        function write_json(path, value)
            fid = fopen(path, 'w');
            if fid < 0
                error('NeuroPAL:UIHarness:ManifestWriteFailed', ...
                    'Cannot write UI manifest: %s', path);
            end
            cleanup = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(value, PrettyPrint=true), 'char');
            clear cleanup;
        end

        function tf = is_effectively_visible(component)
            tf = true;
            current = component;
            while ~isempty(current) && isobject(current) && isvalid(current)
                if isprop(current, 'Visible') && strcmpi(char(string(current.Visible)), 'off')
                    tf = false;
                    return;
                end
                if isa(current, 'matlab.ui.container.Tab')
                    tab_group = current.Parent;
                    if isprop(tab_group, 'SelectedTab') && tab_group.SelectedTab ~= current
                        tf = false;
                        return;
                    end
                end
                if ~isprop(current, 'Parent')
                    break;
                end
                current = current.Parent;
            end
        end

        function position = pixel_position(component, recursive)
            position = [];
            try
                position = double(getpixelposition(component, recursive));
            catch
                try
                    position = double(component.Position);
                catch
                end
            end
        end

        function size_value = parent_size(parent)
            size_value = [];
            if isempty(parent) || ~isobject(parent) || ~isvalid(parent)
                return;
            end
            try
                position = getpixelposition(parent, false);
                size_value = double(position(3:4));
            catch
                try
                    position = parent.Position;
                    size_value = double(position(3:4));
                catch
                end
            end
        end

        function value = property_text(component, property_name)
            value = '';
            try
                if isprop(component, property_name)
                    value = char(string(component.(property_name)));
                end
            catch
            end
        end

        function value = component_text(component)
            value = '';
            candidates = {'Text', 'Title', 'Placeholder'};
            for candidate_index = 1:numel(candidates)
                candidate = candidates{candidate_index};
                try
                    if isprop(component, candidate) && ~isempty(component.(candidate))
                        raw = string(component.(candidate));
                        value = char(join(raw(:), ' | '));
                        return;
                    end
                catch
                end
            end
        end

        function name = parent_name(parent)
            if isempty(parent)
                name = '';
                return;
            end
            name = class(parent);
            tag = Program.Dev.UIHarness.property_text(parent, 'Tag');
            if ~isempty(tag)
                name = sprintf('%s#%s', name, tag);
            end
        end

        function tf = is_scrollable(component)
            tf = false;
            try
                tf = isprop(component, 'Scrollable') && ...
                    strcmpi(char(string(component.Scrollable)), 'on');
            catch
            end
        end

        function value = safe_name(value)
            value = lower(char(string(value)));
            value = regexprep(value, '[^a-z0-9]+', '-');
            value = regexprep(value, '(^-|-$)', '');
            if isempty(value)
                value = 'untitled';
            end
        end

        function tf = is_text_control(class_name)
            tf = contains(class_name, {'Label', 'Button', 'CheckBox', ...
                'RadioButton', 'Switch'});
        end

        function value = ellipsize(value)
            value = char(string(value));
            if strlength(string(value)) > 48
                value = [value(1:45) '...'];
            end
        end

        function value = issue(severity, rule, component, message)
            value = struct('severity', severity, 'rule', rule, ...
                'component', component, 'message', message);
        end

        function restore_view(figure_handle, position, tab_group, selected_tab)
            try
                if isvalid(figure_handle)
                    figure_handle.Position = position;
                end
                if isvalid(tab_group) && isvalid(selected_tab)
                    tab_group.SelectedTab = selected_tab;
                end
                drawnow;
            catch
            end
        end

        function cleanup_app(app, keep_open)
            if keep_open
                assignin('base', 'NEUROPAL_DEV_APP', app);
                return;
            end
            try
                if isvalid(app)
                    delete(app);
                end
            catch
            end
            try
                evalin('base', 'clear NEUROPAL_DEV_APP');
            catch
            end
        end
    end
end
