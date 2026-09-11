function volume = main_display_legacy_volume(app)
%MAIN_DISPLAY_LEGACY_VOLUME Bound stack materialization for legacy dialogs.
dims = [size(app.image_data, 1), size(app.image_data, 2), size(app.image_data, 3), 3];
% These dialogs can keep several double-precision copies while processing.
estimated_bytes = prod(double(dims)) * 8 * 4;
budget = DataHandling.Helpers.large_file.memory_budget_bytes();
if estimated_bytes > budget
    error('Program:Display:LegacyVolumeBudget', ...
        ['This legacy dialog needs a full rendered stack beyond the working-memory budget. ' ...
         'Use the Image Processing tab for this volume.']);
end
source = Program.Helpers.main_display_export_source(app);
if isempty(source)
    volume = [];
    return
end
volume = zeros(dims, 'single');
for z = 1:dims(3)
    volume(:, :, z, :) = source.read_slice(z);
end
end
