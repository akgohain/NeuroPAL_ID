classdef Discovery
    %DISCOVERY Inspect known installations without scanning experiments or disks.
    methods (Static)
        function roots = searchRoots(varargin)
            persistent selected
            if nargin, selected=varargin{1}; end
            roots=selected;
            if isempty(roots), roots={Runtime.Configuration.userRoot()}; end
        end
        function profiles = installed()
            profiles=struct(); roots=Runtime.Discovery.searchRoots();
            records=struct('name',{},'folder',{},'date',{},'bytes',{},'isdir',{},'datenum',{});
            for i=1:numel(roots)
                found=dir(fullfile(roots{i},'Methods-*','installation.json'));
                if ~isempty(found), records=[records;found(:)]; end
            end
            try
                config=Runtime.Configuration.read();
                for i=1:min(100,numel(config.installations))
                    extra=dir(fullfile(config.installations{i},'installation.json'));
                    if ~isempty(extra), records=[records;extra(:)]; end
                end
            catch
            end
            [~,order]=sort([records.datenum],'descend'); records=records(order);
            for i=1:min(100,numel(records))
                try
                    data=jsondecode(fileread(fullfile(records(i).folder,records(i).name)));
                    if isfield(data,'profiles')
                        found=data.profiles;
                    elseif isfield(data,'configuration')
                        found=Runtime.Discovery.fromLegacy(data.configuration);
                    else, continue; end
                    names=fieldnames(found);
                    for j=1:numel(names)
                        if ~isfield(profiles,names{j}), profiles.(names{j})=found.(names{j}); end
                    end
                catch
                    % An incomplete installer record must not prevent app startup.
                end
            end
        end
        function profiles = fromLegacy(config)
            profiles=struct(); origin='installed package';
            mapping={'recording_io','NEUROPAL_VIDEO_PYTHON';'recommendation','NEUROPAL_VIDEO_PYTHON'; ...
                'alignment','NEUROPAL_VIDEO_PYTHON';'activity','NEUROPAL_VIDEO_PYTHON'; ...
                'zephir','NEUROPAL_VIDEO_PYTHON';'detection_moe','NEUROPAL_MOE_PYTHON'; ...
                'yolo','NEUROPAL_YOLO_PYTHON';'cellpose','NEUROPAL_CELLPOSE_PYTHON'; ...
                'spotiflow_supervised','NEUROPAL_SPOTIFLOW_PYTHON'; ...
                'anshita_gat','NEUROPAL_TRANSFORMER_PYTHON';'ensemble','NEUROPAL_ENSEMBLE_PYTHON'};
            for i=1:size(mapping,1)
                key=mapping{i,2};
                if isfield(config,key) && ~isempty(config.(key))
                    p=Runtime.Catalog.profile(); p.python=char(config.(key)); p.origin=origin;
                    profiles.(mapping{i,1})=p;
                end
            end
            if ~isfield(profiles,'ensemble') && isfield(profiles,'detection_moe')
                profiles.ensemble=profiles.detection_moe;
            end
            for id={'detection_moe','spotiflow_supervised','crf_cellid_2'}
                key=['NEUROPAL_' upper(id{1}) '_BUNDLE'];
                if isfield(config,key) && ~isempty(config.(key))
                    if ~isfield(profiles,id{1}), profiles.(id{1})=Runtime.Catalog.profile(); end
                    profiles.(id{1}).bundle=char(config.(key)); profiles.(id{1}).origin=origin;
                end
            end
            pairs={'anshita_gat','source','NEUROPAL_GAT_REPO'; ...
                'anshita_gat','checkpoint','NEUROPAL_GAT_CHECKPOINT'; ...
                'cellpose','weights','NEUROPAL_CELLPOSE_MODEL'};
            for i=1:size(pairs,1)
                if isfield(config,pairs{i,3}) && ~isempty(config.(pairs{i,3}))
                    id=pairs{i,1}; if ~isfield(profiles,id), profiles.(id)=Runtime.Catalog.profile(); end
                    profiles.(id).(pairs{i,2})=char(config.(pairs{i,3})); profiles.(id).origin=origin;
                end
            end
        end
        function profiles = legacyEnvironment()
            % Reading legacy variables is an explicit migration action only.
            keys={'NEUROPAL_VIDEO_PYTHON','NEUROPAL_MOE_PYTHON','NEUROPAL_YOLO_PYTHON', ...
                'NEUROPAL_CELLPOSE_PYTHON','NEUROPAL_SPOTIFLOW_PYTHON','NEUROPAL_TRANSFORMER_PYTHON', ...
                'NEUROPAL_ENSEMBLE_PYTHON','NEUROPAL_DETECTION_MOE_BUNDLE', ...
                'NEUROPAL_SPOTIFLOW_SUPERVISED_BUNDLE','NEUROPAL_CRF_CELLID_2_BUNDLE', ...
                'NEUROPAL_GAT_REPO','NEUROPAL_GAT_CHECKPOINT','NEUROPAL_CELLPOSE_MODEL'};
            data=struct();
            for i=1:numel(keys), data.(keys{i})=getenv(keys{i}); end
            if isempty(data.NEUROPAL_GAT_CHECKPOINT), data.NEUROPAL_GAT_CHECKPOINT=getenv('NEUROPAL_TRANSFORMER_CHECKPOINT'); end
            profiles=Runtime.Discovery.fromLegacy(data);
        end
        function [profile,selected] = profile(id)
            id=Runtime.Catalog.canonical(id); entry=Runtime.Catalog.find(id);
            try
                data=Runtime.Configuration.read();
            catch ME
                if ~strcmp(ME.identifier,'Runtime:Configuration:Unreadable'), rethrow(ME); end
                % Readiness reports the fault; drawing the toolbar still works.
                data=Runtime.Configuration.empty();
            end
            selected=isfield(data.profiles,id);
            if selected
                try
                    profile=Runtime.Catalog.profile(data.profiles.(id));
                catch
                    profile=Runtime.Catalog.profile(); profile.origin='invalid saved selection';
                end
                return;
            end
            installed=Runtime.Discovery.installed(); profile=Runtime.Catalog.profile();
            if isfield(installed,id), profile=Runtime.Catalog.profile(installed.(id)); end
            root=Runtime.Configuration.appRoot();
            if isempty(profile.bundle) && any(strcmp(entry.fields,'bundle'))
                path=fullfile(root,'method_bundles',id);
                if isfile(fullfile(path,'method_bundle.json')), profile.bundle=path; end
            end
            if strcmp(id,'yolo') && isempty(profile.weights)
                profile.weights=fullfile(root,'External_Dependencies','yolo_inf2','best.pt');
            end
        end
    end
end
