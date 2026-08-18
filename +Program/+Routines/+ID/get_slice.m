function get_slice(~, view, ~)
    %% Draw the neurons in this z-slice.

    app = Program.app;

    % Sanity check the Z slice value.
    z = Program.Helpers.gui_z_to_data_index(app.ZSlider.Value, size(app.image_data, 3), false);
    app.logEvent('Main',sprintf('Drawing slice %s...', string(z)), 0);
    app.ZSlider.Value = z;

    % Is there an image?
    if isempty(app.image_data)
        return;
    end

    % Flip the Z-axis.
    z_num = z;
    z = Program.Helpers.gui_z_to_data_index(z_num, size(app.image_data, 3), app.image_prefs.is_Z_flip);
    Program.Helpers.debug_event('IDSlice', ...
        'z_gui=%d z_data=%d is_Z_flip=%d z_center=%d', ...
        z_num, z, app.image_prefs.is_Z_flip, app.image_prefs.z_center);

    % Where are we in Z?
    background_color = [0.94,0.94,0.94];
    LD_color = [0,1,1]; % left or dorsal color
    RV_color = [1,0,1]; % right or ventral color
    z_center_thresh = 1; % center +/- 1 slice
    z_center = app.image_prefs.z_center;
    if z_num >= z_center - z_center_thresh && z_num <= z_center + z_center_thresh
        app.XYPanel.BackgroundColor = background_color;
        app.ZLeftLabel.BackgroundColor = background_color;
        app.ZRightLabel.BackgroundColor = background_color;
    elseif z_num < z_center - z_center_thresh
        app.XYPanel.BackgroundColor = LD_color;
        app.ZLeftLabel.BackgroundColor = LD_color;
        app.ZRightLabel.BackgroundColor = background_color;
    else % if z > z_center + z_center_thresh
        app.XYPanel.BackgroundColor = RV_color;
        app.ZLeftLabel.BackgroundColor = background_color;
        app.ZRightLabel.BackgroundColor = RV_color;
    end

    % Clear the contents of the axis to draw the new Z-slice.
    Program.Helpers.ensure_main_image_axes(app);
    ax = app.XY;
    cla(ax);
    % Create the slice at z for displaying in the axis.
    [xy, ~, z] = Program.Helpers.get_current_display_slice(app, 'main', view);
    Program.Helpers.debug_array_summary('IDSlice', 'xy_slice', xy);
    % Display the current slice in the XY axis.
    Program.Helpers.fill_axes_parent(ax);
    gui_image = image(xy, 'Parent', ax);
    Program.Helpers.configure_image_axes_ticks( ...
        ax, size(xy), app.image_um_scale(1:2), ...
        'XLim', [0, size(xy, 2)], ...
        'YLim', [0, size(xy, 1)]);
    Program.Helpers.fill_axes_parent(ax);
    hold(ax, 'on');
    local_draw_cellpose_mask_overlay(app, ax, z);
    local_draw_yolo_box_overlay(app, ax, z);

    if strcmp(app.TabGroup.SelectedTab.Title, 'Image Processing') & strcmp(app.VolumeDropDown.Value, 'Colormap')
        Program.Helpers.fill_axes_parent(app.proc_xyAxes);
        image(xy, 'Parent', app.proc_xyAxes);
        Program.Helpers.configure_image_axes_ticks( ...
            app.proc_xyAxes, size(xy), app.image_um_scale(1:2), ...
            'XLim', [1, size(xy, 2)], ...
            'YLim', [1, size(xy, 1)]);
        Program.Helpers.fill_axes_parent(app.proc_xyAxes);
    end

    % Add the AddNeuron function as mouse click listener.
    gui_image.ButtonDownFcn = {@app.ImageClicked};

    % Redraw the neurons in this z slice.
    if ~isempty(app.image_neurons) && ~isempty(app.image_neurons.neurons)

        % Which neurons belong in this z-slice?
        neuron_locations = app.image_neurons.get_positions();
        neuron_marker_colors = app.image_neurons.get_marker_colors();
        neuron_marker_sizes = app.image_neurons.get_marker_sizes();
        neuron_line_size = Program.GUIPreferences.instance().neuron_dot.line;
        [marker_size_scale, marker_line_scale] = ...
            Program.GUIPreferences.neuron_marker_display_scales();

        % Since z (which is found by MP) can be a continuous value
        % to find all the neurons in the current slice we find the
        % ones that lie in the interval [z-z_dot_view, z+z_dot_view]. Finally we
        % change the x and y dimension to fix the inconsistent
        % behavior of Matlab figures for scatter and image function.
        % Red centroid visibility should be independent of mask overlay toggles.
        z_dot_view = 1.5;
        current_z_indices = neuron_locations(:,3)>z-z_dot_view & neuron_locations(:,3)<z+z_dot_view;
        positions = neuron_locations(current_z_indices, 1:2);

        % Draw the neuron markers.
        neuron_marker_plot = scatter(ax, positions(:, 2), positions(:, 1), ...
            neuron_marker_sizes(current_z_indices) * marker_size_scale, ...
            neuron_marker_colors(current_z_indices, :), ...
            'filled', 'MarkerEdgeColor', app.neuron_marker.color.edge, ...
            'LineWidth', neuron_line_size * marker_line_scale);

        % Are we showing the neuron annotations?
        if app.show_labels

            % Get the labels.
            labels = app.image_neurons.get_annotations();
            labels = labels(current_z_indices);

            % Get the ON/OFF annotations.
            is_on = app.image_neurons.get_is_annotations_on();
            is_on = is_on(current_z_indices);

            % Get the confidences.
            confidences = app.image_neurons.get_annotation_confidences();
            confidences = confidences(current_z_indices);

            % Get the emphasized neurons.
            is_emphasized = app.image_neurons.get_is_emphasized();
            is_emphasized = is_emphasized(current_z_indices);

            % Remove empty labels.
            is_label = ~cellfun('isempty', labels);
            labels = labels(is_label);
            is_on = is_on(is_label);
            confidences = confidences(is_label);
            is_emphasized = is_emphasized(is_label);

            % Add ON/OFF & confidence to the labels.
            for i = 1:length(confidences)

                % Is the neuron ON/OFF.
                switch is_on(i)
                    case false
                        labels{i} = [labels{i} '-OFF'];
                    case true
                        labels{i} = [labels{i} '-ON'];
                end

                % Is the user uncertain about the ID?
                if confidences(i) <= 0.5
                    labels{i} = [labels{i} '?'];
                end

                % Is the neuron emphasized?
                if is_emphasized(i)
                    labels{i} = [labels{i} '!'];
                end
            end

            % Draw the labels.
            DrawImageLabels(app, positions(is_label,:), labels);
        end

        % Setup the mouse-click callback.
        neuron_marker_plot.ButtonDownFcn = {@app.NeuronClicked};
    end

    % Draw the color atlas.
    if app.ColorAtlasCheckBox.Value

        % Do we have the atlas info?
        if isempty(app.image_neurons.get_aligned_xyzRGBs())

            % Uncheck the atlas.
            app.ColorAtlasCheckBox.Value = false;

            % Warn the user.
            uialert(app.CELL_ID, ...
                'Please press "Auto-ID All" to create the neuron ID atlas!', ...
                'No Atlas', 'Icon', 'warning');

            % Draw the neuron ID atlas.
        else
            Methods.AutoId.instance().visualize(...
                app.image_neurons, app.worm, 'ax', app.XY, 'z', z);
        end
    end
