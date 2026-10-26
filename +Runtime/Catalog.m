classdef Catalog
    %CATALOG Requirements belong to operations, rather than Python filenames.
    methods (Static)
        function entries = all()
            ids={'recording_io','recommendation','alignment','activity','zephir', ...
                'detection_moe','spotiflow_supervised','yolo','cellpose','anshita_gat', ...
                'crf_cellid_2','czi_reader','legacy_segmentation','ensemble','mp','nn','legacy_atlas'};
            names={'Recording reader','Frame recommendations','Reference alignment','Activity and session exchange', ...
                'ZephIR tracking','MoE detection','Spotiflow detection','YOLO detection','Cellpose detection', ...
                'GAT Auto-ID','CRF Auto-ID','CZI fallback reader','Legacy segmentation','Detection consensus', ...
                'Matching pursuit','Neural-network detection','Atlas Auto-ID'};
            entries=repmat(struct('id','','name','','python',true,'fields',{{}}),1,numel(ids));
            for i=1:numel(ids)
                id=ids{i}; fields={'python'};
                if any(strcmp(id,{'detection_moe','spotiflow_supervised','crf_cellid_2'})), fields{end+1}='bundle'; end
                if strcmp(id,'anshita_gat'), fields=[fields {'source','checkpoint'}]; end
                if any(strcmp(id,{'yolo','cellpose'})), fields{end+1}='weights'; end
                python=~any(strcmp(id,{'mp','nn','legacy_atlas','crf_cellid_2'}));
                if ~python, fields=setdiff(fields,{'python'},'stable'); end
                entries(i)=struct('id',id,'name',names{i},'python',python,'fields',{fields});
            end
        end
        function id = canonical(id)
            id=lower(char(string(id)));
            switch id
                case {'gat','transformer','gat/transformer'}, id='anshita_gat';
                case {'moe'}, id='detection_moe';
                case {'atlas'}, id='legacy_atlas';
                case {'spotiflow'}, id='spotiflow_supervised';
                case {'crf'}, id='crf_cellid_2';
            end
        end
        function entry = find(id)
            id=Runtime.Catalog.canonical(id); entries=Runtime.Catalog.all();
            index=find(strcmp({entries.id},id),1);
            if isempty(index), error('Runtime:Capability','This capability is not implemented: %s.',id); end
            entry=entries(index);
        end
        function value = profile(varargin)
            value=struct('python','','bundle','','source','','checkpoint','','weights','','origin','user');
            if ~nargin, return; end
            supplied=varargin{1};
            if ~isstruct(supplied) || ~isscalar(supplied), error('Runtime:Profile','Expected one installation profile.'); end
            names=fieldnames(value);
            for i=1:numel(names)
                if isfield(supplied,names{i})
                    text=string(supplied.(names{i}));
                    if ~isscalar(text) || ismissing(text), error('Runtime:Profile','Invalid %s path.',names{i}); end
                    value.(names{i})=strtrim(char(text));
                    if ~strcmp(names{i},'origin') && ~isempty(value.(names{i}))
                        [ok,attributes]=fileattrib(value.(names{i}));
                        if ok, value.(names{i})=attributes.Name; end
                    end
                end
            end
        end
        function capability = action(action)
            switch char(action)
                case {'track','track_sequence'}, capability='zephir';
                case 'recommend_frames', capability='recommendation';
                case 'align_neuropal', capability='alignment';
                case {'activity','name_activity','export','import','tracking_checkpoint'}, capability='activity';
                otherwise, capability='recording_io';
            end
        end
    end
end
