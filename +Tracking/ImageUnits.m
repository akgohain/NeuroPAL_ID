classdef ImageUnits
    %IMAGEUNITS Display calibrated distances while retaining pixel coordinates.
    methods (Static)
        function build(c,parent)
            control=uidropdown(parent,'Items',{'Pixels','µm'},'Value','Pixels', ...
                'Tooltip','Image axis units. µm uses voxel spacing from Image settings; the first voxel center is zero.', ...
                'ValueChangedFcn',@(~,~) Tracking.ImageUnits.change(c));
            setappdata(c.Grid,'image_units_control',control);
        end
        function change(c)
            control=getappdata(c.Grid,'image_units_control'); value=Tracking.ImageSettings.get(c);
            if strcmp(control.Value,'µm') && isempty(Tracking.ImageUnits.spacing(c))
                control.Value=value.spatial_units; c.View.openSettings();
                uialert(getappdata(c.Grid,'image_settings_window'), ...
                    'Enter positive X Y Z voxel spacings and confirm measured or assumed spacing, then choose µm.', ...
                    'Physical distance'); return;
            end
            value.spatial_units=control.Value; setappdata(c.Grid,'image_metadata',value);
            Tracking.ImageUnits.refresh(c);
        end
        function scale = spacing(c)
            scale=[];
            if isempty(c.Spacing) || ~isvalid(c.Spacing) || ~c.Calibration.Value, return; end
            values=str2double(split(strtrim(string(c.Spacing.Value))));
            if numel(values)==3 && all(isfinite(values) & values>0), scale=values(:)'; end
        end
        function refresh(c)
            value=Tracking.ImageSettings.get(c);
            if strcmp(value.spatial_units,'µm') && isempty(Tracking.ImageUnits.spacing(c))
                value.spatial_units='Pixels'; setappdata(c.Grid,'image_metadata',value);
            end
            control=getappdata(c.Grid,'image_units_control');
            if ~isempty(control), control.Value=value.spatial_units; end
            Tracking.ImageUnits.axis(c,c.Axes); Tracking.ImageUnits.axis(c,c.View.Projection);
        end
        function axis(c,ax)
            if isempty(ax) || ~isgraphics(ax), return; end
            value=Tracking.ImageSettings.get(c); scale=Tracking.ImageUnits.spacing(c);
            physical=strcmp(value.spatial_units,'µm') && ~isempty(scale);
            if ~physical, scale=[1 1 1]; end
            key={physical,scale,ax.XLim,ax.YLim};
            if isequaln(getappdata(ax,'image_units_key'),key), return; end
            if physical
                [ax.XTick,ax.XTickLabel]=Tracking.ImageUnits.ticks(ax.XLim,scale(1));
                [ax.YTick,ax.YTickLabel]=Tracking.ImageUnits.ticks(ax.YLim,scale(2));
                ax.XLabel.String='X (µm)'; ax.YLabel.String='Y (µm)';
            else
                x_step=max(1,round(c.Source.nx/5,-1)); y_step=max(1,round(c.Source.ny/5,-1));
                ax.XTick=unique([1 x_step:x_step:c.Source.nx]); ax.YTick=unique([1 y_step:y_step:c.Source.ny]);
                ax.XTickLabel=string(ax.XTick); ax.YTickLabel=string(ax.YTick);
                ax.XLabel.String='X (pixels)'; ax.YLabel.String='Y (pixels)';
            end
            ax.XMinorTick='off'; ax.YMinorTick='off'; ax.TickDir='out'; ax.Box='on';
            daspect(ax,[1/scale(1) 1/scale(2) 1]);
            setappdata(ax,'image_units_key',key);
        end
        function [positions,labels] = ticks(limits,scale)
            distances=max(0,(limits-1)*scale); span=diff(distances);
            base=10^floor(log10(max(realmin,span/5)));
            steps=[1 2 2.5 5 10]*base; step=steps(find(steps>=span/5,1));
            values=ceil(distances(1)/step)*step:step:distances(2);
            positions=1+values/scale; labels=compose('%.4g',values);
        end
    end
end