end

function local_draw_cellpose_mask_overlay(app, ax, z_data)
if ~local_cellpose_overlay_enabled(app)
    return
end

mask_volume = local_get_cellpose_mask_volume(app);
if isempty(mask_volume)
    return
end

if z_data < 1 || z_data > size(mask_volume, 3)
    return
end

mask_slice_labels = mask_volume(:, :, z_data);
mask_slice = mask_slice_labels > 0;
if ~any(mask_slice(:))
    text(ax, 8, 14, sprintf('Cellpose mask empty at z=%d', z_data), ...
        'Color', [1, 1, 0], 'FontSize', 10, 'FontWeight', 'bold', ...
        'BackgroundColor', [0, 0, 0], 'Margin', 2, 'HitTest', 'off');
    return
end

overlay_color = cat(3, ...
    1.0 * ones(size(mask_slice)), ...
    zeros(size(mask_slice)), ...
    1.0 * ones(size(mask_slice)));
overlay_image = image(overlay_color, 'Parent', ax);
overlay_image.AlphaData = 0.14 * double(mask_slice);
overlay_image.HitTest = 'off';

boundary = local_mask_boundary(mask_slice);
if any(boundary(:))
    % Draw edges in image pixel space (1 cell wide). plot(...,'.') uses screen
    % points so outlines stay visually thick in uiaxes; image + AlphaData matches
    % the slice grid and stays thin when zoomed with the data.
    ny = size(mask_slice, 1);
    nx = size(mask_slice, 2);
    yellow_edge = zeros(ny, nx, 3);
    yellow_edge(:, :, 1) = double(boundary);
    yellow_edge(:, :, 2) = double(boundary);
    edge_im = image(ax, yellow_edge);
    edge_im.AlphaData = double(boundary);
    edge_im.HitTest = 'off';
