classdef ReferenceConstraints
    %REFERENCECONSTRAINTS Match new reference proposals to existing neuron IDs.
    methods (Static)
        function yes = needed(c)
            yes=~isempty(c.Rows) && ~isempty(c.Candidates) && c.CandidateFrame~=c.Reference.Value;
        end
        function acceptOrMatch(c)
            if c.Busy, return; end
            if Tracking.ReferenceConstraints.needed(c), Tracking.ReferenceConstraints.open(c);
            else, c.safe(@() c.accept()); end
        end
        function open(c)
            if c.Busy || isempty(c.Rows), return; end
            c.View.Playback.stop();
            window=getappdata(c.Grid,'reference_constraints_window');
            if isempty(window) || ~isvalid(window)
                window=uifigure('Name','Match reference neurons','Position',[300 300 390 470]);
                window.CloseRequestFcn=@(src,~) set(src,'Visible','off');
                grid=uigridlayout(window,[7 1]); grid.Padding=[14 12 14 12];
                grid.RowHeight={38,'1x',22,30,34,30,30}; grid.RowSpacing=8;
                uilabel(grid,'Text','Match a proposal or place a center for a neuron from the original reference.','WordWrap','on');
                list=uilistbox(grid,'Items',{},'ItemsData',[], ...
                    'ValueChangedFcn',@(~,~) Tracking.ReferenceConstraints.select(c));
                uilabel(grid,'Text','Existing neuron');
                target=uidropdown(grid,'Items',{},'ItemsData',[]);
                apply=uibutton(grid,'Text','Use selected center','FontWeight','bold', ...
                    'ButtonPushedFcn',@(~,~) Tracking.ReferenceConstraints.apply(c));
                place=uibutton(grid,'Text','Place center…', ...
                    'Tooltip','Manually locate the selected existing neuron when no proposal matches it.', ...
                    'ButtonPushedFcn',@(~,~) Tracking.ReferenceConstraints.place(c,target.Value));
                done=uibutton(grid,'Text','Finish matching', ...
                    'ButtonPushedFcn',@(~,~) Tracking.ReferenceConstraints.finish(c));
                controls=struct('window',window,'list',list,'target',target,'apply',apply,'place',place,'done',done);
                setappdata(c.Grid,'reference_constraints_window',window);
                setappdata(c.Grid,'reference_constraints_controls',controls);
            end
            window.Visible='on'; Tracking.ReferenceConstraints.refresh(c);
            Tracking.ReferenceConstraints.select(c);
            figure(window);
        end
        function refresh(c)
            controls=getappdata(c.Grid,'reference_constraints_controls');
            if isempty(controls) || ~isvalid(controls.window) || strcmp(controls.window.Visible,'off'), return; end
            previous=controls.list.Value; ids=c.Candidates(:,1)';
            labels=cellstr("Candidate "+string(ids)+" · Z "+compose('%.1f',c.Candidates(:,5)'));
            controls.list.Items=labels; controls.list.ItemsData=ids;
            if isnumeric(previous) && isscalar(previous) && ismember(previous,ids), controls.list.Value=previous;
            elseif ~isempty(ids), controls.list.Value=ids(1); end
            previous=controls.target.Value; ids=unique(c.Rows(c.Rows(:,2)==c.Reference.Value,1))';
            labels=arrayfun(@(id) Tracking.NeuronNames.label(c,id,true),ids,'UniformOutput',false);
            controls.target.Items=labels; controls.target.ItemsData=ids;
            if isnumeric(previous) && isscalar(previous) && ismember(previous,ids), controls.target.Value=previous;
            elseif ~isempty(ids), controls.target.Value=ids(1); end
            Tracking.ReferenceConstraints.setBusy(c,c.Busy);
        end
        function select(c)
            if c.Busy, return; end
            controls=getappdata(c.Grid,'reference_constraints_controls');
            if isempty(controls.list.Value), return; end
            row=c.Candidates(c.Candidates(:,1)==controls.list.Value,:);
            if ~isempty(row), c.View.select(row,true); end
        end
        function apply(c)
            if c.Busy, return; end
            controls=getappdata(c.Grid,'reference_constraints_controls');
            if isempty(controls.list.Value) || isempty(controls.target.Value), return; end
            candidate=controls.list.Value; identity=controls.target.Value;
            replace=any(c.Rows(:,1)==identity & c.Rows(:,2)==c.CandidateFrame);
            if replace
                answer=uiconfirm(controls.window,'Replace this neuron’s existing center in this frame?', ...
                    'Replace observation?','Options',{'Cancel','Replace'},'DefaultOption',1,'CancelOption',1);
                if ~strcmp(answer,'Replace'), return; end
            end
            try
                Tracking.ReferenceConstraints.assign(c,candidate,identity,replace);
                Tracking.ReferenceConstraints.refresh(c); Tracking.ReferenceConstraints.select(c);
            catch ME
                uialert(controls.window,ME.message,'Match reference neuron');
            end
        end
        function assign(c,candidate,identity,replace)
            if nargin<4, replace=false; end
            if c.Busy, error('Tracking:Busy','Wait for the current job before matching a neuron.'); end
            index=find(c.Candidates(:,1)==candidate,1);
            if isempty(index), error('Tracking:ReferenceCandidate','This proposal is no longer available.'); end
            if ~any(c.Rows(:,1)==identity & c.Rows(:,2)==c.Reference.Value)
                error('Tracking:ReferenceIdentity','Choose an existing neuron from the original reference frame.');
            end
            row=c.Candidates(index,:); frame=row(2);
            if c.Frame.Value~=frame || c.CacheFrame~=frame
                error('Tracking:CandidateView','Open the candidate frame before matching its neurons.');
            end
            existing=c.Rows(:,1)==identity & c.Rows(:,2)==frame;
            if any(existing) && ~replace
                error('Tracking:ExistingObservation','This neuron already has a center in this frame. Confirm replacement first.');
            end
            c.View.Review.checkpoint(identity);
            row(1)=identity; row(6)=1;
            c.Rows(existing,:)=[]; c.Rows(end+1,:)=row; c.Candidates(index,:)=[];
            c.Origins(sprintf('%d:%d',identity,frame))='reviewed';
            c.View.PreferredID=identity; c.View.Selection=[false identity frame];
            c.render(); Tracking.ReferenceFrames.refresh(c);
            c.Status.Text=sprintf('Matched %s in frame %d.',Tracking.NeuronNames.label(c,identity,true),frame);
        end
        function place(c,identity)
            if c.Busy || isempty(identity), return; end
            if ~any(c.Rows(:,1)==identity & c.Rows(:,2)==c.Reference.Value)
                uialert(c.App.CELL_ID,'Choose an existing neuron from the primary reference frame.','Place reference neuron'); return;
            end
            frame=c.Frame.Value; existing=any(c.Rows(:,1)==identity & c.Rows(:,2)==frame);
            if existing
                answer=uiconfirm(c.App.CELL_ID,'Replace this neuron’s existing center in this frame?', ...
                    'Replace observation?','Options',{'Cancel','Replace'},'DefaultOption',1,'CancelOption',1);
                if ~strcmp(answer,'Replace'), return; end
            end
            c.View.Playback.stop(); c.View.CorrectMode=false; c.View.setStage(4);
            c.View.AddMode=true; c.View.AddIdentity=identity; c.View.AddFrame=frame; c.View.AddReplace=existing;
            c.View.DisplayMode.Value='Slice'; c.View.redraw();
            window=getappdata(c.Grid,'reference_constraints_window');
            if ~isempty(window) && isvalid(window), window.Visible='off'; end
            c.Status.Text=sprintf('Click %s in this Z slice (frame %d).',Tracking.NeuronNames.label(c,identity,true),frame);
            c.Buttons.add.Text='Cancel adding neuron'; Tracking.VideoWorkspace.refreshActions(c,false);
        end
        function finish(c)
            if c.Busy, return; end
            controls=getappdata(c.Grid,'reference_constraints_controls');
            if ~isempty(c.Candidates)
                answer=uiconfirm(controls.window,sprintf('Discard %d unmatched proposals? Accepted neurons and reference centers will be kept.',size(c.Candidates,1)), ...
                    'Finish matching?','Options',{'Keep matching','Discard unmatched'},'DefaultOption',1,'CancelOption',1);
                if ~strcmp(answer,'Discard unmatched'), return; end
                c.View.Review.checkpoint(); c.Candidates=zeros(0,7); c.render();
            end
            controls.window.Visible='off';
        end
        function setBusy(c,busy)
            controls=getappdata(c.Grid,'reference_constraints_controls');
            if isempty(controls) || ~isvalid(controls.window), return; end
            controls.list.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(c.Candidates));
            controls.target.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(controls.target.Items));
            controls.apply.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(c.Candidates) && ~isempty(controls.target.Items));
            controls.place.Enable=matlab.lang.OnOffSwitchState(~busy && ~isempty(controls.target.Items));
            controls.done.Enable=matlab.lang.OnOffSwitchState(~busy);
        end
    end
end
