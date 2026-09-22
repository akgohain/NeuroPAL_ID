classdef VideoReview < handle
    %VIDEOREVIEW Preserve reversible edits to the selected neuron.
    properties
        View
        Confirm
        Undo
        Snapshots = {}
        SnapshotBytes = 0
    end
    methods
        function obj = VideoReview(view)
            obj.View=view;
        end
        function render(obj)
            c=obj.View.Controller;
            obj.Undo.Enable=matlab.lang.OnOffSwitchState(~c.Busy && ~isempty(obj.Snapshots));
            obj.Confirm.Enable=matlab.lang.OnOffSwitchState(~c.Busy && ~isempty(obj.View.Selection) && ~obj.View.Selection(1));
        end
        function checkpoint(obj,identity)
            c=obj.View.Controller; obj.View.Playback.stop();
            bytes=8*(numel(c.Rows)+numel(c.Candidates)+numel(c.Excluded));
            if bytes>32*2^20, obj.clear(); return; end
            if nargin<2, identity=obj.View.PreferredID; end
            keys=c.Origins.keys;
            keys=keys(startsWith(keys,sprintf('%d:',identity)));
            snapshot=struct('rows',c.Rows,'candidates',c.Candidates,'excluded',c.Excluded,'next_id',c.NextID, ...
                'identity',identity,'preferred',obj.View.PreferredID,'selection',obj.View.Selection,'keys',{keys},'values',{values(c.Origins,keys)},'bytes',bytes);
            while ~isempty(obj.Snapshots) && (numel(obj.Snapshots)>=5 || obj.SnapshotBytes+bytes>32*2^20)
                obj.SnapshotBytes=obj.SnapshotBytes-obj.Snapshots{1}.bytes; obj.Snapshots(1)=[];
            end
            obj.Snapshots{end+1}=snapshot; obj.SnapshotBytes=obj.SnapshotBytes+bytes;
        end
        function undo(obj)
            c=obj.View.Controller; if c.Busy || isempty(obj.Snapshots), return; end
            obj.View.Playback.stop(); saved=obj.Snapshots{end}; obj.Snapshots(end)=[]; obj.SnapshotBytes=obj.SnapshotBytes-saved.bytes;
            c.Rows=saved.rows; c.Candidates=saved.candidates; c.Excluded=saved.excluded; c.NextID=saved.next_id;
            keys=c.Origins.keys; keys=keys(startsWith(keys,sprintf('%d:',saved.identity)));
            if ~isempty(keys), remove(c.Origins,keys); end
            for i=1:numel(saved.keys), c.Origins(saved.keys{i})=saved.values{i}; end
            obj.View.Selection=saved.selection; obj.View.PreferredID=saved.preferred;
            if ~isempty(saved.selection), c.Frame.Value=saved.selection(3); end
            c.render();
        end
        function confirm(obj)
            c=obj.View.Controller; row=obj.View.Selection;
            if c.Busy || isempty(row) || row(1), return; end
            obj.checkpoint(); c.Origins(sprintf('%d:%d',row(2),row(3)))='confirmed'; c.render();
        end
        function clear(obj)
            obj.Snapshots={}; obj.SnapshotBytes=0;
        end
    end
end