end

end

function boundary = local_mask_boundary(mask_slice)
neighbor_count = conv2(double(mask_slice), ones(3), 'same');
boundary = mask_slice & (neighbor_count < 9);
end

function local_draw_yolo_box_overlay(app, ax, z_data)
if ~local_yolo_box_overlay_enabled(app)
    return
end

boxes = local_get_yolo_boxes_for_slice(app, z_data);
if isempty(boxes)
    return
end

for i = 1:size(boxes, 1)
    x1 = boxes(i, 1);
    y1 = boxes(i, 2);
    x2 = boxes(i, 3);
    y2 = boxes(i, 4);
    score = boxes(i, 5);
    if ~all(isfinite([x1, y1, x2, y2]))
        continue
    end
    width = max(1, x2 - x1);
    height = max(1, y2 - y1);
    rectangle(ax, 'Position', [x1, y1, width, height], ...
        'EdgeColor', [1, 0.85, 0], ...
        'LineWidth', 1.1, ...
        'LineStyle', '-', ...
        'HitTest', 'off');
    if isfinite(score)
        text(ax, x1, max(1, y1 - 2), sprintf('%.2f', score), ...
            'Color', [1, 0.85, 0], ...
            'FontSize', 8, ...
            'FontWeight', 'bold', ...
            'BackgroundColor', [0, 0, 0], ...
            'Margin', 1, ...
            'HitTest', 'off');
    end
end
end

function boxes = local_get_yolo_boxes_for_slice(app, z_data)
boxes = [];

summary_path = local_resolve_yolo_summary_path(app);
if isempty(summary_path) || ~isfile(summary_path)
    return
end

summary = local_get_yolo_summary(app, summary_path);
if isempty(summary) || ~isfield(summary, 'slices')
    return
end

slices = summary.slices;
if isempty(slices)
    return
end

slice_index = round(double(z_data));
slice_record = [];
if slice_index >= 1 && slice_index <= numel(slices)
    slice_record = slices(slice_index);
else
    for i = 1:numel(slices)
        candidate_z = local_yolo_slice_index(slices(i));
        if ~isnan(candidate_z) && round(candidate_z) == slice_index
            slice_record = slices(i);
            break
        end
    end
end

if isempty(slice_record) || ~isfield(slice_record, 'boxes_xyxy_conf')
    return
end

boxes = double(slice_record.boxes_xyxy_conf);
if isempty(boxes)
    return
end
if isvector(boxes)
    boxes = reshape(boxes, 1, []);
end
if size(boxes, 2) < 5
    boxes(:, 5) = NaN;
end
boxes = boxes(:, 1:5);
end

function summary = local_get_yolo_summary(app, summary_path)
summary = [];
cache_metadata_key = 'yolo_box_cache_metadata';
cache_data_key = 'yolo_box_cache_summary';

try
    file_info = dir(summary_path);
catch
    file_info = struct([]);
end
if numel(file_info) ~= 1
    return
end

