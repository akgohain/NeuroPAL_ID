classdef Distribution
    %DISTRIBUTION Install versioned models without changing application source.
    methods (Static)
        function window = open(parent)
            window=getappdata(parent,'model_distribution_window');
            if ~isempty(window) && isvalid(window), figure(window); return; end
            window=uifigure('Name','Install models & runtimes','Position',[230 230 800 440]);
            window.CloseRequestFcn=@(~,~) Runtime.Distribution.close(window);
            addlistener(parent,'ObjectBeingDestroyed',@(~,~) Runtime.Settings.dispose(window));
            grid=uigridlayout(window,[7 1]); grid.RowHeight={32,42,'1x',32,30,32,42};
            entries=Runtime.Catalog.all();
            choice=uidropdown(grid,'Items',{entries.name},'ItemsData',{entries.id},'Tag','DownloadCapability');
            status=uilabel(grid,'Text','','WordWrap','on','Tag','DownloadStatus');
            table=uitable(grid,'ColumnName',{'Model','Version','Download'},'ColumnEditable',false, ...
                'ColumnWidth',{170,'auto',120},'RowName',{},'Tag','DownloadModels');
            history=uigridlayout(grid,[1 2]); history.Padding=[0 0 0 0]; history.ColumnWidth={'1x',150};
            versions=uidropdown(history,'Items',{'No saved versions'},'Tag','InstalledModelVersions');
            restore=uibutton(history,'Text','Use saved version','ButtonPushedFcn',@(~,~) Runtime.Distribution.restore(window));
            options=uigridlayout(grid,[1 2]); options.Padding=[0 0 0 0];
            select=uicheckbox(options,'Text','Use after validation','Value',true);
            repair=uicheckbox(options,'Text','Rebuild runtime','Value',false);
            repair.Tooltip='Create a fresh Python environment; keep the previous one for running jobs and rollback.';
            buttons=uigridlayout(grid,[1 4]); buttons.Padding=[0 0 0 0];
            update=uibutton(buttons,'Text','Check updates','Tag','CheckModelUpdates','ButtonPushedFcn',@(~,~) Runtime.Distribution.updates(window));
            install=uibutton(buttons,'Text','Install','Tag','InstallModels','ButtonPushedFcn',@(~,~) Runtime.Distribution.install(window));
            local=uibutton(buttons,'Text','Local package…','ButtonPushedFcn',@(~,~) Runtime.Distribution.local(window));
            close=uibutton(buttons,'Text','Close','ButtonPushedFcn',@(~,~) Runtime.Distribution.close(window));
            message=uilabel(grid,'Text','','WordWrap','on','Tag','DownloadMessage');
            c=struct('parent',parent,'choice',choice,'status',status,'table',table,'versions',versions, ...
                'restore',restore,'select',select,'repair',repair,'message',message,'install',install, ...
                'busy',false,'buttons',[update install local close restore]);
            setappdata(window,'distribution_controls',c); setappdata(window,'distribution_cancel',false);
            setappdata(window,'distribution_catalog',Runtime.Distribution.catalogPath());
            setappdata(parent,'model_distribution_window',window);
            settings=getappdata(parent,'runtime_controls');
            if ~isempty(settings), choice.Value=settings.choice.Value; end
            choice.ValueChangedFcn=@(~,~) Runtime.Distribution.refresh(window);
            Runtime.Distribution.refresh(window);
        end
        function refresh(window)
            c=getappdata(window,'distribution_controls'); if c.busy, return; end
            try
                value=jsondecode(fileread(getappdata(window,'distribution_catalog')));
                c.status.Text=['Catalog: ' value.release_tag];
                model=''; id=c.choice.Value;
                if any(strcmp(id,{'detection_moe','ensemble'}))
                    model='moe';
                elseif strcmp(id,'anshita_gat')
                    model='gat';
                end
                if ~isempty(model)
                    pack=value.models.(model);
                    c.table.Data={upper(model),pack.version,sprintf('%.1f MB',pack.bytes/1e6)};
                else, c.table.Data=cell(0,3); end
                supported=Runtime.Distribution.supported(id);
                c.install.Enable=matlab.lang.OnOffSwitchState(supported && ismac && strcmp(computer('arch'),'maca64'));
                if supported
                    c.message.Text='Validated before use. Previous versions are retained. Runtime dependencies also download on first install.';
                    if ~ismac || ~strcmp(computer('arch'),'maca64')
                        c.message.Text='Managed downloads support Apple silicon macOS 14+. Choose an existing installation in Models & runtimes on other systems.';
                    end
                else
                    c.message.Text='No managed download is supplied for this method. Choose an existing installation in Models & runtimes.';
                end
                [labels,profiles]=Runtime.Distribution.history(id);
                setappdata(window,'distribution_history',profiles);
                if isempty(labels), c.versions.Items={'No saved versions'}; c.restore.Enable='off';
                else, c.versions.Items=labels; c.versions.Value=labels{1}; c.restore.Enable='on'; end
            catch ME
                c.message.Text=ME.message; c.install.Enable='off';
            end
        end
        function yes = supported(id)
            yes=any(strcmp(id,{'recording_io','recommendation','alignment','activity','zephir', ...
                'detection_moe','ensemble','anshita_gat','yolo'}));
        end
        function path = catalogPath()
            path=fullfile(Runtime.Configuration.appRoot(),'distribution','models','catalog.json');
            folder=fullfile(fileparts(Runtime.Configuration.location()),'model-catalogs');
            try
                saved=jsondecode(fileread(fullfile(folder,'selection.json')));
                if isempty(regexp(saved.sha256,'^[0-9a-f]{64}$','once')), return; end
                candidate=fullfile(folder,[saved.sha256 '.json']);
                fingerprint=Annotations.Store.fingerprint(candidate);
                if ~strcmp(fingerprint.sha256,saved.sha256), return; end
                value=jsondecode(fileread(candidate)); baseline=jsondecode(fileread(path));
                if value.adapter_api==baseline.adapter_api && strcmp(value.repository,baseline.repository) && ...
                        isequaln(orderfields(value.runtimes),orderfields(baseline.runtimes))
                    path=candidate;
                end
            catch
                % The source catalog remains available when the optional cache is absent.
            end
        end
        function [labels,profiles] = history(id)
            labels={}; profiles={}; roots=Runtime.Discovery.searchRoots(); paths={};
            for i=1:numel(roots)
                records=dir(fullfile(roots{i},'Methods-*','installation.json'));
                [~,order]=sort([records.datenum],'descend');
                for j=order, paths{end+1}=fullfile(records(j).folder,records(j).name); end
            end
            config=Runtime.Configuration.read();
            for i=1:min(100,numel(config.installations)), paths{end+1}=fullfile(config.installations{i},'installation.json'); end
            paths=unique(paths,'stable'); signatures={};
            for i=1:min(100,numel(paths))
                try
                    record=jsondecode(fileread(paths{i}));
                    if isfield(record,'profiles'), found=record.profiles;
                    else, found=Runtime.Discovery.fromLegacy(record.configuration); end
                    if ~isfield(found,id), continue; end
                    profile=Runtime.Catalog.profile(found.(id)); signature=jsonencode(profile);
                    if any(strcmp(signature,signatures)), continue; end
                    signatures{end+1}=signature; profiles{end+1}=profile;
                    [~,name]=fileparts(fileparts(paths{i}));
                    if isfield(record,'release_tag'), name=record.release_tag; end
                    labels{end+1}=sprintf('%s [%d]',name,numel(profiles));
                catch
                    % Ignore partial receipts; an install becomes usable after validation.
                end
            end
        end
        function updates(window)
            c=getappdata(window,'distribution_controls'); if c.busy, return; end
            Runtime.Distribution.busy(window,true);
            cleanup=onCleanup(@() Runtime.Distribution.finish(window,[]));
            c.message.Text='Checking published model releases…'; drawnow;
            try
                path=Runtime.Distribution.latest();
                if Runtime.Distribution.canceled(window,[]), return; end
                setappdata(window,'distribution_catalog',path);
                Runtime.Distribution.busy(window,false); Runtime.Distribution.refresh(window);
                c.message.Text='Latest compatible published models selected for installation. Current installations are unchanged.';
            catch ME
                if isvalid(window), c.message.Text=ME.message; end
            end
        end
        function path = latest()
            repository='akgohain/NeuroPAL_ID';
            options=weboptions('Timeout',15,'ContentType','json','UserAgent','NeuroPAL-ID-model-manager');
            baseline=jsondecode(fileread(fullfile(Runtime.Configuration.appRoot(),'distribution','models','catalog.json')));
            incompatible=false;
            for page=1:3
                url=sprintf('https://api.github.com/repos/%s/releases?per_page=30&page=%d',repository,page);
                releases=webread(url,options);
                for i=1:numel(releases)
                    release=releases(i); tag=char(release.tag_name);
                    if release.draft || release.prerelease || ~startsWith(tag,'models-'), continue; end
                    if isempty(regexp(tag,'^models-[A-Za-z0-9._-]{1,73}$','once')), continue; end
                    assets=release.assets;
                    if isempty(assets), continue; end
                    index=find(strcmp({assets.name},'model_catalog.json'));
                    if numel(index)~=1, continue; end
                    asset=assets(index);
                    if asset.size<=0 || asset.size>1048576 || ~isfield(asset,'digest') || ...
                            isempty(regexp(asset.digest,'^sha256:[0-9a-f]{64}$','once'))
                        error('Runtime:Catalog','The published model catalog has no verifiable checksum.');
                    end
                    folder=fullfile(fileparts(Runtime.Configuration.location()),'model-catalogs');
                    if ~isfolder(folder), mkdir(folder); end
                    temporary=[tempname(folder) '.json']; cleanup=onCleanup(@() Runtime.Configuration.remove(temporary));
                    download=sprintf('https://github.com/%s/releases/download/%s/model_catalog.json',repository,tag);
                    websave(temporary,download,weboptions('Timeout',20,'UserAgent','NeuroPAL-ID-model-manager'));
                    stat=dir(temporary); fingerprint=Annotations.Store.fingerprint(temporary);
                    if stat.bytes~=asset.size || ~strcmp(['sha256:' fingerprint.sha256],asset.digest)
                        error('Runtime:Catalog','The published model catalog failed checksum verification. Current installations were kept.');
                    end
                    value=jsondecode(fileread(temporary));
                    if ~strcmp(value.repository,repository) || ~strcmp(value.release_tag,tag)
                        error('Runtime:Catalog','The catalog does not match its repository/release.');
                    end
                    if value.schema_version~=1 || value.adapter_api~=baseline.adapter_api || ...
                            ~isequaln(orderfields(value.runtimes),orderfields(baseline.runtimes))
                        incompatible=true; continue;
                    end
                    path=fullfile(folder,[fingerprint.sha256 '.json']); movefile(temporary,path,'f');
                    fid=fopen(temporary,'w');
                    if fid<0, error('Runtime:Catalog','Cannot save the model catalog selection.'); end
                    writer=onCleanup(@() fclose(fid));
                    fwrite(fid,jsonencode(struct('sha256',fingerprint.sha256)),'char'); clear writer;
                    movefile(temporary,fullfile(folder,'selection.json'),'f'); return;
                end
                if numel(releases)<30, break; end
            end
            if incompatible
                error('Runtime:Catalog','Published models need a newer app/runtime adapter. Update the app or keep the current models.');
            end
            error('Runtime:Catalog','No compatible public model release has been published yet. Use Local package or choose an existing installation.');
        end
        function install(window)
            c=getappdata(window,'distribution_controls'); if c.busy, return; end
            if ~Runtime.Distribution.supported(c.choice.Value), return; end
            log=''; progress=[];
            try
                Program.HeavyJob.assertIdle(); Runtime.Configuration.read();
                Runtime.Distribution.busy(window,true);
                cleanup=onCleanup(@() Runtime.Distribution.finish(window,progress));
                root=fileparts(Runtime.Configuration.location()); folder=fullfile(root,'logs');
                if ~isfolder(folder), mkdir(folder); end
                key=char(java.util.UUID.randomUUID()); log=fullfile(folder,['models-' key '.log']);
                response=fullfile(folder,['models-' key '.json']);
                script=fullfile(Runtime.Configuration.appRoot(),'distribution','models','Install-Mac.command');
                arguments={'/bin/bash',script,'install','--catalog',getappdata(window,'distribution_catalog'), ...
                    '--capability',c.choice.Value,'--app',Runtime.Configuration.appRoot(),'--root',root, ...
                    '--registry',Runtime.Configuration.location(),'--response',response};
                if c.select.Value, arguments{end+1}='--activate'; end
                if c.repair.Value, arguments{end+1}='--rebuild-runtime'; end
                progress=uiprogressdlg(window,'Title','Installing models & runtimes','Message','Preparing the managed installer…', ...
                    'Indeterminate','on','Cancelable','on');
                progressCleanup=onCleanup(@() Runtime.Installer.close(progress));
                job=Program.HeavyJob.acquire('Installing models & runtimes'); release=onCleanup(@() delete(job));
                args=java.util.ArrayList;
                for i=1:numel(arguments), args.add(arguments{i}); end
                builder=java.lang.ProcessBuilder(args); Runtime.Environment.apply(builder);
                builder.environment().put('NEUROPAL_JOB_TOKEN',Program.HeavyJob.token());
                builder.environment().put('NEUROPAL_PARENT_PID',num2str(feature('getpid')));
                builder.redirectErrorStream(true); builder.redirectOutput(java.io.File(log));
                process=builder.start(); stop=onCleanup(@() Runtime.Resolver.stop(process)); started=tic;
                while process.isAlive()
                    if Runtime.Distribution.canceled(window,progress), error('Runtime:Cancelled','Installation canceled. Completed installations are retained; check saved versions before retrying.'); end
                    if toc(started)>3600, error('Runtime:Timeout','Installation timed out. Current selections were kept.'); end
                    lines=regexp(Runtime.Resolver.tail(log),'NEUROPAL_PROGRESS:([^\r\n]*)','tokens');
                    if ~isempty(lines), progress.Message=lines{end}{1}; end
                    drawnow limitrate; pause(.15);
                end
                if ~isvalid(window), return; end
                if isfile(response), result=jsondecode(fileread(response));
                else, result=struct('ok',false,'message','Installer exited without a completion receipt.'); end
                if process.exitValue()~=0 || ~result.ok
                    message='Setup could not complete. See the installation log.';
                    if isfield(result,'message'), message=result.message;
                    else
                        lines=regexp(Runtime.Resolver.tail(log),'SETUP FAILED:([^\r\n]*)','tokens');
                        if ~isempty(lines), message=lines{end}{1}; end
                    end
                    error('Runtime:Install','%s',message);
                end
                Runtime.Distribution.busy(window,false); Runtime.Distribution.refresh(window);
                if result.activated, c.message.Text='Validated and selected. Previous versions remain available above.';
                else, c.message.Text='Validated and installed. Your selected installation was kept; use the saved-version list to switch.'; end
                if isvalid(c.parent), Runtime.Settings.refresh(c.parent,false); end
            catch ME
                if isvalid(window)
                    c.message.Text=ME.message;
                    if ~isempty(log), c.message.Tooltip=['Installation log: ' log]; end
                end
            end
        end
        function restore(window)
            c=getappdata(window,'distribution_controls'); if c.busy, return; end
            profiles=getappdata(window,'distribution_history'); if isempty(profiles), return; end
            index=find(strcmp(c.versions.Items,c.versions.Value),1); profile=profiles{index};
            Runtime.Distribution.busy(window,true);
            progress=uiprogressdlg(window,'Title','Checking saved version','Message','Validating before switching…','Indeterminate','on','Cancelable','on');
            cleanup=onCleanup(@() Runtime.Distribution.finish(window,progress));
            try
                Runtime.Resolver.save(c.choice.Value,profile,true,@() Runtime.Distribution.canceled(window,progress));
                c.message.Text='Saved version validated and selected. Other capabilities are unchanged.';
                if isvalid(c.parent), Runtime.Settings.refresh(c.parent,false); end
            catch ME
                if isvalid(window), c.message.Text=ME.message; end
            end
        end
        function local(window)
            c=getappdata(window,'distribution_controls'); if c.busy, return; end
            Runtime.Installer.run(c.parent);
            if isvalid(window), Runtime.Distribution.refresh(window); end
        end
        function busy(window,value)
            c=getappdata(window,'distribution_controls'); c.busy=value;
            setappdata(window,'distribution_controls',c);
            setappdata(window,'distribution_cancel',false);
            state=matlab.lang.OnOffSwitchState(~value);
            c.choice.Enable=state; c.versions.Enable=state; c.select.Enable=state; c.repair.Enable=state;
            set(c.buttons,'Enable',state);
        end
        function finish(window,progress)
            if ~isempty(progress) && isvalid(progress), close(progress); end
            if ~isvalid(window), return; end
            Runtime.Distribution.busy(window,false);
            c=getappdata(window,'distribution_controls');
            if isempty(getappdata(window,'distribution_history')), c.restore.Enable='off'; end
            if ~Runtime.Distribution.supported(c.choice.Value) || ~ismac || ~strcmp(computer('arch'),'maca64'), c.install.Enable='off'; end
        end
        function yes = canceled(window,progress)
            yes=~isvalid(window);
            if ~yes, yes=isequal(getappdata(window,'distribution_cancel'),true); end
            if ~isempty(progress), yes=yes || ~isvalid(progress) || progress.CancelRequested; end
        end
        function close(window)
            c=getappdata(window,'distribution_controls');
            if c.busy, setappdata(window,'distribution_cancel',true);
            else, delete(window); end
        end
    end
end
