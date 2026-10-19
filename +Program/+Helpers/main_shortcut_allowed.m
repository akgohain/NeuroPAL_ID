function allowed = main_shortcut_allowed(app, focused)
%MAIN_SHORTCUT_ALLOWED Keep image shortcuts out of text entry and unrelated tabs.
allowed = false;
try
    selected = app.TabGroup.SelectedTab;
    if isequal(selected, app.NeuroPALIDTab)
        if isempty(app.image_data), return; end
    elseif isequal(selected, app.ImageProcessingTab)
        switch app.VolumeDropDown.Value
            case 'Colormap'
                % The processing keyboard callback reads this MAT volume's dimensions.
                if ~isa(app.proc_image, 'matlab.io.MatFile'), return; end
                dims = size(app.proc_image, 'data');
                if numel(dims) < 2 || any(dims < 1), return; end
            case 'Video'
                if ~Program.GUIHandling.processing_video_available(app), return; end
            otherwise
                return;
        end
    else
        % Video playback owns WindowKeyPressFcn for its own frame shortcuts.
        return;
    end

    if nargin < 2, focused = app.CELL_ID.CurrentObject; end
    if isobject(app) && isprop(app, 'IDEditField')
        ui = getappdata(app.IDEditField, 'manual_id_ui');
        if ~isempty(ui) && (Program.GUI.ManualIDController.inside(focused, ui.panel) || ...
                isequal(focused, app.UserIDButton))
            return;
        end
    end
    if isa(focused, 'matlab.ui.control.EditField') || ...
            isa(focused, 'matlab.ui.control.NumericEditField') || ...
            isa(focused, 'matlab.ui.control.TextArea') || ...
            isa(focused, 'matlab.ui.control.Spinner') || ...
            isa(focused, 'matlab.ui.control.DropDown')
        return;
    end
    allowed = true;
catch
    % A closing app or an incompletely loaded processing source is not navigable.
end
end
