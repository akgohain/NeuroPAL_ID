classdef ActivityImport
    %ACTIVITYIMPORT Validate complete activity tables before replacing the browser data.
    methods (Static)
        function choose(app,kind)
            Program.HeavyJob.assertIdle();
            prefs=Program.GUIPreferences.instance();
            if nargin<2, kind=''; end
            filter=['*.' kind];
            if isempty(kind), filter={'*.csv;*.nwb','Named neuron activity'}; end
            [name,folder]=Program.GUI.ManualIDService.selectFile(app,'uigetfile', ...
                filter,'Import named neuron activity',prefs.image_dir);
            if isequal(name,0), return; end
            progress=uiprogressdlg(app.CELL_ID,'Title','Import neuron activity','Message','Checking activity and neuron names…','Indeterminate','on');
            cleanup=onCleanup(@() Runtime.Installer.close(progress));
            file=fullfile(folder,name);
            [~,~,extension]=fileparts(file); timestamps=[];
            if strcmpi(extension,'.csv'), [names,activity]=Program.ActivityImport.readCSV(file);
            elseif strcmpi(extension,'.nwb'), [names,activity,timestamps]=Program.ActivityImport.readNWB(file);
            else, error('NeuroPAL:ActivityFormat','Choose a supported CSV or NWB activity file.'); end
            [map,table]=Program.ActivityImport.prepare(names,activity);
            if ~isempty(timestamps)
                if ismember('timestamps',table.Properties.VariableNames)
                    error('NeuroPAL:ActivityNames','A neuron name conflicts with the reserved timestamps column.');
                end
                table.timestamps=timestamps;
            end
            app.neuron_activity_by_name=map; app.activity_table=table; app.activity_module=[];
            app.framerate=[]; app.color_tracker=[]; app.style_tracker=[];
            app.DisplayNeuronActivityMenu.Checked='off';
            app.VolTraceParent.Visible='off'; app.LoadNeuronActivityButton.Visible='on';
            Program.GUIHandling.gui_lock(app,'enable','activity_gui');
            close(progress);
            uialert(app.CELL_ID,'Named activity loaded. Use Neuron Activity to display it.','Neuron activity','Icon','success');
        end
        function [names,activity] = readCSV(file)
            stat=dir(file);
            if isempty(stat) || stat.bytes>64*1024^2
                error('NeuroPAL:ActivitySize','Choose an activity CSV smaller than 64 MiB, or use NWB / Video Tracking for larger recordings.');
            end
            data=readtable(file,'VariableNamingRule','preserve');
            if width(data)<6 || height(data)==0
                error('NeuroPAL:ActivityFormat','Expected legacy ZephIR CSV rows with neuron names in column 2 and activity samples from column 6 onward.');
            end
            names=string(data{:,2}); activity=data{:,6:end};
            if ~isnumeric(activity) || ~isreal(activity)
                error('NeuroPAL:ActivityFormat','Activity samples must be numeric; missing samples may be NaN.');
            end
            Program.ActivityImport.prepare(names,activity);
        end
        function [names,activity,timestamps] = readNWB(file)
            base='/processing/CalciumActivity/'; dataset='';
            paths={[base 'SignalRawFluor/SignalCalciumImResponseSeries/data'],[base 'ActivityTraces/activity']};
            for i=1:numel(paths)
                try, h5info(file,paths{i}); dataset=paths{i}; break; catch, end
            end
            if isempty(dataset)
                try
                    group=h5info(file,[base 'ActivityDfOverF']);
                    for i=1:numel(group.Groups)
                        path=[group.Groups(i).Name '/data'];
                        try, h5info(file,path); dataset=path; break; catch, end
                    end
                catch
                end
            end
            if isempty(dataset), error('NeuroPAL:ActivityFormat','This NWB does not contain a supported CalciumActivity trace dataset.'); end
            detail=h5info(file,dataset);
            if numel(detail.Dataspace.Size)>2 || prod(double(detail.Dataspace.Size))*8>Runtime.Environment.resource('image_max_mib')*1024^2
                error('NeuroPAL:ActivitySize','The activity matrix exceeds the supported dimensions or memory budget. Use Video Tracking for bounded recording access.');
            end
            names=[];
            paths={[base 'NeuronIDs/labels'],[base 'ActivityTraces/neuron'],[base 'ActivityLabels/neuron']};
            for i=1:numel(paths)
                try, labelinfo=h5info(file,paths{i}); catch, continue; end
                count=prod(double(labelinfo.Dataspace.Size));
                if count>1e6 || ~ismember(count,double(detail.Dataspace.Size))
                    error('NeuroPAL:ActivityNames','The neuron-label count does not match either axis of the activity matrix.');
                end
                names=string(h5read(file,paths{i})); if ~isempty(names), break; end
            end
            if isempty(names), error('NeuroPAL:ActivityNames','The NWB activity dataset has no supported neuron-name labels.'); end
            activity=h5read(file,dataset);
            if size(activity,1)~=numel(names) && size(activity,2)==numel(names), activity=activity'; end
            Program.ActivityImport.prepare(names,activity);
            timestamps=[]; timepath=[fileparts(dataset) '/timestamps'];
            try, timeinfo=h5info(file,timepath); catch, timeinfo=[]; end
            if ~isempty(timeinfo)
                if prod(double(timeinfo.Dataspace.Size))~=size(activity,2)
                    error('NeuroPAL:ActivityTime','Activity timestamps must match the sample count.');
                end
                timestamps=double(h5read(file,timepath)); timestamps=timestamps(:);
                if any(~isfinite(timestamps)) || any(diff(timestamps)<=0)
                    error('NeuroPAL:ActivityTime','Activity timestamps must be finite and strictly increasing.');
                end
            end
        end
        function [map,table] = prepare(names,activity)
            names=strtrim(string(names(:)));
            if ~isnumeric(activity) || ~isreal(activity) || ~ismatrix(activity) || isempty(activity) || ...
                    size(activity,1)~=numel(names) || any(isinf(activity),'all')
                error('NeuroPAL:ActivityFormat','Activity must have one numeric row per neuron name and a common sample count. Missing samples may be NaN.');
            end
            keep=~ismissing(names) & strlength(names)>0 & ~strcmpi(names,'unknown') & ~strcmpi(names,'null');
            names=names(keep); activity=activity(keep,:);
            if isempty(names) || ~any(isfinite(activity),'all')
                error('NeuroPAL:ActivityNames','No named neurons with finite activity were found.');
            end
            if any(strlength(names)>128) || numel(unique(names))~=numel(names)
                error('NeuroPAL:ActivityNames','Neuron names must be unique and at most 128 characters; duplicate rows cannot be silently merged.');
            end
            map=containers.Map('KeyType','char','ValueType','any');
            for i=1:numel(names), map(char(names(i)))=double(activity(i,:)); end
            map('null')=zeros(1,size(activity,2));
            labels=[cellstr(names);{'null'}];
            columns=matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(labels));
            table=array2table([double(activity);zeros(1,size(activity,2))]','VariableNames',columns);
        end
        function display(app)
            if app.DisplayNeuronActivityMenu.Checked
                app.VolTraceParent.Visible='off'; app.LoadNeuronActivityButton.Visible='on';
                app.DisplayNeuronActivityMenu.Checked='off'; return;
            end
            if ~istable(app.activity_table) || ~ismember('null',app.activity_table.Properties.VariableNames)
                error('NeuroPAL:ActivityMissing','Import named neuron activity before opening the trace browser.');
            end
            progress=uiprogressdlg(app.CELL_ID,'Title','Loading activity','Indeterminate','on');
            cleanup=onCleanup(@() Runtime.Installer.close(progress));
            previous=app.VolTrace;
            if ismember('timestamps',app.activity_table.Properties.VariableNames)
                trace=stackedplot(app.VolTraceHelperGrid,app.activity_table,{'null'},'XVariable','timestamps');
                trace.XLabel='Time (s)';
            else
                trace=stackedplot(app.VolTraceHelperGrid,app.activity_table,{'null'}); trace.XLabel='Sample';
            end
            trace.GridVisible='on'; trace.Layout.Row=[1 numel(app.VolTraceHelperGrid.RowHeight)]; trace.Layout.Column=[1 2];
            app.VolTrace=trace;
            if ~isempty(previous) && isvalid(previous), delete(previous); end
            app.VolTraceParent.Parent=app.LoadNeuronActivityButton.Parent;
            app.VolTraceParent.Layout=app.LoadNeuronActivityButton.Layout;
            app.LoadNeuronActivityButton.Visible='off'; app.VolTraceParent.Visible='on';
            app.DisplayNeuronActivityMenu.Checked='on';
        end
        function recording(app)
            prefs=Program.GUIPreferences.instance();
            [name,folder]=Program.GUI.ManualIDService.selectFile(app,'uigetfile', ...
                {'*.h5;*.hdf5;*.nwb','Calcium recordings'},'Open calcium recording',prefs.image_dir);
            if isequal(name,0), return; end
            Program.Routines.open(fullfile(folder,name),'recording');
        end
        function unavailableBatch(app)
            uialert(app.CELL_ID, ...
                ['The legacy batch command does not use the selected MoE/GAT models and cannot safely preserve reviewed IDs. ' ...
                 'Open each image with File > Open, then use Auto-detect and Auto-ID.'], ...
                'Batch workflow unavailable','Icon','info');
        end
    end
end
