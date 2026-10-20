classdef ManualIDController
    %MANUALIDCONTROLLER Own drafts and suggestions without implicit annotation saves.
    methods (Static)
        function install(app)
            state=Program.GUI.ManualIDController.state(app);
            if state.installed
                Program.GUI.ManualIDController.installRelease(app); return;
            end
            state.installed=true;
            state.previousKey=app.CELL_ID.WindowKeyPressFcn;
            state.previousRelease=app.CELL_ID.WindowKeyReleaseFcn;
            state.previousMouse=app.CELL_ID.WindowButtonDownFcn;
            state.previousResize=app.CELL_ID.SizeChangedFcn;
            state.previousTab=app.TabGroup.SelectionChangedFcn;
            Program.GUI.ManualIDController.put(app,state);
            app.CELL_ID.WindowKeyPressFcn=@(src,event) Program.GUI.ManualIDController.windowKey(app,src,event);
            app.CELL_ID.WindowKeyReleaseFcn=@(src,event) Program.GUI.ManualIDController.windowRelease(app,src,event);
            setappdata(app.CELL_ID,'manual_id_release_installed',true);
            app.CELL_ID.WindowButtonDownFcn=@(src,event) Program.GUI.ManualIDController.windowMouse(app,src,event);
            listener=addlistener(app.CELL_ID,'ObjectBeingDestroyed', ...
                @(src,~) Program.GUI.ManualIDController.disposeWatchers(src));
            setappdata(app.CELL_ID,'manual_id_resize_cleanup',listener);
            app.TabGroup.SelectionChangedFcn=@(src,event) Program.GUI.ManualIDController.tabChanged(app,src,event);
        end
        function state=state(app)
            state=getappdata(app.CELL_ID,'manual_id_controller');
            if ~isempty(state)
                defaults=struct('previousRelease',[],'pendingGesture',[],'mouseGesture',[], ...
                    'keyGesture',[],'heldAssignmentKey','','lastCommittedGesture','', ...
                    'focusRole','','focusOwner','','focusAction',0, ...
                    'focusBoundary','','focusOffset',0);
                fields=fieldnames(defaults);
                for i=1:numel(fields)
                    if ~isfield(state,fields{i}), state.(fields{i})=defaults.(fields{i}); end
                end
                return;
            end
            state=struct('installed',false,'drafts',containers.Map('KeyType','char','ValueType','any'), ...
                'key','','context',struct(),'text','','baseline','','parsed',[], ...
                'staged',[],'generation',0,'dirty',false,'active',0,'rows',[], ...
                'open',false,'allNames',false,'expanded','','busy',false,'operation','', ...
                'lastCommitTime',-Inf,'previousKey',[],'previousMouse',[], ...
                'previousResize',[],'previousTab',[],'previousRelease',[], ...
                'pendingGesture',[],'mouseGesture',[],'keyGesture',[], ...
                'heldAssignmentKey','','lastCommittedGesture','', ...
                'focusRole','','focusOwner','','focusAction',0, ...
                'focusBoundary','','focusOffset',0, ...
                'status','','cacheKey','','cache',[],'clickUntil',-Inf,'buttonText','Assign');
            Program.GUI.ManualIDController.put(app,state);
        end
        function put(app,state)
            setappdata(app.CELL_ID,'manual_id_controller',state);
        end
        function ui=ui(app)
            ui=getappdata(app.IDEditField,'manual_id_ui');
        end
        function select(app,index)
            if nargin<2, index=app.selected_neuron; end
            if isempty(index), Program.GUI.ManualIDController.unselect(app); return; end
            Program.GUI.ManualIDService.ensure(app);
            context=Program.GUI.ManualIDService.context(app,index);
            state=Program.GUI.ManualIDController.stash(Program.GUI.ManualIDController.state(app));
            state.key=Program.GUI.ManualIDController.ownerKey(context); state.context=context;
            if ~strcmp(state.focusOwner,state.key)
                state.focusRole=''; state.focusOwner=''; state.focusAction=0;
                state.focusBoundary=''; state.focusOffset=0;
            end
            state.open=false; state.active=0; state.expanded=''; state.status=''; state.operation='';
            record=Program.GUI.ManualIDService.record(app,index);
            state.baseline=Program.GUI.ManualIDController.recordText(record);
            if isKey(state.drafts,state.key)
                draft=state.drafts(state.key);
                state.text=draft.text; state.staged=draft.staged; state.dirty=true;
                if ~isequal(draft.context,context)
                    state.staged=[]; state.status='Context changed. Review this draft before assigning.';
                end
            else
                state.text=state.baseline;
                state.staged=Program.GUI.ManualIDController.baselineDraft(record,context.sex);
                state.dirty=false;
                if isempty(state.text) && app.AutoNameCheckBox.Value
                    prediction=app.image_neurons.neurons(index).deterministic_id;
                    provisional=Annotations.Catalog.parse(prediction,context.sex,false);
                    if provisional.valid && strcmp(provisional.kind,'individual')
                        state.text=provisional.token;
                    end
                end
            end
            state.parsed=Annotations.Catalog.parse(state.text,context.sex,state.allNames);
            if isempty(state.status), state.status=Program.GUI.ManualIDController.reviewMessage(record); end
            state.generation=state.generation+1;
            if strcmp(record.kind,'unassigned'), state.buttonText='Assign'; else, state.buttonText='Update ID'; end
            Program.GUI.ManualIDController.put(app,state);
            Program.GUI.ManualIDController.renderText(app,state.text);
            Program.GUI.ManualIDInput.setEnabled(app,'on');
            app.UserIDButton.Text=state.buttonText;
            Program.GUI.ManualIDController.describe(app,state);
            Program.GUI.ManualIDController.close(app);
        end
        function unselect(app)
            state=Program.GUI.ManualIDController.stash(Program.GUI.ManualIDController.state(app));
            state.key=''; state.context=struct(); state.text=''; state.staged=[];
            state.parsed=[]; state.dirty=false; state.open=false; state.active=0;
            Program.GUI.ManualIDController.put(app,state);
            Program.GUI.ManualIDController.close(app);
        end
        function edited(app,text,show)
            if nargin<3, show=true; end
            if ~isvalid(app) || strcmp(app.IDEditField.Enable,'off') || isempty(app.selected_neuron), return; end
            state=Program.GUI.ManualIDController.state(app);
            context=Program.GUI.ManualIDService.context(app,app.selected_neuron);
            if ~strcmp(state.key,Program.GUI.ManualIDController.ownerKey(context)) || ~isequaln(state.context,context)
                Program.GUI.ManualIDController.select(app,app.selected_neuron);
                state=Program.GUI.ManualIDController.state(app);
            end
            % A final native text event can arrive after an explicit focus transfer.
            retainFocus=show && strcmp(state.focusOwner,state.key) && ...
                any(strcmp(state.focusRole,{'assign','actions'}));
            text=char(string(text));
            if ~strcmp(text,state.text)
                state.text=text; state.staged=[]; state.expanded=''; state.active=0;
                state.generation=state.generation+1; state.operation=''; state.status='';
                state.dirty=~strcmp(text,state.baseline);
            end
            state.parsed=Annotations.Catalog.parse(text,context.sex,state.allNames);
            % A focus intent can absorb final native text; captured commands cannot.
            if ~show && ~isempty(state.pendingGesture) && ...
                    strcmp(state.pendingGesture.origin,'keyboard-focus') && ...
                    strcmp(state.pendingGesture.owner_key,state.key) && isequaln(state.pendingGesture.context,context)
                state.pendingGesture.generation=state.generation;
                if ~isempty(state.keyGesture) && strcmp(state.keyGesture.origin,'keyboard-focus') && ...
                        strcmp(state.keyGesture.operation_id,state.pendingGesture.operation_id)
                    state.keyGesture=state.pendingGesture;
                end
            end
            Program.GUI.ManualIDController.put(app,Program.GUI.ManualIDController.stash(state));
            app.IDEditField.Value=text;
            ui=Program.GUI.ManualIDController.ui(app);
            if ~isempty(ui), setappdata(ui.input,'manual_id_native_value',ui.input.Value); end
            if show && ~retainFocus, Program.GUI.ManualIDController.noteFocus(app,'input'); end
            Program.GUI.ManualIDController.describe(app,state);
            if show && ~retainFocus, Program.GUI.ManualIDController.open(app);
            % Final native or pasted values can arrive without ValueChanging.
            elseif state.open, Program.GUI.ManualIDController.refresh(app); end
        end
        function draft=capture(app)
            state=Program.GUI.ManualIDController.state(app);
            if isempty(state.key) && ~isempty(app.selected_neuron)
                Program.GUI.ManualIDController.select(app,app.selected_neuron);
                state=Program.GUI.ManualIDController.state(app);
            end
            if isempty(state.staged)
                draft=Annotations.Catalog.parse(state.text,Program.GUI.ManualIDController.sex(app),state.allNames);
            else
                draft=state.staged; draft.valid=true;
            end
        end
        function result=assign(app,index,text,action,gesture)
            if nargin<2 || isempty(index), index=app.selected_neuron; end
            if nargin<3, text=[]; end
            if nargin<4, action='assign'; end
            if nargin<5, gesture=[]; end
            result=struct('changed',false,'noop',false);
            Program.GUI.ManualIDController.readVisible(app);
            state=Program.GUI.ManualIDController.state(app);
            if state.busy, return; end
            if ~isempty(gesture)
                if strcmp(state.lastCommittedGesture,gesture.operation_id)
                    result.noop=true; result.replayed=true; return;
                end
                if ~strcmp(state.key,gesture.owner_key) || state.generation~=gesture.generation
                    Program.GUI.ManualIDController.message(app,'This assignment belongs to an earlier draft. Review the selected neuron before assigning.');
                    return;
                end
                index=gesture.index;
                state.operation=gesture.operation_id;
                Program.GUI.ManualIDController.put(app,state);
            end
            if isempty(index)
                Program.GUI.ManualIDController.message(app,'Select a neuron before assigning an ID.'); return;
            end
            if ~isempty(text), Program.GUI.ManualIDController.edited(app,text,false); end
            state=Program.GUI.ManualIDController.state(app);
            context=Program.GUI.ManualIDService.context(app,index);
            if ~strcmp(state.key,Program.GUI.ManualIDController.ownerKey(context))
                Program.GUI.ManualIDController.message(app,'The selected neuron changed. Review its ID before assigning.'); return;
            end
            if isempty(strtrim(state.text)) && isempty(state.staged), action='clear'; end
            draft=Program.GUI.ManualIDController.capture(app);
            if ~strcmp(action,'clear') && ~draft.valid
                Program.GUI.ManualIDController.message(app,draft.message); return;
            end
            if isempty(state.operation), state.operation=char(java.util.UUID.randomUUID()); end
            state.busy=true; Program.GUI.ManualIDController.put(app,state);
            app.is_saving_ID=true;
            Program.GUI.ManualIDInput.setEnabled(app,'off');
            % Keep native button focus while the busy guard rejects repeats.
            app.UserIDButton.Text='Saving…';
            guard=onCleanup(@() Program.GUI.ManualIDController.release(app));
            options=struct('operation_id',state.operation,'context',state.context, ...
                'expected_revision',state.context.annotation_revision,'draft_generation',state.generation);
            if isfield(draft,'context_exception_reason') && ~isempty(draft.context_exception_reason)
                options.reason=draft.context_exception_reason;
            end
            try
                result=Program.GUI.ManualIDService.assign(app,index,draft,action,options);
                if result.changed
                    current=Program.GUI.ManualIDController.state(app);
                    same=strcmp(current.key,state.key) && current.generation==state.generation;
                    if isKey(current.drafts,state.key)
                        saved=current.drafts(state.key);
                        if saved.generation==state.generation, remove(current.drafts,state.key); end
                    end
                    if same, current.dirty=false; current.operation=''; end
                    current.lastCommitTime=now;
                    current.lastCommittedGesture=state.operation;
                    Program.GUI.ManualIDController.put(app,current);
                    if same, Program.GUI.ManualIDController.close(app); end
                    try
                        Program.GUI.ManualIDController.notify(app,index,result,same);
                    catch renderError
                        result.display_error=renderError.message;
                        Program.GUI.ManualIDController.message(app,['Saved; display could not refresh. ' renderError.message]);
                    end
                elseif isfield(result,'noop') && result.noop
                    if strcmp(action,'clear')
                        Program.GUI.ManualIDController.message(app,'This neuron has no saved ID.');
                    else
                        current=Program.GUI.ManualIDController.state(app);
                        if strcmp(current.key,state.key) && current.generation==state.generation
                            if isKey(current.drafts,state.key), remove(current.drafts,state.key); end
                            record=Program.GUI.ManualIDService.record(app,index);
                            current.context=Program.GUI.ManualIDService.context(app,index);
                            current.baseline=Program.GUI.ManualIDController.recordText(record);
                            current.text=current.baseline; current.dirty=false;
                            current.staged=Program.GUI.ManualIDController.baselineDraft(record,current.context.sex);
                            Program.GUI.ManualIDController.put(app,current);
                            Program.GUI.ManualIDController.renderText(app,current.text);
                            Program.GUI.ManualIDController.describe(app,current);
                        end
                        Program.GUI.ManualIDController.message(app,'This ID is already saved.');
                    end
                end
            catch ME
                Program.GUI.ManualIDController.message(app,ME.message);
            end
        end
        function clear(app)
            state=Program.GUI.ManualIDController.state(app);
            if ~isempty(state.key), Program.GUI.ManualIDController.assign(app,app.selected_neuron,[],'clear'); end
        end
        function undo(app)
            state=Program.GUI.ManualIDController.state(app);
            if state.busy, return; end
            state.busy=true; Program.GUI.ManualIDController.put(app,state);
            app.is_saving_ID=true;
            Program.GUI.ManualIDInput.setEnabled(app,'off');
            guard=onCleanup(@() Program.GUI.ManualIDController.release(app));
            try
                result=Program.GUI.ManualIDService.undo(app);
                if result.changed
                    try
                        Program.GUI.ManualIDController.notify(app,app.selected_neuron,result,false);
                    catch renderError
                        Program.GUI.ManualIDController.message(app,['Saved; display could not refresh. ' renderError.message]);
                    end
                    if ~isempty(app.selected_neuron), Program.GUI.ManualIDController.select(app,app.selected_neuron); end
                end
            catch ME
                Program.GUI.ManualIDController.message(app,ME.message);
            end
        end
        function notify(app,index,result,advance)
            callback=getappdata(app.CELL_ID,'manual_id_after_commit');
            if ~isempty(callback), callback(index,result,advance); end
        end
        function release(app)
            if ~isvalid(app) || ~isvalid(app.CELL_ID) || ...
                    ~isvalid(app.UserIDButton) || ~isvalid(app.IDEditField), return; end
            state=Program.GUI.ManualIDController.state(app); state.busy=false;
            Program.GUI.ManualIDController.put(app,state);
            app.is_saving_ID=false;
            app.UserIDButton.Text=state.buttonText;
            enabled=false;
            if ~isempty(app.selected_neuron)
                try
                    context=Program.GUI.ManualIDService.context(app,app.selected_neuron);
                    enabled=strcmp(state.key,Program.GUI.ManualIDController.ownerKey(context));
                catch
                    % A source closed during a modal must remain disabled.
                end
            end
            app.UserIDButton.Enable=matlab.lang.OnOffSwitchState(enabled);
            Program.GUI.ManualIDInput.setEnabled(app,matlab.lang.OnOffSwitchState(enabled));
        end
        function open(app)
            state=Program.GUI.ManualIDController.state(app);
            if isempty(state.key) || ~isequal(app.TabGroup.SelectedTab,app.NeuroPALIDTab), return; end
            state.open=true; Program.GUI.ManualIDController.put(app,state);
            Program.GUI.ManualIDController.refresh(app);
            ui=Program.GUI.ManualIDController.ui(app); if isempty(ui), return; end
            Program.GUI.ManualIDController.position(app); ui.panel.Visible='on';
            try, uistack(ui.panel,'top'); catch, end
            Program.GUI.ManualIDController.startResizeWatcher(app);
        end
        function close(app,delay)
            if nargin<2, delay=false; end
            if ~isvalid(app), return; end
            state=Program.GUI.ManualIDController.state(app); state.open=false; state.active=0;
            Program.GUI.ManualIDController.stopResizeWatcher(app.CELL_ID);
            ui=Program.GUI.ManualIDController.ui(app);
            if ~isempty(ui) && isvalid(ui.panel)
                if delay
                    % Keep the click surface briefly so a second click cannot hit the image.
                    state.clickUntil=now+.3/86400;
                    clock=timer('ExecutionMode','singleShot','StartDelay',.3, ...
                        'TimerFcn',@(~,~) Program.GUI.ManualIDController.delayedClose(app), ...
                        'StopFcn',@(src,~) delete(src));
                    start(clock);
                else, ui.panel.Visible='off'; end
            end
            Program.GUI.ManualIDController.put(app,state);
        end
        function delayedClose(app)
            if ~isvalid(app), return; end
            state=Program.GUI.ManualIDController.state(app);
            if ~state.open, Program.GUI.ManualIDController.close(app); end
        end
        function refresh(app)
            ui=Program.GUI.ManualIDController.ui(app); if isempty(ui), return; end
            state=Program.GUI.ManualIDController.state(app); if ~state.open, return; end
            rows=Program.GUI.ManualIDController.suggestions(app,state.text,state.expanded,state.allNames);
            state=Program.GUI.ManualIDController.state(app); state.rows=rows;
            ui.list.ItemsData=[]; ui.list.Items={rows.label}; ui.list.ItemsData=1:numel(rows);
            ui.list.Value={};
            if state.active>0 && state.active<=numel(rows), ui.list.Value=state.active; else, state.active=0; end
            status=state.status;
            if isempty(status)
                if ~state.dirty && ~isempty(state.staged) && strcmp(state.staged.kind,'unresolved_set')
                    status=['Saved · member unresolved · ' state.staged.certainty];
                elseif ~state.dirty && ~isempty(state.baseline)
                    if ~isempty(state.staged) && strcmp(state.staged.certainty,'unspecified')
                        status='Saved · certainty unspecified';
                    elseif ~isempty(state.staged) && strcmp(state.staged.certainty,'tentative')
                        status='Saved · tentative identity';
                    else, status='Saved annotation'; end
                elseif ~isempty(state.staged), status='Draft · Assign to save';
                elseif isempty(rows), status='No matching atlas names';
                elseif ~isempty(state.parsed) && state.parsed.requires_staging
                    status='Choose an individual or keep the family unresolved.';
                else, status='Enter selects · Tab to Assign'; end
            end
            ui.status.Text=status; ui.status.Tooltip=status;
            if state.allNames, ui.all.Text='Applicable names'; else, ui.all.Text='All atlas names'; end
            Program.GUI.ManualIDController.put(app,state);
        end
        function rows=suggestions(app,text,expanded,allNames)
            sex=Program.GUI.ManualIDController.sex(app);
            state=Program.GUI.ManualIDController.state(app);
            cacheKey=[char(string(sex)) ':' char(string(allNames))];
            if ~strcmp(state.cacheKey,cacheKey)
                names=Annotations.Catalog.names(sex,allNames); groups=Annotations.Catalog.groups(sex,allNames);
                records=cell(numel(names),1);
                for i=1:numel(names), records{i}=Annotations.Catalog.lookup(names{i},sex); end
                state.cacheKey=cacheKey;
                state.cache=struct('names',{names},'groups',groups,'records',{records});
                Program.GUI.ManualIDController.put(app,state);
            end
            cache=state.cache; parsed=Annotations.Catalog.parse(text,sex,allNames);
            query=upper(strtrim(char(string(text))));
            parts=regexp(query,'^(?<token>[A-Z][A-Z0-9]*)(?:-ON|-OFF)?\??!?$','names','once');
            if ~isempty(parts), query=parts.token; end
            if isempty(expanded) && strcmp(parsed.kind,'unresolved_set') && parsed.requires_staging
                expanded=parsed.token;
            end
            rows=struct('kind',{},'token',{},'label',{},'rank',{});
            occupied=Program.GUI.ManualIDController.occupied(app);
            if ~isempty(expanded)
                members=Annotations.Catalog.members(expanded,sex,allNames);
                if isempty(members), return; end
                rows(end+1)=Program.GUI.ManualIDController.row('group',expanded,[expanded ' · choose an individual'],0);
                for i=1:numel(members)
                    info=Annotations.Catalog.lookup(members{i},sex);
                    rows(end+1)=Program.GUI.ManualIDController.individualRow(info,occupied,1);
                end
                rows(end+1)=Program.GUI.ManualIDController.row('keep',expanded,['Keep ' expanded ' unresolved'],2);
                return;
            end
            for i=1:numel(cache.groups)
                group=cache.groups(i);
                rank=Program.GUI.ManualIDController.matchRank(group.token,upper([group.token ' ' group.description]),query,false);
                if isfinite(rank)
                    rows(end+1)=Program.GUI.ManualIDController.row('group',group.token, ...
                        sprintf('%s · %d members',group.token,numel(group.members)),rank);
                end
            end
            for i=1:numel(cache.names)
                info=cache.records{i};
                rank=Program.GUI.ManualIDController.matchRank(info.token,upper([info.token ' ' info.description]),query,true);
                aliases=cellstr(string(info.metadata.aliases));
                if any(strcmpi(aliases,query)), rank=min(rank,1);
                elseif ~isempty(query) && any(startsWith(upper(string(aliases)),query)), rank=min(rank,2); end
                if isfinite(rank), rows(end+1)=Program.GUI.ManualIDController.individualRow(info,occupied,rank); end
            end
            catalog=Annotations.Catalog.manifest();
            for i=1:numel(catalog.classifications)
                info=catalog.classifications(i);
                rank=Program.GUI.ManualIDController.matchRank(info.name,upper([info.name ' ' info.description]),query,true);
                if isfinite(rank), rows(end+1)=Program.GUI.ManualIDController.row('classification',info.name,info.name,rank); end
            end
            if ~isempty(rows), [~,order]=sort([rows.rank],'ascend'); rows=rows(order); end
        end
        function row=individualRow(info,occupied,rank)
            label=info.token;
            if ~isempty(info.description), label=[label ' · ' info.description]; end
            if ~info.applicable, label=[label ' · other sex']; end
            if any(strcmp(occupied,info.token)), label=[label ' · assigned']; end
            row=Program.GUI.ManualIDController.row('individual',info.token,label,rank);
        end
        function values=occupied(app)
            values={}; if isempty(app.image_neurons), return; end
            neurons=app.image_neurons.neurons;
            for i=1:numel(neurons)
                if isequal(i,app.selected_neuron), continue; end
                if isprop(neurons(i),'annotation_record') && isfield(neurons(i).annotation_record,'kind')
                    record=neurons(i).annotation_record;
                    if Annotations.Store.confirmed(record), values=[values;record.candidates(:)]; end
                elseif ~isempty(neurons(i).annotation) && neurons(i).annotation_confidence>.5
                    values{end+1,1}=neurons(i).annotation;
                end
            end
        end
        function row=row(kind,token,label,rank)
            row=struct('kind',kind,'token',token,'label',label,'rank',rank);
        end
        function rank=matchRank(token,description,query,individual)
            if isempty(query), rank=4;
            elseif strcmpi(token,query), rank=double(~individual);
            elseif startsWith(upper(token),query), rank=2;
            elseif contains(description,query), rank=3;
            else, rank=Inf; end
        end
        function highlight(app,value)
            state=Program.GUI.ManualIDController.state(app);
            if isempty(value), state.active=0; else, state.active=value(end); end
            Program.GUI.ManualIDController.put(app,state);
            ui=Program.GUI.ManualIDController.ui(app);
            if state.active>0, ui.list.Value=state.active; else, ui.list.Value={}; end
        end
        function clicked(app,event)
            state=Program.GUI.ManualIDController.state(app); if now<state.clickUntil, return; end
            item=[]; try, item=event.InteractionInformation.Item; catch, end
            if ~isempty(item), Program.GUI.ManualIDController.accept(app,item,true); end
        end
        function accept(app,index,mouse)
            if nargin<3, mouse=false; end
            state=Program.GUI.ManualIDController.state(app);
            if index<1 || index>numel(state.rows), return; end
            context=Program.GUI.ManualIDService.context(app,app.selected_neuron);
            if ~isequal(state.context,context)
                Program.GUI.ManualIDController.message(app,'Context changed. Review the draft before choosing an ID.'); return;
            end
            row=state.rows(index);
            if strcmp(row.kind,'group')
                state.expanded=row.token; state.active=0; state.status='';
                Program.GUI.ManualIDController.put(app,state); Program.GUI.ManualIDController.refresh(app);
                Program.GUI.ManualIDController.noteFocus(app,'input');
                ui=Program.GUI.ManualIDController.ui(app); focus(ui.input); return;
            end
            parsed=Annotations.Catalog.parse(state.text,context.sex,state.allNames);
            raw=Program.GUI.ManualIDController.withModifiers(row.token,parsed);
            if strcmp(row.kind,'keep'), draft=Annotations.Catalog.stageGroup(raw,context.sex,state.allNames);
            else, draft=Annotations.Catalog.parse(raw,context.sex,state.allNames); end
            if ~draft.valid, Program.GUI.ManualIDController.message(app,draft.message); return; end
            state.text=raw; state.staged=draft; state.parsed=draft; state.dirty=true;
            if ~strcmp(row.kind,'keep'), state.expanded=''; end
            state.generation=state.generation+1; state.operation=''; state.status='Draft · Assign to save';
            Program.GUI.ManualIDController.put(app,Program.GUI.ManualIDController.stash(state));
            Program.GUI.ManualIDController.renderText(app,raw);
            Program.GUI.ManualIDController.describe(app,state);
            Program.GUI.ManualIDController.close(app,mouse);
            Program.GUI.ManualIDController.noteFocus(app,'input');
            ui=Program.GUI.ManualIDController.ui(app); focus(ui.input);
        end
        function handled=handleKey(app,event,object)
            handled=false; ui=Program.GUI.ManualIDController.ui(app); if isempty(ui), return; end
            if ~isequal(app.TabGroup.SelectedTab,app.NeuroPALIDTab), return; end
            key=lower(event.Key);
            shift=any(strcmpi(event.Modifier,'shift'));
            if strcmp(key,'tab'), Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID); end
            actions={ui.all,ui.clear,ui.undo};
            state=Program.GUI.ManualIDController.state(app);
            if nargin<3
                object=app.CELL_ID.CurrentObject;
                if strcmp(state.focusOwner,state.key)
                    if any(strcmp(state.focusRole,{'list','actions'})) && ...
                            (~state.open || strcmp(ui.panel.Visible,'off'))
                        handled=true; Program.GUI.ManualIDController.deferFocus(app,ui.input,'input'); return;
                    end
                    if strcmp(state.focusRole,'assign'), object=app.UserIDButton;
                    elseif strcmp(state.focusRole,'input'), object=ui.input;
                    elseif strcmp(state.focusRole,'list'), object=ui.list;
                    elseif strcmp(state.focusRole,'actions')
                        if state.focusAction<1 || state.focusAction>numel(actions), return; end
                        object=actions{state.focusAction};
                    elseif strcmp(state.focusRole,'other')
                        if strcmp(key,'tab') && ~isempty(state.focusBoundary)
                            state.focusOffset=state.focusOffset+1-2*shift;
                            Program.GUI.ManualIDController.put(app,state);
                            if state.focusOffset==0
                                handled=true;
                                if strcmp(state.focusBoundary,'assign'), target=app.UserIDButton;
                                else, target=ui.input; end
                                Program.GUI.ManualIDController.deferFocus(app,target,state.focusBoundary);
                            end
                        end
                        return;
                    end
                end
            end
            if isequal(object,app.UserIDButton)
                if strcmp(key,'tab')
                    if shift
                        handled=true; Program.GUI.ManualIDController.deferFocus(app,ui.input,'input');
                    else, Program.GUI.ManualIDController.leaveEditor(app,'assign',1); end
                elseif any(strcmp(key,{'return','enter','space'}))
                    handled=true; Program.GUI.ManualIDController.beginKeyGesture(app,key);
                    gesture=Program.GUI.ManualIDController.consumeGesture(app,[]);
                    Program.GUI.ManualIDController.assign(app,app.selected_neuron,[],'assign',gesture);
                end
                return;
            elseif isa(object,'matlab.ui.control.Button')
                index=find(cellfun(@(button) isequal(object,button),actions),1);
                if isempty(index), return; end
                % Keep native button activation; only route this popup's Tab cycle.
                handled=true;
                if strcmp(key,'tab')
                    index=index+1-2*shift;
                    if index<1 || index>numel(actions)
                        Program.GUI.ManualIDController.deferFocus(app,ui.input,'input');
                    else
                        Program.GUI.ManualIDController.deferFocus(app,actions{index},'actions');
                    end
                elseif strcmp(key,'escape')
                    Program.GUI.ManualIDController.close(app);
                    Program.GUI.ManualIDController.deferFocus(app,ui.input,'input');
                end
                return;
            end
            if ~isequal(object,ui.input) && ~Program.GUI.ManualIDController.inside(object,ui.panel), return; end
            % This flag gates the previous image shortcut callback, not native keys.
            handled=true;
            state=Program.GUI.ManualIDController.state(app);
            modified=any(ismember(lower(string(event.Modifier)),["control","command","meta"]));
            switch key
                case {'return','enter'}
                    handled=true;
                    if modified, return;
                    elseif state.open && state.active>0
                        Program.GUI.ManualIDController.accept(app,state.active);
                    else
                        draft=Program.GUI.ManualIDController.capture(app);
                        if ~draft.valid, Program.GUI.ManualIDController.message(app,draft.message);
                        else, Program.GUI.ManualIDController.message(app,'Draft ready · Assign to save.'); end
                    end
                case {'uparrow','downarrow'}
                    handled=true;
                    if modified && strcmp(key,'downarrow')
                        if ~state.open, Program.GUI.ManualIDController.open(app); end
                        Program.GUI.ManualIDController.deferFocus(app,ui.all,'actions'); return;
                    end
                    if ~state.open, Program.GUI.ManualIDController.open(app); return; end
                    step=1; if strcmp(key,'uparrow'), step=-1; end
                    active=state.active+step;
                    if state.active==0 && step<0, active=numel(state.rows); end
                    active=max(1,min(numel(state.rows),active));
                    if isempty(state.rows), active=0; end
                    Program.GUI.ManualIDController.highlight(app,active);
                case 'escape'
                    handled=true;
                    if state.open, Program.GUI.ManualIDController.close(app);
                    else
                        if isKey(state.drafts,state.key), remove(state.drafts,state.key); end
                        record=Program.GUI.ManualIDService.record(app,app.selected_neuron);
                        state.context=Program.GUI.ManualIDService.context(app,app.selected_neuron);
                        state.baseline=Program.GUI.ManualIDController.recordText(record);
                        state.text=state.baseline; state.dirty=false;
                        state.expanded=''; state.active=0; state.status='';
                        state.staged=Program.GUI.ManualIDController.baselineDraft(record,state.context.sex);
                        state.parsed=Annotations.Catalog.parse(state.text,state.context.sex,state.allNames);
                        state.generation=state.generation+1; state.operation='';
                        Program.GUI.ManualIDController.put(app,state);
                        Program.GUI.ManualIDController.renderText(app,state.text);
                        Program.GUI.ManualIDController.describe(app,state);
                    end
                case 'tab'
                    Program.GUI.ManualIDController.close(app);
                    if ~shift
                        handled=true; Program.GUI.ManualIDController.deferFocus(app,app.UserIDButton,'assign');
                    else
                        handled=false; Program.GUI.ManualIDController.leaveEditor(app,'input',-1);
                    end
            end
        end
        function windowKey(app,src,event)
            Program.GUI.ManualIDController.installRelease(app);
            if ~Program.GUI.ManualIDController.handleKey(app,event)
                if isequal(app.TabGroup.SelectedTab,app.NeuroPALIDTab) && ...
                        any(strcmpi(event.Key,{'return','enter','space'}))
                    % Native button activation can arrive without tracked editor focus.
                    Program.GUI.ManualIDController.beginKeyGesture(app,lower(event.Key));
                end
                state=Program.GUI.ManualIDController.state(app);
                Program.GUI.ManualIDController.invoke(state.previousKey,src,event);
            end
        end
        function installRelease(app)
            if isappdata(app.CELL_ID,'manual_id_release_installed'), return; end
            state=Program.GUI.ManualIDController.state(app);
            state.previousRelease=app.CELL_ID.WindowKeyReleaseFcn;
            Program.GUI.ManualIDController.put(app,state);
            app.CELL_ID.WindowKeyReleaseFcn=@(src,event) Program.GUI.ManualIDController.windowRelease(app,src,event);
            setappdata(app.CELL_ID,'manual_id_release_installed',true);
        end
        function windowRelease(app,src,event)
            state=Program.GUI.ManualIDController.state(app);
            if strcmpi(state.heldAssignmentKey,event.Key), state.heldAssignmentKey=''; end
            Program.GUI.ManualIDController.put(app,state);
            Program.GUI.ManualIDController.invoke(state.previousRelease,src,event);
        end
        function windowMouse(app,src,event)
            Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
            state=Program.GUI.ManualIDController.state(app); ui=Program.GUI.ManualIDController.ui(app);
            object=app.CELL_ID.CurrentObject;
            if isequal(object,app.UserIDButton)
                Program.GUI.ManualIDController.noteFocus(app,'assign');
                Program.GUI.ManualIDController.beginMouseGesture(app,app.CELL_ID.SelectionType);
            elseif ~isempty(ui) && isequal(object,ui.input)
                Program.GUI.ManualIDController.noteFocus(app,'input');
            elseif ~isempty(ui) && isequal(object,ui.list)
                Program.GUI.ManualIDController.noteFocus(app,'list');
            elseif ~isempty(ui) && Program.GUI.ManualIDController.inside(object,ui.panel)
                actions={ui.all,ui.clear,ui.undo};
                if any(cellfun(@(button) isequal(object,button),actions))
                    Program.GUI.ManualIDController.noteFocus(app,'actions',object);
                else
                    Program.GUI.ManualIDController.noteFocus(app,'input'); focus(ui.input);
                end
            else, Program.GUI.ManualIDController.noteFocus(app,'other');
            end
            if ~isempty(ui)
                if isequal(object,ui.input), Program.GUI.ManualIDController.open(app);
                elseif ~Program.GUI.ManualIDController.inside(object,ui.panel), Program.GUI.ManualIDController.close(app); end
            end
            Program.GUI.ManualIDController.invoke(state.previousMouse,src,event);
        end
        function resized(app,src,event)
            state=Program.GUI.ManualIDController.state(app); Program.GUI.ManualIDController.close(app);
            Program.GUI.ManualIDController.invoke(state.previousResize,src,event);
        end
        function tabChanged(app,src,event)
            state=Program.GUI.ManualIDController.state(app); Program.GUI.ManualIDController.close(app);
            Program.GUI.ManualIDController.invoke(state.previousTab,src,event);
        end
        function toggleAll(app)
            state=Program.GUI.ManualIDController.state(app);
            state.allNames=~state.allNames; state.cacheKey=''; state.expanded=''; state.active=0; state.status='';
            Program.GUI.ManualIDController.put(app,state); Program.GUI.ManualIDController.refresh(app);
            Program.GUI.ManualIDController.noteFocus(app,'input');
            ui=Program.GUI.ManualIDController.ui(app); focus(ui.input);
        end
        function message(app,text)
            state=Program.GUI.ManualIDController.state(app); state.status=char(string(text));
            Program.GUI.ManualIDController.put(app,state); Program.GUI.ManualIDController.open(app);
            ui=Program.GUI.ManualIDController.ui(app);
            if ~isempty(ui)
                ui.input.Tooltip=state.status;
                if strcmp(ui.input.Enable,'on')
                    Program.GUI.ManualIDController.noteFocus(app,'input'); focus(ui.input);
                end
            end
        end
        function position(app)
            ui=Program.GUI.ManualIDController.ui(app); if isempty(ui), return; end
            anchor=getpixelposition(ui.input,true); bounds=app.CELL_ID.InnerPosition;
            width=min(max(320,anchor(3)),max(120,bounds(3)-12)); height=min(290,max(100,bounds(4)-12));
            left=max(6,min(anchor(1),bounds(3)-width-6)); bottom=anchor(2)-height-4;
            if bottom<6, bottom=min(bounds(4)-height-6,anchor(2)+anchor(4)+4); end
            ui.panel.Position=[left,max(6,bottom),width,height];
        end
        function startResizeWatcher(app)
            window=app.CELL_ID;
            watch=getappdata(window,'manual_id_popup_resize_timer');
            if ~isempty(watch) && isvalid(watch.timer), return; end
            ui=Program.GUI.ManualIDController.ui(app);
            clock=timer('ExecutionMode','fixedSpacing','Period',.1,'BusyMode','drop', ...
                'Name','NeuroPAL ID popup bounds','Tag','ManualIDPopupBounds', ...
                'TimerFcn',@(src,~) Program.GUI.ManualIDController.checkResize(app,src), ...
                'ErrorFcn',@(src,~) Program.GUI.ManualIDController.disposeTimer(src), ...
                'StopFcn',@(src,~) Program.GUI.ManualIDController.disposeTimer(src));
            watch=struct('timer',clock,'bounds',window.InnerPosition, ...
                'anchor',getpixelposition(ui.input,true));
            setappdata(window,'manual_id_popup_resize_timer',watch);
            start(clock);
        end
        function checkResize(app,clock)
            if ~isvalid(app) || ~isvalid(app.CELL_ID)
                Program.GUI.ManualIDController.disposeTimer(clock); return;
            end
            try
                state=Program.GUI.ManualIDController.state(app);
                watch=getappdata(app.CELL_ID,'manual_id_popup_resize_timer');
                ui=Program.GUI.ManualIDController.ui(app);
                if ~state.open || isempty(watch)
                    Program.GUI.ManualIDController.stopResizeWatcher(app.CELL_ID); return;
                end
                if ~isequal(watch.bounds,app.CELL_ID.InnerPosition) || ...
                        ~isequal(watch.anchor,getpixelposition(ui.input,true))
                    Program.GUI.ManualIDController.close(app);
                end
            catch
                Program.GUI.ManualIDController.disposeTimer(clock);
            end
        end
        function stopResizeWatcher(window)
            if isempty(window) || ~isvalid(window), return; end
            watch=getappdata(window,'manual_id_popup_resize_timer');
            setappdata(window,'manual_id_popup_resize_timer',[]);
            if ~isempty(watch), Program.GUI.ManualIDController.disposeTimer(watch.timer); end
        end
        function disposeTimer(clock)
            if isempty(clock), return; end
            % A completed single-shot callback may already be deleting its timer.
            try
                if ~isvalid(clock), return; end
                clock.StopFcn=[]; clock.ErrorFcn=[];
                if strcmp(clock.Running,'on'), stop(clock); end
                delete(clock);
            catch
                try, delete(clock); catch, end
            end
        end
        function orderEditor(app)
            ui=Program.GUI.ManualIDController.ui(app);
            parent=ui.input.Parent;
            if ~isequal(parent,app.UserIDButton.Parent), return; end
            % Native Tab follows the editor's forward child order.
            parent.Children=[ui.input;app.UserIDButton];
        end
        function noteFocus(app,role,target)
            state=Program.GUI.ManualIDController.state(app);
            state.focusRole=role; state.focusOwner=state.key;
            state.focusAction=0; state.focusBoundary=''; state.focusOffset=0;
            if strcmp(role,'actions') && nargin>=3
                ui=Program.GUI.ManualIDController.ui(app);
                actions={ui.all,ui.clear,ui.undo};
                index=find(cellfun(@(button) isequal(target,button),actions),1);
                if ~isempty(index), state.focusAction=index; end
            end
            if ~isempty(app.selected_neuron)
                try
                    context=Program.GUI.ManualIDService.context(app,app.selected_neuron);
                    state.focusOwner=Program.GUI.ManualIDController.ownerKey(context);
                catch
                    % A closing source cannot acquire a new editor focus owner.
                end
            end
            Program.GUI.ManualIDController.put(app,state);
        end
        function leaveEditor(app,boundary,offset)
            Program.GUI.ManualIDController.noteFocus(app,'other');
            state=Program.GUI.ManualIDController.state(app);
            state.focusBoundary=boundary; state.focusOffset=offset;
            if ~isempty(state.pendingGesture) && strcmp(state.pendingGesture.origin,'keyboard-focus')
                state.pendingGesture=[];
            end
            Program.GUI.ManualIDController.put(app,state);
        end
        function deferFocus(app,target,role)
            Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
            Program.GUI.ManualIDController.readVisible(app);
            Program.GUI.ManualIDController.noteFocus(app,role,target);
            state=Program.GUI.ManualIDController.state(app);
            if strcmp(role,'assign')
                state.pendingGesture=Program.GUI.ManualIDController.captureGesture(app,'keyboard-focus');
                if isempty(state.heldAssignmentKey), state.keyGesture=state.pendingGesture; end
                Program.GUI.ManualIDController.put(app,state);
                % Native Tab reaches Assign in the editor's own child order.
                return;
            elseif ~isempty(state.pendingGesture) && strcmp(state.pendingGesture.origin,'keyboard-focus')
                state.pendingGesture=[]; Program.GUI.ManualIDController.put(app,state);
            end
            owner=state.focusOwner; generation=state.generation;
            % Popup routes restore owned focus after native key handling finishes.
            clock=timer('ExecutionMode','singleShot','StartDelay',.01, ...
                'Tag','ManualIDDeferredFocus','BusyMode','drop', ...
                'TimerFcn',@(src,~) Program.GUI.ManualIDController.finishFocus(app,target,owner,generation,role,src), ...
                'ErrorFcn',@(src,~) Program.GUI.ManualIDController.disposeTimer(src), ...
                'StopFcn',@(src,~) Program.GUI.ManualIDController.disposeTimer(src));
            setappdata(app.CELL_ID,'manual_id_focus_timer',clock); start(clock);
        end
        function finishFocus(app,target,owner,generation,role,clock)
            if ~isvalid(app) || ~isvalid(app.CELL_ID) || ~isvalid(target)
                Program.GUI.ManualIDController.disposeTimer(clock); return;
            end
            current=getappdata(app.CELL_ID,'manual_id_focus_timer');
            if ~isequal(current,clock)
                Program.GUI.ManualIDController.disposeTimer(clock); return;
            end
            setappdata(app.CELL_ID,'manual_id_focus_timer',[]);
            state=Program.GUI.ManualIDController.state(app);
            if strcmp(state.key,owner) && strcmp(state.focusOwner,owner) && state.generation==generation && strcmp(state.focusRole,role) && ...
                    isequal(app.TabGroup.SelectedTab,app.NeuroPALIDTab) && strcmp(target.Enable,'on')
                focus(target);
            end
        end
        function stopFocusTimer(window)
            if isempty(window) || ~isvalid(window), return; end
            clock=getappdata(window,'manual_id_focus_timer');
            setappdata(window,'manual_id_focus_timer',[]);
            if ~isempty(clock), Program.GUI.ManualIDController.disposeTimer(clock); end
        end
        function disposeWatchers(window)
            Program.GUI.ManualIDController.stopResizeWatcher(window);
            Program.GUI.ManualIDController.stopFocusTimer(window);
        end
        function value=inside(object,parent)
            value=false;
            while ~isempty(object) && isvalid(object)
                if isequal(object,parent), value=true; return; end
                if ~isprop(object,'Parent'), return; end
                object=object.Parent;
            end
        end
        function invoke(callback,src,event)
            if isempty(callback), return; end
            if isa(callback,'function_handle'), callback(src,event);
            elseif iscell(callback), feval(callback{1},src,event,callback{2:end});
            elseif ischar(callback), evalin('base',callback); end
        end
        function renderText(app,text)
            app.IDEditField.Value=char(string(text)); ui=Program.GUI.ManualIDController.ui(app);
            if ~isempty(ui)
                ui.input.Value=char(string(text));
                setappdata(ui.input,'manual_id_native_value',ui.input.Value);
            end
        end
        function readVisible(app)
            ui=Program.GUI.ManualIDController.ui(app);
            if isempty(ui) || strcmp(ui.input.Enable,'off'), return; end
            previous=getappdata(ui.input,'manual_id_native_value');
            if isempty(previous), previous=''; end
            % ValueChanging owns in-flight text while the native Value still lags.
            if ~strcmp(ui.input.Value,previous)
                Program.GUI.ManualIDController.edited(app,ui.input.Value,false);
            end
        end
        function describe(app,state)
            ui=Program.GUI.ManualIDController.ui(app); if isempty(ui), return; end
            label='Type an ID. Enter selects; Tab focuses Assign. Click Assign or press Enter/Space there to save. Down opens suggestions; Ctrl+Down focuses popup actions.';
            if state.dirty, label=['Unassigned draft. ' label];
            elseif ~isempty(state.staged) && strcmp(state.staged.kind,'unresolved_set')
                label=['Saved family membership (' state.staged.certainty '); individual member unresolved. ' label];
            elseif ~isempty(state.staged) && strcmp(state.staged.certainty,'unspecified')
                label=['Saved annotation; certainty unspecified. Choose an individual explicitly to confirm it. ' label];
            elseif ~isempty(state.staged) && strcmp(state.staged.certainty,'tentative')
                label=['Saved tentative identity hypothesis. ' label];
            elseif ~isempty(state.baseline), label=['Saved annotation. ' label];
            elseif ~isempty(state.text), label=['Provisional model prefill; not assigned. ' label]; end
            if ~isempty(state.status), label=[state.status ' ' label]; end
            ui.input.Tooltip=label;
        end
        function text=reviewMessage(record)
            text='';
            if isfield(record,'issue') && ~isempty(record.issue)
                text=['Needs review · ' record.issue];
            elseif isfield(record,'conflicts') && ~isempty(record.conflicts)
                text=['Hypothesis conflicts with confirmed ' strjoin(record.conflicts,', ') '.'];
            end
        end
        function state=stash(state)
            if isempty(state.key), return; end
            if state.dirty
                state.drafts(state.key)=struct('text',state.text,'staged',state.staged, ...
                    'context',state.context,'generation',state.generation);
            elseif isKey(state.drafts,state.key), remove(state.drafts,state.key); end
        end
        function value=dirty(app)
            state=Program.GUI.ManualIDController.state(app); value=state.dirty || state.drafts.Count>0;
        end
        function invalidate(app)
            state=Program.GUI.ManualIDController.state(app);
            state.drafts=containers.Map('KeyType','char','ValueType','any');
            state.key=''; state.context=struct(); state.dirty=false; state.text='';
            state.staged=[]; state.parsed=[]; state.cacheKey=''; state.generation=state.generation+1;
            state.pendingGesture=[]; state.mouseGesture=[]; state.keyGesture=[];
            state.heldAssignmentKey=''; state.lastCommittedGesture='';
            state.focusRole=''; state.focusOwner=''; state.focusAction=0;
            state.focusBoundary=''; state.focusOffset=0;
            Program.GUI.ManualIDController.stopFocusTimer(app.CELL_ID);
            Program.GUI.ManualIDController.put(app,state); Program.GUI.ManualIDController.close(app);
        end
        function key=ownerKey(context)
            key=[char(string(context.source_id)) ':' char(string(context.owner_id))];
        end
        function gesture=captureGesture(app,origin)
            if nargin<2, origin='explicit'; end
            Program.GUI.ManualIDController.readVisible(app);
            state=Program.GUI.ManualIDController.state(app);
            gesture=struct('owner_key',state.key,'context',state.context, ...
                'generation',state.generation,'index',app.selected_neuron, ...
                'operation_id',char(java.util.UUID.randomUUID()),'origin',origin);
        end
        function beginMouseGesture(app,selection)
            Program.GUI.ManualIDController.readVisible(app);
            state=Program.GUI.ManualIDController.state(app);
            if strcmp(selection,'open') && ~isempty(state.mouseGesture)
                gesture=state.mouseGesture;
            else, gesture=Program.GUI.ManualIDController.captureGesture(app,'mouse'); end
            state.mouseGesture=gesture; state.pendingGesture=gesture;
            Program.GUI.ManualIDController.put(app,state);
        end
        function beginKeyGesture(app,key)
            Program.GUI.ManualIDController.readVisible(app);
            state=Program.GUI.ManualIDController.state(app);
            if strcmp(state.heldAssignmentKey,key) && ~isempty(state.keyGesture)
                gesture=state.keyGesture;
            else, gesture=Program.GUI.ManualIDController.captureGesture(app,'keyboard'); end
            state.heldAssignmentKey=key; state.keyGesture=gesture; state.pendingGesture=gesture;
            Program.GUI.ManualIDController.put(app,state);
        end
        function gesture=consumeGesture(app,event)
            state=Program.GUI.ManualIDController.state(app); gesture=state.pendingGesture;
            if ~isempty(gesture)
                state.pendingGesture=[]; Program.GUI.ManualIDController.put(app,state); return;
            end
            if isa(event,'matlab.ui.eventdata.ButtonPushedData')
                if ~isempty(state.keyGesture) && (~isempty(state.heldAssignmentKey) || ...
                        strcmp(state.keyGesture.origin,'keyboard-focus')), gesture=state.keyGesture;
                elseif ~isempty(state.mouseGesture)
                    gesture=state.mouseGesture;
                else
                    gesture=struct('owner_key','','context',struct(),'generation',-1, ...
                        'index',[],'operation_id','uncaptured-native-gesture','origin','native');
                end
            end
        end
        function sex=sex(app)
            sex=app.SexDropDown.Value;
            if isfield(app.worm,'sex'), sex=app.worm.sex; end
        end
        function text=recordText(record)
            text='';
            if isempty(record) || ~isfield(record,'kind') || strcmp(record.kind,'unassigned'), return; end
            if strcmp(record.kind,'classification') && isfield(record,'classification_token')
                token=record.classification_token;
            elseif strcmp(record.kind,'legacy_issue') && isfield(record,'provenance')
                text=Program.GUI.ManualIDController.legacyText(record.provenance); return;
            elseif strcmp(record.kind,'unresolved_set')
                if ~isempty(record.group), token=record.group; else, token=strjoin(record.candidates,' / '); end
            elseif numel(record.candidates)==1, token=record.candidates{1};
            elseif isfield(record,'token'), token=record.token;
            else, return; end
            text=Program.GUI.ManualIDController.withModifiers(token,record);
        end
        function draft=baselineDraft(record,sex)
            draft=[];
            if ~any(strcmp(record.kind,{'individual','unresolved_set','classification'})), return; end
            draft=record; draft.valid=true; draft.message=''; draft.requires_staging=false;
            draft.context_exception_required=false;
            if strcmp(record.kind,'classification'), draft.token=record.classification_token;
            elseif strcmp(record.kind,'unresolved_set'), draft.token=record.group;
            else, draft.token=record.candidates{1}; end
            for i=1:numel(record.candidates)
                info=Annotations.Catalog.lookup(record.candidates{i},sex);
                draft.context_exception_required=draft.context_exception_required || ~info.applicable;
            end
        end
        function text=legacyText(provenance)
            text='';
            for field={'raw','raw_annotation','original_annotation'}
                if isfield(provenance,field{1}) && (ischar(provenance.(field{1})) || isstring(provenance.(field{1})))
                    text=char(string(provenance.(field{1}))); return;
                end
            end
        end
        function text=withModifiers(token,parsed)
            text=char(string(token));
            if isfield(parsed,'attributes') && isfield(parsed.attributes,'on_off')
                value=parsed.attributes.on_off;
                if isscalar(value) && ~isnan(value)
                    if value, text=[text '-ON']; else, text=[text '-OFF']; end
                end
            end
            if isfield(parsed,'certainty') && strcmp(parsed.certainty,'tentative'), text=[text '?']; end
            if isfield(parsed,'attributes') && isfield(parsed.attributes,'emphasized') && parsed.attributes.emphasized
                text=[text '!'];
            end
        end
    end
end
