classdef NeuronNames
    %NEURONNAMES Keep anatomical names separate from stable tracking IDs.
    methods (Static)
        function records = get(c)
            records=getappdata(c.Grid,'neuron_names');
            if isempty(records), records=struct('id',{},'name',{},'confidence',{},'source',{}); end
        end
        function records = validate(records)
            if isempty(records), records=struct('id',{},'name',{},'confidence',{},'source',{}); end
            if ~isstruct(records) || ~all(isfield(records,{'id','name','confidence','source'}))
                error('Tracking:Names','Invalid saved neuron names.');
            end
            if ~isempty(records)
                records=reshape(records,1,[]); ids=[records.id];
                if ~isnumeric(ids) || ~isreal(ids) || numel(ids)~=numel(records) || numel(unique(ids))~=numel(ids) || any(~isfinite(ids) | ids<1 | ids~=round(ids))
                    error('Tracking:Names','Neuron names must refer to unique positive tracking IDs.');
                end
            end
            for i=1:numel(records)
                name=string(records(i).name); confidence=records(i).confidence; source=string(records(i).source);
                if ~isscalar(name) || ismissing(name) || strlength(name)>64 || any(char(name)<32) || ...
                        ~isscalar(confidence) || ~isfinite(confidence) || confidence<0 || confidence>1 || ~isscalar(source) || ismissing(source)
                    error('Tracking:Names','Invalid neuron name or identity confidence.');
                end
            end
        end
        function set(c,records)
            records=Tracking.NeuronNames.validate(records);
            setappdata(c.Grid,'neuron_names',records);
            c.View.ListKey={}; c.View.ProjectionKey={}; c.Analysis.PlotKey={};
        end
        function name = label(c,id,with_id)
            if nargin<3, with_id=false; end
            records=Tracking.NeuronNames.get(c); index=find([records.id]==id,1);
            if isempty(index) || isempty(strtrim(records(index).name))
                name=sprintf('Neuron %d',id); return;
            end
            name=char(records(index).name);
            if strcmp(records(index).source,'auto-id'), name=[name '?']; end
            if with_id, name=sprintf('%s · #%d',name,id); end
        end
        function value = tooltip(c,id)
            records=Tracking.NeuronNames.get(c); index=find([records.id]==id,1);
            value='Select a neuron to inspect its trajectory and activity.';
            if isempty(index) || isempty(records(index).name), return; end
            record=records(index);
            if strcmp(record.source,'auto-id')
                value=sprintf('Auto-ID class suggestion: %s. Model confidence: %.1f%%. Not reviewed.',record.name,100*record.confidence);
            else
                value=sprintf('%s · identity source: %s',record.name,record.source);
            end
        end
        function import(c,observations)
            records=Tracking.NeuronNames.get(c);
            if isempty(observations) || ~isfield(observations,'name'), return; end
            [~,indices]=unique([observations.track_id]);
            for i=indices(:)'
                row=observations(i); name=char(row.name);
                if isempty(name) || strcmp(name,sprintf('Neuron %d',row.track_id)), continue; end
                index=find([records.id]==row.track_id,1); if isempty(index), index=numel(records)+1; end
                confidence=1; source='imported';
                if isfield(row,'identity_confidence'), confidence=row.identity_confidence; end
                if isfield(row,'identity_source'), source=char(row.identity_source); end
                records(index)=struct('id',row.track_id,'name',name,'confidence',confidence,'source',source);
            end
            Tracking.NeuronNames.set(c,records);
        end
        function edit(c)
            if c.Busy || isempty(c.View.Selection) || c.View.Selection(1), return; end
            id=c.View.PreferredID; records=Tracking.NeuronNames.get(c); index=find([records.id]==id,1);
            initial=''; if ~isempty(index), initial=records(index).name; end
            answer=inputdlg('Anatomical name (blank to clear):','Neuron name',1,{initial});
            if isempty(answer), return; end
            name=strtrim(answer{1});
            if numel(name)>64, uialert(c.App.CELL_ID,'Use a neuron name of at most 64 characters.','Neuron name'); return; end
            if isempty(index), index=numel(records)+1; end
            records(index)=struct('id',id,'name',name,'confidence',1,'source','reviewed');
            Tracking.NeuronNames.set(c,records); c.render();
        end
    end
end
