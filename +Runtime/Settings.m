classdef Settings
    %SETTINGS Configure dependencies without exposing shell environment variables.
    methods (Static)
        function install(app)
            menu=findall(app.CELL_ID,'Tag','RuntimeToolsMenu');
            if isempty(menu)
                menu=uimenu(app.CELL_ID,'Text','Tools','Tag','RuntimeToolsMenu');
                uimenu(menu,'Text','Models & runtimes…','MenuSelectedFcn',@(~,~) Runtime.Settings.open(app));
            end
        end
        function window = open(app,id)
            if nargin<2, id='recording_io'; end
            id=Runtime.Catalog.canonical(id);
            window=getappdata(app.CELL_ID,'runtime_settings_window');
            if isempty(window) || ~isvalid(window)
                window=uifigure('Name','Models & runtimes','Position',[180 220 790 460]);
                window.CloseRequestFcn=@(src,~) Runtime.Settings.close(src);
                grid=uigridlayout(window,[5 1]); grid.RowHeight={32,35,'1x',32,32};
                entries=Runtime.Catalog.all();
                choice=uidropdown(grid,'Items',{entries.name},'ItemsData',{entries.id},'Tag','RuntimeCapability');
                status=uilabel(grid,'Text','','WordWrap','on','Tag','RuntimeStatus');
                table=uitable(grid,'ColumnName',{'Component','Location'},'ColumnEditable',[false true], ...
                    'RowName',{},'ColumnWidth',{140,'auto'},'Tag','RuntimePaths');
                buttons=uigridlayout(grid,[1 5]); buttons.Padding=[0 0 0 0];
                buttons.ColumnWidth={105,145,105,105,'1x'};
                browse=uibutton(buttons,'Text','Choose…','ButtonPushedFcn',@(~,~) Runtime.Settings.browse(window));
                detected=uibutton(buttons,'Text','Use detected','ButtonPushedFcn',@(~,~) Runtime.Settings.refresh(window,true));
                check=uibutton(buttons,'Text','Check','Tag','RuntimeCheck','ButtonPushedFcn',@(~,~) Runtime.Settings.check(window,false));
                apply=uibutton(buttons,'Text','Apply','Tag','RuntimeApply','ButtonPushedFcn',@(~,~) Runtime.Settings.check(window,true));
                close=uibutton(buttons,'Text','Close','ButtonPushedFcn',@(~,~) set(window,'Visible','off'));
                actions=uigridlayout(grid,[1 6]); actions.Padding=[0 0 0 0]; actions.ColumnWidth={145,110,110,90,125,'1x'};
                uim=uibutton(actions,'Text','Import previous setup…','ButtonPushedFcn',@(~,~) Runtime.Settings.importLegacy(window));
                forget=uibutton(actions,'Text','Forget selection','ButtonPushedFcn',@(~,~) Runtime.Settings.forget(window));
                reset=uibutton(actions,'Text','Reset settings…','ButtonPushedFcn',@(~,~) Runtime.Settings.reset(window));
                details=uibutton(actions,'Text','Details…','ButtonPushedFcn',@(~,~) Runtime.Settings.details(window));
                install=uibutton(actions,'Text','Install / update…','ButtonPushedFcn',@(~,~) Runtime.Distribution.open(window));
                resources=uibutton(actions,'Text','Resources…','ButtonPushedFcn',@(~,~) Runtime.Settings.resources(window));
                controls=struct('app',app,'choice',choice,'status',status,'table',table,'checking',false, ...
                    'buttons',[browse detected check apply close uim forget reset details install resources]);
                setappdata(window,'runtime_controls',controls);
                choice.ValueChangedFcn=@(~,~) Runtime.Settings.refresh(window,false);
                table.CellEditCallback=@(~,~) Runtime.Settings.changed(window);
                setappdata(app.CELL_ID,'runtime_settings_window',window);
                addlistener(app.CELL_ID,'ObjectBeingDestroyed',@(~,~) Runtime.Settings.dispose(window));
            end
            controls=getappdata(window,'runtime_controls');
            if controls.checking, figure(window); return; end
            controls.choice.Value=id; Runtime.Settings.refresh(window,false);
            window.Visible='on'; figure(window);
        end
        function refresh(window,detected)
            c=getappdata(window,'runtime_controls'); if c.checking, return; end
            id=c.choice.Value; entry=Runtime.Catalog.find(id);
            setappdata(window,'runtime_report',[]);
            try
                Runtime.Configuration.read();
                [profile,selected]=Runtime.Discovery.profile(id);
                if detected
                    found=Runtime.Discovery.installed();
                    if isfield(found,id), profile=found.(id);
                    else, c.status.Text='No packaged installation was detected. Choose an existing installation.'; return; end
                end
                fields=entry.fields; data=cell(numel(fields),2);
                for i=1:numel(fields), data(i,:)={Runtime.Settings.label(fields{i}),profile.(fields{i})}; end
                c.table.Data=data; setappdata(window,'runtime_fields',fields);
                setappdata(window,'runtime_draft',profile);
                if selected, c.status.Text='Saved installation. Check validates it; Apply validates and saves changes.';
                elseif any(structfun(@(v) ~isempty(v),rmfield(profile,'origin')))
                    c.status.Text='Installation detected. Check or Apply to validate it.';
                else, c.status.Text='Choose an existing installation. No settings have been changed.'; end
                if isempty(fields), c.status.Text='This method uses MATLAB. Check verifies its prerequisites.'; end
            catch ME
                c.status.Text=ME.message; c.table.Data=cell(0,2);
                setappdata(window,'runtime_fields',{}); setappdata(window,'runtime_draft',Runtime.Catalog.profile());
            end
        end
        function value = draft(window)
            c=getappdata(window,'runtime_controls'); value=getappdata(window,'runtime_draft');
            if isempty(value), value=Runtime.Catalog.profile(); end
            fields=getappdata(window,'runtime_fields');
            for i=1:numel(fields), value.(fields{i})=strtrim(char(string(c.table.Data{i,2}))); end
        end
        function browse(window)
            c=getappdata(window,'runtime_controls'); fields=getappdata(window,'runtime_fields');
            if isempty(fields), return; end
            row=1;
            if ~isempty(c.table.Selection), row=c.table.Selection(1); end
            row=min(max(row,1),numel(fields)); key=fields{row};
            if any(strcmp(key,{'bundle','source','checkpoint'}))
                selected=uigetdir('',sprintf('Choose %s',Runtime.Settings.label(key)));
            else
                [file,folder]=uigetfile({'*.*','All files'},sprintf('Choose %s',Runtime.Settings.label(key)));
                if isequal(file,0), return; end
                selected=fullfile(folder,file);
            end
            if isequal(selected,0), return; end
            data=c.table.Data; data{row,2}=selected; c.table.Data=data;
            Runtime.Settings.changed(window);
        end
        function changed(window)
            setappdata(window,'runtime_report',[]);
            c=getappdata(window,'runtime_controls'); c.status.Text='Not saved. Apply checks this installation before replacing the saved selection.';
        end
        function check(window,save)
            c=getappdata(window,'runtime_controls'); if c.checking, return; end
            try
                Program.HeavyJob.assertIdle();
            catch ME
                c.status.Text=ME.message; return;
            end
            profile=Runtime.Settings.draft(window); id=c.choice.Value;
            c.checking=true; setappdata(window,'runtime_controls',c);
            setappdata(window,'runtime_cancel',false);
            c.choice.Enable='off'; c.table.Enable='off'; set(c.buttons,'Enable','off');
            progress=uiprogressdlg(window,'Title','Checking installation','Message','Checking dependencies and loading selected models…', ...
                'Indeterminate','on','Cancelable','on');
            cleanup=onCleanup(@() Runtime.Settings.finish(window,progress));
            try
                report=Runtime.Resolver.inspect(id,profile,true,@() ~isvalid(progress) || progress.CancelRequested || ...
                    ~isvalid(window) || isequal(getappdata(window,'runtime_cancel'),true));
                if ~isvalid(window), return; end
                setappdata(window,'runtime_report',report);
                if ~report.ready, c.status.Text=[report.status ': ' report.summary]; return; end
                if save
                    Runtime.Configuration.update(id,profile);
                    c.status.Text='Ready. Installation saved for subsequent operations and app launches.';
                else, c.status.Text='Check passed. Click Apply to save this installation.'; end
            catch ME
                if isvalid(window) && isvalid(c.status), c.status.Text=ME.message; end
            end
        end
        function finish(window,progress)
            if isvalid(progress), close(progress); end
            if ~isvalid(window), return; end
            c=getappdata(window,'runtime_controls'); c.checking=false; setappdata(window,'runtime_controls',c);
            c.choice.Enable='on'; c.table.Enable='on'; set(c.buttons,'Enable','on');
        end
        function importLegacy(window)
            c=getappdata(window,'runtime_controls'); found=Runtime.Discovery.legacyEnvironment(); id=c.choice.Value;
            if ~isfield(found,id), c.status.Text='No previous setup found for this capability.'; return; end
            p=found.(id); fields=getappdata(window,'runtime_fields'); data=c.table.Data;
            for i=1:numel(fields), data{i,2}=p.(fields{i}); end
            c.table.Data=data; setappdata(window,'runtime_draft',p); Runtime.Settings.changed(window);
        end
        function forget(window)
            c=getappdata(window,'runtime_controls');
            answer=uiconfirm(window,'Forget this selection? Installed files and experimental data will be kept.', ...
                'Forget installation','Options',{'Cancel','Forget'},'DefaultOption',1,'CancelOption',1);
            if strcmp(answer,'Forget')
                try, Runtime.Configuration.update(c.choice.Value,[]); Runtime.Settings.refresh(window,false);
                catch ME, c.status.Text=ME.message; end
            end
        end
        function reset(window)
            answer=uiconfirm(window,'Back up dependency settings and start again? Installed files and experimental data will be kept.', ...
                'Reset dependency settings','Options',{'Cancel','Reset'},'DefaultOption',1,'CancelOption',1);
            if strcmp(answer,'Reset')
                try, Runtime.Configuration.reset(); Runtime.Settings.refresh(window,false);
                catch ME, c=getappdata(window,'runtime_controls'); c.status.Text=ME.message; end
            end
        end
        function details(window)
            report=getappdata(window,'runtime_report');
            if isempty(report), text='Run Check to see the actual interpreter, package versions and model validation.';
            else, text=jsonencode(report,'PrettyPrint',true); end
            detail=uifigure('Name','Installation details','Position',[240 240 740 440]);
            addlistener(window,'ObjectBeingDestroyed',@(~,~) Runtime.Settings.dispose(detail));
            grid=uigridlayout(detail,[1 1]); uitextarea(grid,'Value',splitlines(string(text)),'Editable','off');
        end
        function resources(parent)
            try, config=Runtime.Configuration.read();
            catch ME, uialert(parent,ME.message,'Resource limits'); return; end
            names=fieldnames(config.resources);
            window=uifigure('Name','Resource limits','Position',[240 240 490 340]);
            addlistener(parent,'ObjectBeingDestroyed',@(~,~) Runtime.Settings.dispose(window));
            grid=uigridlayout(window,[2 1]); grid.RowHeight={'1x',32};
            data=cell(numel(names),2);
            for i=1:numel(names), data(i,:)={strrep(names{i},'_',' '),config.resources.(names{i})}; end
            table=uitable(grid,'Data',data,'ColumnName',{'Limit','Value'},'ColumnEditable',[false true],'RowName',{});
            uibutton(grid,'Text','Apply to subsequent operations','ButtonPushedFcn',@(~,~) Runtime.Settings.saveResources(window,table,names));
        end
        function saveResources(window,table,names)
            try
                value=struct();
                for i=1:numel(names), value.(names{i})=double(table.Data{i,2}); end
                Runtime.Configuration.update('resources',value); delete(window);
            catch ME
                uialert(window,ME.message,'Resource limits');
            end
        end
        function yes = ensure(app,id)
            progress=uiprogressdlg(app.CELL_ID,'Title','Checking setup', ...
                'Message','Checking the selected runtime and model…','Indeterminate','on','Cancelable','on');
            cleanup=onCleanup(@() Runtime.Installer.close(progress));
            report=Runtime.Resolver.inspect(id,struct(),false,@() ~isvalid(progress) || progress.CancelRequested);
            canceled=~isvalid(progress) || progress.CancelRequested;
            if isvalid(progress), close(progress); end
            yes=report.ready;
            if canceled, yes=false; return; end
            if yes, return; end
            answer=uiconfirm(app.CELL_ID,sprintf('%s needs setup.\n\n%s',report.name,report.summary), ...
                'Models & runtimes','Options',{'Configure…','Cancel'},'DefaultOption',1,'CancelOption',2);
            if strcmp(answer,'Configure…'), Runtime.Settings.open(app,id); end
        end
        function failure(app,ME,id)
            if nargin<3, id='recording_io'; end
            if strcmp(ME.identifier,'Runtime:CZISetup'), id='czi_reader'; end
            for i=1:numel(ME.cause)
                if strcmp(ME.cause{i}.identifier,'Runtime:CapabilityContext'), id=ME.cause{i}.message; end
            end
            answer=uiconfirm(app.CELL_ID,ME.message,'Models & runtimes', ...
                'Options',{'Configure…','Cancel'},'DefaultOption',1,'CancelOption',2);
            if strcmp(answer,'Configure…'), Runtime.Settings.open(app,id); end
        end
        function text = label(key)
            switch key
                case 'python', text='Python executable';
                case 'bundle', text='Model bundle';
                case 'source', text='GAT source folder';
                case 'checkpoint', text='Checkpoint folder';
                case 'weights', text='Weights file';
                otherwise, text=key;
            end
        end
        function dispose(window)
            if isvalid(window), delete(window); end
        end
        function close(window)
            c=getappdata(window,'runtime_controls');
            if c.checking, setappdata(window,'runtime_cancel',true);
            else, window.Visible='off'; end
        end
    end
end
