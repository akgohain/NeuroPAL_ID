function data = legacy_detection_volume(app, matching_pursuit)
%LEGACY_DETECTION_VOLUME Prepare legacy detector input within the memory budget.
channels = app.image_prefs.RGBW;
channels = channels(~isnan(channels));
if isempty(app.image_data) || isempty(channels) || ...
        any(channels < 1 | channels > size(app.image_data, 4) | channels ~= round(channels))
    error('Program:Detection:Channels', 'Assign valid image channels before running detection.');
end
values = prod(double(size(app.image_data, 1:3))) * numel(channels);
if values * 8 * 4 > DataHandling.Helpers.large_file.memory_budget_bytes()
    error('Program:Detection:LegacyVolumeBudget', ...
        ['This legacy detector exceeds the working-memory budget for this volume. ' ...
         'Crop or downsample in Image Processing, or select a streamed detector such as MoE.']);
end
data = app.image_data(:, :, :, channels);
if any(~isfinite(data), 'all')
    error('Program:Detection:Nonfinite', 'The legacy detector requires finite image intensities.');
end
if all(max(data, [], [1 2 3]) == min(data, [], [1 2 3]), 'all')
    error('Program:Detection:NoSignal', 'The selected channels contain no varying signal.');
end
if ~matching_pursuit
    data = Methods.Preprocess.zscore_frame(data);
end
end