metadata = struct('path', summary_path, ...
    'bytes', file_info.bytes, ...
    'datenum', file_info.datenum);

if isappdata(app.CELL_ID, cache_metadata_key) && isappdata(app.CELL_ID, cache_data_key)
    cached_metadata = getappdata(app.CELL_ID, cache_metadata_key);
    if isstruct(cached_metadata) && ...
            isfield(cached_metadata, 'path') && strcmp(cached_metadata.path, metadata.path) && ...
            isfield(cached_metadata, 'bytes') && cached_metadata.bytes == metadata.bytes && ...
            isfield(cached_metadata, 'datenum') && cached_metadata.datenum == metadata.datenum
        summary = getappdata(app.CELL_ID, cache_data_key);
        return
    end
end

try
    summary = jsondecode(fileread(summary_path));
catch
    summary = [];
    return
end

setappdata(app.CELL_ID, cache_metadata_key, metadata);
setappdata(app.CELL_ID, cache_data_key, summary);
end

function z_index = local_yolo_slice_index(slice_record)
z_index = NaN;
candidate_fields = {'z', 'z_index', 'slice', 'slice_index'};
for i = 1:numel(candidate_fields)
    field_name = candidate_fields{i};
    if isfield(slice_record, field_name)
        value = double(slice_record.(field_name));
        if isfinite(value)
            z_index = value;
            if z_index == floor(z_index)
                z_index = z_index + 1 * (z_index == 0);
            end
            return
        end
    end
end
end

function mask_volume = local_get_cellpose_mask_volume(app)
mask_volume = [];

mp_params = local_resolve_mp_params(app);
if isempty(mp_params)
    return
end
if ~isfield(mp_params, 'masks_mat_path') || isempty(mp_params.masks_mat_path)
    return
end

mask_path = char(string(mp_params.masks_mat_path));
if ~isfile(mask_path)
    return
end

cache_metadata_key = 'cellpose_mask_cache_metadata';
cache_data_key = 'cellpose_mask_cache_volume';

try
    file_info = dir(mask_path);
catch
    file_info = struct([]);
end

if numel(file_info) ~= 1
    return
end

cache_metadata = local_build_cellpose_mask_cache_metadata(app, mask_path, file_info, mp_params);

if isappdata(app.CELL_ID, cache_metadata_key) && isappdata(app.CELL_ID, cache_data_key)
    cached_metadata = getappdata(app.CELL_ID, cache_metadata_key);
    if local_is_cellpose_mask_cache_valid(cached_metadata, cache_metadata)
        mask_volume = getappdata(app.CELL_ID, cache_data_key);
        if ~isempty(mask_volume)
            return
        end
    end
end

mask_source = local_cellpose_mask_source(app, mp_params);
switch lower(mask_source)
    case "masks_3d"
        mask_source = "masks_3D";
    otherwise
        mask_source = "masks_stitched";
end

try
    payload = load(mask_path);
catch
    return
end

if isfield(payload, char(mask_source))
    raw_mask = payload.(char(mask_source));
elseif isfield(payload, 'masks_stitched')
    raw_mask = payload.masks_stitched;
elseif isfield(payload, 'masks_3D')
    raw_mask = payload.masks_3D;
else
    return
end

try
    mask_volume = local_align_mask_to_image(raw_mask, size(app.image_data, 1:3));
catch
    return
end

if isempty(mask_volume)
    return
end

setappdata(app.CELL_ID, cache_metadata_key, cache_metadata);
setappdata(app.CELL_ID, cache_data_key, mask_volume);
end

function mask_source = local_cellpose_mask_source(app, mp_params)
mask_source = "masks_stitched";
if isappdata(app.CELL_ID, 'cellpose_mask_overlay_source')
    mask_source = string(getappdata(app.CELL_ID, 'cellpose_mask_overlay_source'));
end
if isfield(mp_params, 'mask_source')
    stored_source = lower(char(string(mp_params.mask_source)));
    if ~isappdata(app.CELL_ID, 'cellpose_mask_overlay_source')
        mask_source = stored_source;
    end
