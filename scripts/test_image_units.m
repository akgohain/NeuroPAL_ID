function test_image_units(c)
%TEST_IMAGE_UNITS Check calibrated axes without changing image coordinates.
saved=struct('metadata',Tracking.ImageSettings.get(c),'spacing',c.Spacing.Value, ...
    'confirmed',c.Calibration.Value,'calibration_label',c.Calibration.Text,'mode',c.View.DisplayMode.Value);
cleanup=onCleanup(@() restore(c,saved));
c.View.Playback.stop(); c.Spacing.Value='0.4 0.8 1.5'; c.Calibration.Value=true;
control=getappdata(c.Grid,'image_units_control'); rows=c.Rows; candidates=c.Candidates;
for mode={'Slice','Slab','MIP'}
    c.View.DisplayMode.Value=mode{1}; c.render();
    ax=c.Axes; if strcmp(mode{1},'MIP'), ax=c.View.Projection; end
    img=getappdata(ax,'main_slice_image'); pixels=img.CData; x=img.XData; y=img.YData;
    marker=line(ax,[25 60],[30 50],'Tag','units_test_marker');
    marker_cleanup=onCleanup(@() delete(marker));
    for units={'µm','Pixels','µm'}
        control.Value=units{1}; Tracking.ImageUnits.change(c);
        assert(isequal(img.CData,pixels) && isequal(img.XData,x) && isequal(img.YData,y));
        assert(isequal(marker.XData,[25 60]) && isequal(marker.YData,[30 50]));
        if strcmp(units{1},'µm')
            assert(strcmp(ax.XLabel.String,'X (µm)') && strcmp(ax.YLabel.String,'Y (µm)'));
            x_labels=str2double(string(ax.XTickLabel)); y_labels=str2double(string(ax.YTickLabel));
            assert(max(abs(x_labels(:)-(ax.XTick(:)-1)*.4))<1e-9);
            assert(max(abs(y_labels(:)-(ax.YTick(:)-1)*.8))<1e-9);
            assert(abs(ax.DataAspectRatio(1)/ax.DataAspectRatio(2)-2)<1e-9);
        else
            assert(strcmp(ax.XLabel.String,'X (pixels)') && strcmp(ax.YLabel.String,'Y (pixels)'));
            assert(isequal(ax.DataAspectRatio,[1 1 1]));
        end
    end
    c.View.fitAxes(ax); assert(strcmp(ax.XLabel.String,'X (µm)'));
    clear marker_cleanup
end
session=c.Analysis.session(); assert(strcmp(session.image_settings.spatial_units,'µm'));
control.Value='Pixels'; Tracking.ImageUnits.change(c); c.Analysis.restoreSession(session);
assert(strcmp(control.Value,'µm'));
% Editing or clearing calibration must not leave stale physical labels.
c.Spacing.Value='invalid'; c.spacingChanged();
assert(strcmp(control.Value,'Pixels') && strcmp(c.Axes.XLabel.String,'X (pixels)'));
assert(isempty(Tracking.ImageUnits.spacing(c)));
c.Spacing.Value='0.4 0.8 1.5 trailing'; c.Calibration.Value=true;
assert(isempty(Tracking.ImageUnits.spacing(c)));
assert(isequal(c.Rows,rows) && isequal(c.Candidates,candidates));
fprintf('IMAGE_UNITS_COORDINATES_CALIBRATION_SESSION=PASS\n');
end

function restore(c,saved)
c.Spacing.Value=saved.spacing; c.Calibration.Value=saved.confirmed;
c.Calibration.Text=saved.calibration_label;
c.View.DisplayMode.Value=saved.mode; Tracking.ImageSettings.restore(c,saved.metadata); c.render();
end
