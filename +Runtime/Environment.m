classdef Environment
    %ENVIRONMENT Scope worker caches and resource limits to the child process.
    methods (Static)
        function apply(builder)
            resources=Program.HeavyJob.resources();
            environment=builder.environment();
            % Managed workers must not inherit another Python environment.
            for key={'PYTHONHOME','PYTHONPATH','VIRTUAL_ENV','CONDA_PREFIX'}
                environment.remove(key{1});
            end
            root=fullfile(fileparts(Runtime.Configuration.location()),'cache');
            names={'MPLCONFIGDIR','YOLO_CONFIG_DIR','XDG_CONFIG_HOME','CELLPOSE_LOCAL_MODELS_PATH'};
            for i=1:numel(names)
                folder=fullfile(root,lower(names{i}));
                if ~isfolder(folder), mkdir(folder); end
                environment.put(names{i},folder);
            end
            mapping={'NEUROPAL_MAX_JOB_MIB','max_job_mib';'NEUROPAL_MOE_WORKSPACE_MIB','moe_workspace_mib'; ...
                'NEUROPAL_ROUTER_MIB','router_mib';'NEUROPAL_IMAGE_MAX_MIB','image_max_mib'};
            for i=1:size(mapping,1), environment.put(mapping{i,1},num2str(resources.(mapping{i,2}))); end
            environment.put('MPLBACKEND','Agg'); environment.put('PYTHONNOUSERSITE','1');
            environment.put('PYTHONDONTWRITEBYTECODE','1');
            environment.put('OMP_NUM_THREADS',num2str(round(resources.threads)));
        end
        function value = resource(name)
            try
                config=Runtime.Configuration.read();
            catch ME
                if ~strcmp(ME.identifier,'Runtime:Configuration:Unreadable'), rethrow(ME); end
                config=Runtime.Configuration.empty();
            end
            value=config.resources.(name);
        end
    end
end
