classdef VideoReview < handle
    %VIDEOREVIEW Link quality cues and reversible edits to the selected neuron.
    properties
        View
        Filter
        List
        Note
        Confirm
        Undo
        Next
        Issues = zeros(0,3)
        Key = {}
        Snapshots = {}
        SnapshotBytes = 0
    end
    methods
        function obj = VideoReview(view,parent)
            obj.View=view;
            obj.Next=uibutton(parent,'Text','Next issue','ButtonPushedFcn',@(~,~) obj.next()); obj.Next.Layout.Row=2;
            loop=uibutton(parent,'Text','Loop nearby','ButtonPushedFcn',@(~,~) view.Playback.around()); loop.Layout.Row=2; loop.Layout.Column=2;
            obj.Filter=uidropdown(parent,'Items',{'Tracking cues','Signal cues','All quality flags'},'ValueChangedFcn',@(~,~) view.redraw());
            obj.Filter.Layout.Row=3;
            obj.Note=uilabel(parent,'Text','Unreviewed','FontSize',11); obj.Note.Layout.Row=3; obj.Note.Layout.Column=2;
            obj.List=uilistbox(parent,'Items',{},'ValueChangedFcn',@(~,~) obj.choose()); obj.List.Layout.Row=4; obj.List.Layout.Column=[1 2];
        end
        function render(obj)
            c=obj.View.Controller; identity=obj.View.PreferredID;
            origin=sprintf('%d:%d',identity,c.Frame.Value); obj.Note.Text='Unreviewed';
            if isKey(c.Origins,origin) && any(strcmp(c.Origins(origin),{'reviewed','confirmed'})), obj.Note.Text='Verified here'; end
            obj.Undo.Enable=matlab.lang.OnOffSwitchState(~c.Busy && ~isempty(obj.Snapshots));
            obj.Confirm.Enable=matlab.lang.OnOffSwitchState(~c.Busy && ~isempty(obj.View.Selection) && ~obj.View.Selection(1));
            key={identity,c.ActivityDirectory,c.activityCurrent(),obj.Filter.Value,c.Rows,c.Excluded};
            if isequaln(obj.Key,key), return; end
            obj.Key=key; frames=(1:c.Source.nt)'; flags=zeros(c.Source.nt,1,'uint16');
            measured=key{3};
            if measured
                file=fullfile(c.ActivityDirectory,'activity.h5'); ids=double(h5read(file,'/neuron_id'));
                index=find(ids==identity,1);
                if ~isempty(index)
                    ts=double(h5read(file,'/frame')); values=h5read(file,'/quality_flags',[index 1],[1 numel(ts)]);
                    frames=ts(:); flags=uint16(values(:));
                end
            else
                rows=sortrows(c.Rows(c.Rows(:,1)==identity,:),2);
                if ~isempty(rows)
                    missing=~ismember(frames,rows(:,2)); flags(missing)=1;
                    jump=[false;diff(rows(:,2))==1 & vecnorm(diff(rows(:,3:5)),2,2)>c.Analysis.Controls.motion.Value];
                    flags(rows(jump,2))=256;
                end
            end
            switch obj.Filter.Value
                case 'Tracking cues', mask=uint16(1+4+8+16+256);
                case 'Signal cues', mask=uint16(32+64+128+512+1024);
                otherwise, mask=uint16(2047);
            end
            flags=bitand(flags,mask); active=find(flags~=0);
            obj.Issues=zeros(0,3);
            if ~isempty(active)
                starts=[1;find(diff(frames(active))>1 | diff(double(flags(active)))~=0)+1];
                ends=[starts(2:end)-1;numel(active)];
                obj.Issues=[frames(active(starts)),frames(active(ends)),double(flags(active(starts)))];
            end
            labels=cell(size(obj.Issues,1),1);
            for i=1:numel(labels)
                labels{i}=sprintf('%d–%d · %s',obj.Issues(i,1),obj.Issues(i,2),obj.reason(obj.Issues(i,3)));
            end
            if isempty(labels)
                obj.List.Parent.RowHeight{4}=28;
                obj.List.Items={'No matching cues'}; obj.List.ItemsData=[]; obj.List.Enable='off';
            else
                obj.List.Parent.RowHeight{4}=60;
                obj.List.Items=labels; obj.List.ItemsData=1:numel(labels); obj.List.Value=1; obj.List.Enable='on';
            end
            if measured, obj.List.Tooltip='Quality flags for the selected neuron. Flags are review cues, not confirmed errors.';
            else, obj.List.Tooltip='Current-coordinate gaps and motion only. Extract activity for signal and ROI quality flags.'; end
            ax=obj.View.Playback.Events; marks=findobj(ax,'Tag','review_events');
            x=obj.Issues(:,1); y=ones(size(x))*.5;
            if isempty(marks)
                marks=scatter(ax,x,y,16,[.65 .45 .2],'filled','Tag','review_events');
                marks.ButtonDownFcn=@(~,~) obj.seekMark();
            else
                marks.XData=x; marks.YData=y;
            end
            ax.XLim=[.5 c.Source.nt+.5]; ax.YLim=[0 1]; ax.Visible='off';
            obj.Next.Enable=matlab.lang.OnOffSwitchState(~c.Busy && ~isempty(obj.Issues));
        end
        function choose(obj)
            if isempty(obj.Issues) || obj.View.Controller.Busy, return; end
            obj.View.navigate(obj.Issues(obj.List.Value,1));
        end
        function next(obj)
            if isempty(obj.Issues) || obj.View.Controller.Busy, return; end
            index=find(obj.Issues(:,1)>obj.View.Controller.Frame.Value,1);
            if isempty(index), index=1; end
            obj.List.Value=index; obj.choose();
        end
        function seekMark(obj)
            if isempty(obj.Issues), return; end
            point=obj.View.Playback.Events.CurrentPoint; [~,index]=min(abs(obj.Issues(:,1)-point(1,1)));
            obj.List.Value=index; obj.choose();
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
            obj.Snapshots={}; obj.SnapshotBytes=0; obj.Key={};
        end
    end
    methods (Static)
        function text = reason(flags)
            names={'Missing','Excluded','ROI clipped','Overlap','Empty ROI','Empty background','Invalid baseline', ...
                'Invalid reference','Large displacement','Saturated','Invalid ratio baseline'};
            selected=bitget(uint16(flags),1:numel(names))~=0;
            text=strjoin(names(selected),', ');
        end
    end
end