end
mask_source = lower(char(mask_source));
if strcmp(mask_source, '3d') || strcmp(mask_source, 'masks_3d')
    mask_source = "masks_3D";
elseif strcmp(mask_source, 'stitched') || strcmp(mask_source, 'masks_stitched')
    mask_source = "masks_stitched";
else
    mask_source = "masks_stitched";
end
end

function cache_metadata = local_build_cellpose_mask_cache_metadata(app, mask_path, file_info, mp_params)
cache_metadata = struct( ...
    'path', mask_path, ...
    'mask_source', local_cellpose_mask_source(app, mp_params) ...
);

if isstruct(file_info) && ~isempty(file_info)
    if isfield(file_info, 'bytes')
        cache_metadata.bytes = file_info.bytes;
    end
    if isfield(file_info, 'datenum')
        cache_metadata.datenum = file_info.datenum;
    end
end
end

function tf = local_is_cellpose_mask_cache_valid(cached_metadata, current_metadata)
tf = false;

if isempty(cached_metadata) || isempty(current_metadata)
    return
end

if ~isfield(cached_metadata, 'path') || ...
        ~isfield(cached_metadata, 'mask_source') || ...
        ~isfield(current_metadata, 'path') || ...
        ~isfield(current_metadata, 'mask_source')
    return
end

if ~strcmp(cached_metadata.path, current_metadata.path) || ...
        ~strcmp(cached_metadata.mask_source, current_metadata.mask_source)
    return
end

has_current_metadata = isfield(current_metadata, 'bytes') && isfield(current_metadata, 'datenum');
has_cached_metadata = isfield(cached_metadata, 'bytes') && isfield(cached_metadata, 'datenum');
if xor(has_current_metadata, has_cached_metadata)
    return
end
if has_current_metadata && has_cached_metadata
    if cached_metadata.bytes ~= current_metadata.bytes || ...
            cached_metadata.datenum ~= current_metadata.datenum
        return
    end
end

tf = true;
end

function mp_params = local_resolve_mp_params(app)
mp_params = [];

if isprop(app, 'mp_params') && ~isempty(app.mp_params) && isstruct(app.mp_params)
    mp_params = app.mp_params;
end

needs_fallback = isempty(mp_params) || ...
    ~isfield(mp_params, 'masks_mat_path') || isempty(mp_params.masks_mat_path);
if ~needs_fallback
    return
end

if ~isprop(app, 'id_file') || isempty(app.id_file) || ~isfile(app.id_file)
    return
end

try
    id_payload = load(app.id_file, 'mp_params');
catch
    return
end

if isfield(id_payload, 'mp_params') && isstruct(id_payload.mp_params)
    mp_params = id_payload.mp_params;
end
end

function tf = local_cellpose_overlay_enabled(app)
key = 'show_cellpose_mask_overlay';

if isappdata(app.CELL_ID, key)
    tf = logical(getappdata(app.CELL_ID, key));
else
    tf = false;
    setappdata(app.CELL_ID, key, tf);
end
end

function tf = local_yolo_box_overlay_enabled(app)
key = 'show_yolo_box_overlay';

if isappdata(app.CELL_ID, key)
    tf = logical(getappdata(app.CELL_ID, key));
else
    tf = false;
    setappdata(app.CELL_ID, key, tf);
end
end

function summary_path = local_resolve_yolo_summary_path(app)
summary_path = '';
mp_params = local_resolve_mp_params(app);
if isstruct(mp_params) && isfield(mp_params, 'summary_path') && ~isempty(mp_params.summary_path)
    summary_path = char(string(mp_params.summary_path));
end
end

function aligned_mask = local_align_mask_to_image(mask_data, image_shape_xyz)
aligned_mask = [];
mask_data = squeeze(mask_data);
if ndims(mask_data) ~= 3
    return
end

mask_shape = size(mask_data);
if isequal(mask_shape, image_shape_xyz)
    aligned_mask = mask_data;
    return
end

all_perms = perms(1:3);
for i = 1:size(all_perms, 1)
    candidate = permute(mask_data, all_perms(i, :));
    if isequal(size(candidate), image_shape_xyz)
        aligned_mask = candidate;
        return
    end
end
end
