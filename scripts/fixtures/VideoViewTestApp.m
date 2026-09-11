classdef VideoViewTestApp < handle
    %VIDEOVIEWTESTAPP Minimal source and controls for video-view tests.
    properties
        CELL_ID
        xyAxes
        video_info = struct()
        fallback_frame = []
        RSlider = struct('Value',1)
        GSlider = struct('Value',1)
        BSlider = struct('Value',1)
        tSlider = struct('Value',1,'Limits',[1 5])
        tEditField = struct('Value',1)
        hor_zSlider = struct('Value',1)
        OverlayFrameMIPCheckBox = struct('Value',false)
        OverlaylastIDdframeCheckBox_2 = struct('Value',false)
        full_refreshes = []
    end
    methods
        function app = VideoViewTestApp()
            app.CELL_ID = figure('Visible','off','HandleVisibility','off');
            app.xyAxes = axes(app.CELL_ID);
        end
        function frame = retrieve_frame(app,t)
            frame = app.fallback_frame(:,:,:,:,t);
        end
        function visual_composer(app,t)
            app.full_refreshes(end+1) = t;
        end
        function ImageClicked(varargin)
        end
        function delete(app)
            Program.GUI.clear_zephir_time_slider(app);
            if ~isempty(app.CELL_ID) && isvalid(app.CELL_ID), delete(app.CELL_ID); end
        end
    end
end
