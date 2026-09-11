classdef MainDisplayTestApp < handle
    %MAINDISPLAYTESTAPP Minimal viewer state for display/cache contract tests.
    properties
        CELL_ID
        image_data = []
        image_view = []
        image_file = 'fixture-a.mat'
        image_gamma = ones(1, 6)
        image_prefs = struct('is_Z_flip', false)
        ZSlider = struct('Value', 1)
        RDropDown
        GDropDown
        BDropDown
        WDropDown
        DICDropDown
        GFPDropDown
        RCheckBox = struct('Value', true)
        GCheckBox = struct('Value', true)
        BCheckBox = struct('Value', true)
        WCheckBox = struct('Value', false)
        DICCheckBox = struct('Value', false)
        GFPCheckBox = struct('Value', false)
    end
    methods
        function app = MainDisplayTestApp()
            app.CELL_ID = figure('Visible', 'off', 'HandleVisibility', 'off');
            names = {'RDropDown', 'GDropDown', 'BDropDown', ...
                'WDropDown', 'DICDropDown', 'GFPDropDown'};
            items = {'1', '2', '3', '4', '5', '6'};
            for n = 1:numel(names)
                app.(names{n}) = struct('Items', {items}, 'Value', items{n});
            end
        end
        function delete(app)
            if ~isempty(app.CELL_ID) && isvalid(app.CELL_ID)
                delete(app.CELL_ID);
            end
        end
    end
end
