classdef MLProgress
    %MLPROGRESS Shared progress UI for long-running ML methods.

    methods(Static)
        function progress = open(title, message, options)
            arguments
                title (1,1) string
                message (1,1) string = "Starting..."
                options.App = []
            end

            progress = [];
            app = options.App;
            if isempty(app)
                app = Methods.MLProgress.currentApp();
            end
            if isempty(app)
                return
            end

            try
                progress = uiprogressdlg(app.CELL_ID, ...
                    'Title', char(title), ...
                    'Message', char(message), ...
                    'Indeterminate', 'on', ...
                    'Cancelable', 'off');
                drawnow limitrate;
            catch
                progress = [];
            end
        end

        function update(progress, message, value)
            arguments
                progress
                message (1,1) string = ""
                value = []
            end

            if isempty(progress) || ~isvalid(progress)
                return
            end
            try
                if strlength(message) > 0
                    progress.Message = char(message);
                end
                if ~isempty(value) && isfinite(double(value))
                    progress.Indeterminate = 'off';
                    progress.Value = min(max(double(value), 0), 1);
                end
                drawnow limitrate;
            catch
            end
        end

        function close(progress)
            if isempty(progress) || ~isvalid(progress)
                return
            end
            try
                delete(progress);
            catch
            end
        end

        function fcn = callback(progress)
            fcn = @(message) Methods.MLProgress.update(progress, string(message), []);
        end

        function value = cancelled(progress)
            value = ~isempty(progress) && (~isvalid(progress) || progress.CancelRequested);
        end

        function app = currentApp()
            app = [];
            try
                app = Program.app;
                if isempty(app) || ~isvalid(app) || ...
                        ~isprop(app, 'CELL_ID') || isempty(app.CELL_ID) || ...
                        ~isvalid(app.CELL_ID)
                    app = [];
                end
            catch
                app = [];
            end
        end
    end
end
