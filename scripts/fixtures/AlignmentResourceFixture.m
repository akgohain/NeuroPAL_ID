classdef AlignmentResourceFixture < handle
    %ALIGNMENTRESOURCEFIXTURE Record cancellation and deletion without a pool.
    properties
        record
        name
        fail_cancel = false
    end
    methods
        function obj = AlignmentResourceFixture(record,name)
            obj.record = record;
            obj.name = name;
            record([name '_cancel']) = 0;
            record([name '_delete']) = 0;
        end
        function cancel(obj)
            key = [obj.name '_cancel'];
            obj.record(key) = obj.record(key)+1;
            if obj.fail_cancel
                error('NeuroPAL:Test:CancelFailure','Injected cancellation failure.');
            end
        end
        function delete(obj)
            key = [obj.name '_delete'];
            obj.record(key) = obj.record(key)+1;
        end
    end
end
