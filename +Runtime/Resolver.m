classdef Resolver
    %RESOLVER Use the same validated installations from every application route.
    methods (Static)
        function report = inspect(id,overrides,deep,cancel)
            if nargin<2, overrides=struct(); end
            if nargin<3, deep=false; end
            if nargin<4, cancel=@() false; end
            id=Runtime.Catalog.canonical(id); entry=Runtime.Catalog.find(id);
            report=struct('id',id,'name',entry.name,'ready',false,'status','Not configured', ...
                'summary','','profile',Runtime.Catalog.profile(),'details',struct());
            selected=false;
            try
                Runtime.Configuration.read();
                [profile,selected]=Runtime.Discovery.profile(id);
                if all(isfield(overrides,fieldnames(Runtime.Catalog.profile())))
                    profile=Runtime.Catalog.profile(overrides);
                end
                fields=fieldnames(overrides);
                for i=1:numel(fields)
                    if isfield(profile,fields{i}) && strlength(string(overrides.(fields{i})))>0
                        profile.(fields{i})=char(string(overrides.(fields{i})));
                    end
                end
                report.profile=profile;
                Runtime.Resolver.assets(id,profile);
                if entry.python
                    if isempty(profile.python) || ~isfile(profile.python)
                        error('Runtime:Missing','Choose a Python executable for %s.',entry.name);
                    end
                    report.details=Runtime.Resolver.probe(id,profile,deep,cancel);
                elseif strcmp(id,'nn')
                    Methods.ModelSetup.neuralNetwork();
                    if deep, Methods.NNDetect.instance(); end
                elseif any(strcmp(id,{'mp','legacy_atlas'}))
                    for toolbox={'images','stats','optim'}
                        if isempty(ver(toolbox{1})), error('Runtime:MATLAB','Required MATLAB toolbox is missing: %s.',toolbox{1}); end
                    end
                end
                report.ready=true; report.status='Ready'; report.summary=[entry.name ' is ready.'];
                if ~entry.python, report.details=struct('matlab',version); end
            catch ME
                report.summary=ME.message;
                if contains(ME.identifier,'Cancel'), report.status='Check canceled';
                elseif strcmp(ME.identifier,'Runtime:Missing'), report.status='Not configured';
                elseif selected, report.status='Needs repair';
                else, report.status='Needs setup'; end
            end
        end
        function context = require(id,overrides,cancel)
            if nargin<2, overrides=struct(); end
            if nargin<3 || isempty(cancel), cancel=@() false; end
            report=Runtime.Resolver.inspect(id,overrides,false,cancel);
            if strcmp(report.status,'Check canceled'), error('Runtime:Cancelled','Setup check canceled.'); end
            if ~report.ready
                failure=MException('Runtime:SetupRequired','%s\n\nOpen Tools > Models & runtimes to configure %s.',report.summary,report.name);
                failure=addCause(failure,MException('Runtime:CapabilityContext','%s',report.id));
                throw(failure);
            end
            context=report.profile; context.capability=report.id; context.validation=report.details;
        end
        function python = python(id,explicit,cancel)
            if nargin<2, explicit=''; end
            if nargin<3, cancel=[]; end
            context=Runtime.Resolver.require(id,struct('python',char(explicit)),cancel); python=context.python;
        end
        function bundle = bundle(id)
            [profile,~]=Runtime.Discovery.profile(id); bundle=profile.bundle;
        end
        function save(id,profile,deep,cancel)
            if nargin<3, deep=true; end
            if nargin<4, cancel=@() false; end
            % Validate the proposed profile without changing the saved selection.
            profile=Runtime.Catalog.profile(profile);
            report=Runtime.Resolver.inspect(id,profile,deep,cancel);
            if ~report.ready, error('Runtime:Validation','%s',report.summary); end
            Runtime.Configuration.update(Runtime.Catalog.canonical(id),profile);
        end
        function assets(id,p)
            root=Runtime.Configuration.appRoot();
            if any(strcmp(id,{'detection_moe','spotiflow_supervised','crf_cellid_2'}))
                if isempty(p.bundle), error('Runtime:Missing','Choose the complete model bundle.'); end
                ready=Methods.MethodBundle.inspect(id,p.bundle);
                if ~ready.ready, error('Runtime:Assets','%s',ready.summary); end
            elseif strcmp(id,'anshita_gat')
                if ~isfile(fullfile(p.source,'run_app_volume_inference.py'))
                    error('Runtime:Missing','Choose the GAT source folder containing run_app_volume_inference.py.');
                end
                checkpoint=p.checkpoint; if isfolder(checkpoint), checkpoint=fullfile(checkpoint,'best_model.pt'); end
                if ~isfile(checkpoint) || ~isfile(fullfile(fileparts(checkpoint),'train_config.json'))
                    error('Runtime:Missing','Choose the GAT checkpoint with best_model.pt and train_config.json.');
                end
                jsondecode(fileread(fullfile(fileparts(checkpoint),'train_config.json')));
            elseif any(strcmp(id,{'yolo','cellpose'}))
                if ~isfile(p.weights), error('Runtime:Missing','Choose a local %s weights file.',id); end
                info=dir(p.weights); if info.bytes==0, error('Runtime:Assets','The weights file is empty.'); end
                fid=fopen(p.weights); cleanup=onCleanup(@() fclose(fid));
                if fid<0, error('Runtime:Assets','Cannot read the weights file.'); end
                header=fread(fid,100,'*char')';
                if startsWith(header,'version https://git-lfs.github.com/spec')
                    error('Runtime:Assets','This file is a Git LFS pointer, not model weights. Choose the downloaded model.');
                end
            elseif strcmp(id,'legacy_atlas')
                if ~isfile(fullfile(root,'Data','Models','atlas_xx_rgb.mat'))
                    error('Runtime:Assets','The application atlas files are missing.');
                end
            elseif strcmp(id,'legacy_segmentation')
                if ~isfile(fullfile(root,'External_Dependencies','3dct','CellTracker','python','npal_seg.py'))
                    error('Runtime:Assets','The legacy segmentation adapter is not installed.');
                end
            end
        end
        function result = probe(id,profile,deep,cancel)
            persistent cache
            if isempty(cache), cache=containers.Map('KeyType','char','ValueType','any'); end
            signature=Runtime.Resolver.signature(id,profile,deep);
            if ~deep && isKey(cache,signature)
                cached=cache(signature);
                if (now-cached.checked)*86400<60, result=cached.result; return; end
            end
            folder=tempname; mkdir(folder); cleanup=onCleanup(@() rmdir(folder,'s'));
            request=fullfile(folder,'request.json'); response=fullfile(folder,'response.json');
            logdir=fullfile(fileparts(Runtime.Configuration.location()),'logs');
            if ~isfolder(logdir), mkdir(logdir); end
            log=fullfile(logdir,['check-' id '-' char(java.util.UUID.randomUUID()) '.log']);
            value=struct('capability',id,'profile',profile,'deep',logical(deep),'app',Runtime.Configuration.appRoot());
            fid=fopen(request,'w'); writer=onCleanup(@() fclose(fid)); fwrite(fid,unicode2native(jsonencode(value),'UTF-8'),'uint8'); clear writer
            command={profile.python,'-u',fullfile(Runtime.Configuration.appRoot(),'+Wrapper','runtime_probe.py'),request,response};
            timeout=45; if deep, timeout=240; end
            [status,~]=Wrapper.runPythonProcess(command,'LogPath',log, ...
                'JobToken',Program.HeavyJob.token(),'CancelFcn',cancel,'TimeoutSeconds',timeout, ...
                'Environment',struct('CUDA_VISIBLE_DEVICES','-1'));
            if ~isfile(response), error('Runtime:Probe','Python could not complete its check.\n%s\n\nCheck log: %s',Runtime.Resolver.tail(log),log); end
            result=jsondecode(fileread(response));
            if status~=0 || ~result.ok, error('Runtime:Incompatible','%s\n\nCheck log: %s',result.message,log); end
            result.log=log;
            cache(signature)=struct('checked',now,'result',result);
        end
        function value = signature(id,profile,deep)
            % Changes to the interpreter, bundle or worker invalidate this session cache.
            paths={profile.python,profile.bundle,profile.source,profile.checkpoint,profile.weights, ...
                fullfile(fileparts(fileparts(profile.python)),'pyvenv.cfg'), ...
                fullfile(fileparts(fileparts(profile.python)),'neuropal-runtime.json'), ...
                fullfile(profile.bundle,'method_bundle.json'),fullfile(profile.bundle,'SHA256SUMS'), ...
                fullfile(profile.checkpoint,'train_config.json'),fullfile(profile.checkpoint,'best_model.pt'), ...
                fullfile(profile.source,'run_app_volume_inference.py'), ...
                fullfile(Runtime.Configuration.appRoot(),'distribution','macos','check_models.py'), ...
                Runtime.Configuration.location(), ...
                fullfile(Runtime.Configuration.appRoot(),'+Wrapper','runtime_probe.py')};
            metadata=cell(size(paths));
            for i=1:numel(paths)
                if isempty(paths{i}), continue; end
                data=dir(paths{i});
                if ~isempty(data), metadata{i}=[sum([data.bytes]),max([data.datenum])]; end
            end
            value=jsonencode(struct('id',id,'profile',profile,'deep',deep,'files',{metadata}));
        end
        function stop(process)
            % Keep handles to this process's descendants before stopping the parent.
            children={};
            try
                stream=process.toHandle().descendants(); close=onCleanup(@() stream.close()); iterator=stream.iterator();
                while iterator.hasNext(), children{end+1}=iterator.next(); end
            catch
            end
            for i=numel(children):-1:1
                if children{i}.isAlive(), children{i}.destroy(); end
            end
            if process.isAlive()
                process.destroy(); process.waitFor(2,java.util.concurrent.TimeUnit.SECONDS);
                if process.isAlive(), process.destroyForcibly(); end
            end
            for i=numel(children):-1:1
                if children{i}.isAlive(), children{i}.destroyForcibly(); end
            end
        end
        function value = tail(file)
            fid=fopen(file); if fid<0, value='No diagnostic output.'; return; end
            cleanup=onCleanup(@() fclose(fid)); data=dir(file); fseek(fid,max(0,data.bytes-8192),'bof'); value=fread(fid,8192,'*char')';
        end
    end
end
