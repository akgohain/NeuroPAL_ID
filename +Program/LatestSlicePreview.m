classdef LatestSlicePreview < handle
    %LATESTSLICEPREVIEW Coalesce drag events and cancel previews on release.
    properties (Access = private)
        Worker
        Preview
        Commit
        Context
        Pending = []
        PendingContext = []
        LifetimeListener = []
    end
    methods
        function obj = LatestSlicePreview(preview, commit, context, owner)
            obj.Preview = preview;
            obj.Commit = commit;
            obj.Context = context;
            obj.Worker = timer('Name', 'NeuroPAL main slice preview', ...
                'ExecutionMode', 'fixedSpacing', 'Period', 0.04, ...
                'StartDelay', 0.02, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) obj.flush());
            obj.LifetimeListener = addlistener(owner, 'ObjectBeingDestroyed', ...
                @(~, ~) delete(obj));
        end

        function request(obj, value)
            obj.Pending = round(double(value));
            obj.PendingContext = obj.Context();
            if strcmp(obj.Worker.Running, 'off')
                start(obj.Worker);
            end
        end

        function finish(obj, src, event)
            % The release value wins over every preview already queued.
            obj.cancel();
            obj.Commit(src, event);
        end

        function flush(obj)
            value = obj.Pending;
            context = obj.PendingContext;
            obj.cancel();
            if isempty(value) || ~isequaln(context, obj.Context())
                return
            end
            obj.Preview(value);
            drawnow limitrate nocallbacks;
        end

        function cancel(obj)
            obj.Pending = [];
            obj.PendingContext = [];
            if ~isempty(obj.Worker) && isvalid(obj.Worker)
                stop(obj.Worker);
            end
        end

        function delete(obj)
            obj.cancel();
            if ~isempty(obj.Worker) && isvalid(obj.Worker)
                delete(obj.Worker);
            end
            if ~isempty(obj.LifetimeListener) && isvalid(obj.LifetimeListener)
                delete(obj.LifetimeListener);
            end
        end
    end
end
