classdef histograms
    
    properties (Constant)
        handles = dictionary( ...
            'panels', {"%s_hist_panel"}, ...
            'labels', {"%s_Label"}, ...
            'axes', {"%s_hist_ax"});

        prefixes = {'tl', 'tm', 'tr', 'bl', 'bm', 'br'};
    end
    
    methods (Static)
        function reset(pfx)
            if nargin == 0
                prefixes = Program.Handlers.histograms.prefixes;

                for n=1:length(prefixes)
                    Program.Handlers.histograms.reset(prefixes{n});
                end

                return
            end

            component = Program.Routines.GUI.get_component('panels', pfx);
            component.Visible = 'off';
            cla(Program.Routines.GUI.get_component('axes', pfx))
        end
        
        function draw()
            app = Program.app;
            raw = Program.Handlers.histograms.get_source_array(app);
            state = Program.Handlers.channels.processing_state(app);
            rows = state.rows([state.rows.source_idx] > 0);

            Program.Handlers.histograms.reset();
            rheight = app.ProcHistogramGrid.RowHeight;
            rheight{2} = 0;
            app.ProcHistogramGrid.RowHeight = rheight;

            for n = 1:numel(rows)
                row = rows(n);
                chan_hist = Program.Helpers.to_user_uint8(raw.array(:, :, :, row.source_idx));

                if app.HidezerointensitypixelsCheckBox.Value
                    chan_hist = chan_hist(chan_hist > 0);
                end

                if isempty(chan_hist)
                    continue
                end

                [h_panel, h_label, h_axes] = Program.Handlers.histograms.get_gui(row.row);
                h_panel.Visible = 'on';

                h_label.Text = sprintf("%s Channel", row.role_name);
                histogram(h_axes, chan_hist, ...
                    'FaceColor', row.color, ...
                    'EdgeColor', row.color)
                lower_bound = app.HidezerointensitypixelsCheckBox.Value;
                if h_axes.XLim(2) <= 1.0 && lower_bound == 1
                    lower_bound = 0.001;
                end
                h_axes.XLim = [lower_bound, h_axes.XLim(2)];

                if row.row >= 4
                    rheight = app.ProcHistogramGrid.RowHeight;
                    rheight{2} = '1x';
                    app.ProcHistogramGrid.RowHeight = rheight;

                    h_panel.Parent = app.ProcHistogramGrid;
                    h_panel.Layout.Row = 2;
                    h_panel.Layout.Column = row.row - 3;
                end
            end
            
        end
    end

    methods(Static, Access=private)
        function raw = get_source_array(app)
            if strcmp(app.VolumeDropDown.Value, 'Colormap') && ...
                    app.ProcShowMIPCheckBox.Value && ...
                    isappdata(app.CELL_ID, 'proc_render_cache')
                cache = getappdata(app.CELL_ID, 'proc_render_cache');
                signature = Program.Helpers.processing_render_signature(app);
                if isstruct(cache) && isfield(cache, 'signature') && strcmp(cache.signature, signature)
                    raw = cache.raw;
                    return
                end
            end

            raw = Program.GUIHandling.get_active_volume(app, 'request', 'array');
        end

        function [h_panel, h_label, h_axes] = get_gui(c)
            app = Program.app;

            if c > Program.Handlers.channels.config{'max_channels'}
                c = Program.Helpers.first_unchecked_channel();
            end

            h_panel = Program.Routines.GUI.get_component('panels', Program.Handlers.histograms.prefixes{c});
            h_label = Program.Routines.GUI.get_component('labels', Program.Handlers.histograms.prefixes{c});
            h_axes = Program.Routines.GUI.get_component('axes', Program.Handlers.histograms.prefixes{c});
        end
    end
end
