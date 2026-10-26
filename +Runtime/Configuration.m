classdef Configuration
    %CONFIGURATION Keep machine settings outside the application and image files.
    methods (Static)
        function root = userRoot()
            home = char(java.lang.System.getProperty('user.home'));
            if ismac
                root = fullfile(home,'Library','Application Support','NeuroPAL_ID');
            elseif ispc
                root = fullfile(home,'AppData','Local','NeuroPAL_ID');
            else
                root = fullfile(home,'.local','share','NeuroPAL_ID');
            end
        end
        function value = location(varargin)
            % An explicit location also allows isolated batch and validation runs.
            persistent selected
            if nargin, selected=char(varargin{1}); end
            value=selected;
            if isempty(value), value=fullfile(Runtime.Configuration.userRoot(),'dependencies.json'); end
        end
        function root = appRoot()
            root=fileparts(fileparts(mfilename('fullpath')));
        end
        function value = empty()
            value=struct('schema_version',1,'profiles',struct(),'installations',{{}},'resources', ...
                struct('max_job_mib',6144,'moe_workspace_mib',4096,'router_mib',512, ...
                'image_max_mib',512,'io_chunk_mib',128,'video_cache_mib',32,'threads',4));
        end
        function value = read()
            file=Runtime.Configuration.location(); value=Runtime.Configuration.empty();
            if ~isfile(file), return; end
            try
                supplied=jsondecode(fileread(file));
                if ~isstruct(supplied) || ~isscalar(supplied) || ...
                        ~isfield(supplied,'schema_version') || supplied.schema_version~=1 || ...
                        ~isfield(supplied,'profiles') || ~isstruct(supplied.profiles) || ~isscalar(supplied.profiles)
                    error('Runtime:Configuration:Schema','Unsupported dependency settings.');
                end
                value.profiles=supplied.profiles;
                if isfield(supplied,'installations')
                    value.installations=cellstr(string(supplied.installations(:)));
                end
                if isfield(supplied,'resources')
                    names=fieldnames(value.resources);
                    for i=1:numel(names)
                        name=names{i};
                        if isfield(supplied.resources,name)
                            n=supplied.resources.(name);
                            if isnumeric(n) && isscalar(n) && isfinite(n) && n>=0 && (n>0 || strcmp(name,'video_cache_mib')) && n<=1048576
                                if ~strcmp(name,'threads') || (n==round(n) && n>=1 && n<=256)
                                    value.resources.(name)=n;
                                end
                            end
                        end
                    end
                end
            catch ME
                error('Runtime:Configuration:Unreadable', ...
                    'Cannot read Models & runtimes settings. Use Reset settings in that window to preserve a backup and start again.\n\n%s\n%s',file,ME.message);
            end
        end
        function update(id,profile)
            if ~strcmp(id,'resources'), Runtime.Catalog.find(id); end
            file=Runtime.Configuration.location(); folder=fileparts(file);
            if ~isfolder(folder), mkdir(folder); end
            release=Runtime.Configuration.lock(file);
            value=Runtime.Configuration.read();
            if strcmp(id,'resources')
                defaults=Runtime.Configuration.empty(); names=fieldnames(defaults.resources);
                for i=1:numel(names)
                    n=profile.(names{i}); minimum=0;
                    if ~strcmp(names{i},'video_cache_mib'), minimum=eps; end
                    if ~isnumeric(n) || ~isscalar(n) || ~isfinite(n) || n<minimum || n>1048576
                        error('Runtime:Resources','Enter valid positive resource limits; video cache may be zero.');
                    end
                end
                if profile.threads~=round(profile.threads) || profile.threads<1 || profile.threads>256
                    error('Runtime:Resources','Threads must be a whole number between 1 and 256.');
                end
                value.resources=profile;
            elseif isempty(profile)
                if isfield(value.profiles,id), value.profiles=rmfield(value.profiles,id); end
            else
                value.profiles.(id)=Runtime.Catalog.profile(profile);
            end
            temporary=[tempname(folder) '.json'];
            cleanup=onCleanup(@() Runtime.Configuration.remove(temporary));
            fid=fopen(temporary,'w');
            if fid<0, error('Runtime:Configuration:Write','Cannot save dependency settings in %s.',folder); end
            writer=onCleanup(@() fclose(fid)); fwrite(fid,unicode2native(jsonencode(value),'UTF-8'),'uint8'); clear writer
            [ok,message]=movefile(temporary,file,'f');
            if ~ok, error('Runtime:Configuration:Write','%s',message); end
        end
        function reset()
            file=Runtime.Configuration.location();
            folder=fileparts(file); if ~isfolder(folder), mkdir(folder); end
            release=Runtime.Configuration.lock(file);
            if isfile(file)
                backup=[file '.backup-' char(java.util.UUID.randomUUID())];
                [ok,message]=movefile(file,backup);
                if ~ok, error('Runtime:Configuration:Backup','%s',message); end
            end
        end
        function remove(file)
            if isfile(file), delete(file); end
        end
        function release = lock(file)
            lock=java.io.RandomAccessFile([file '.lock'],'rw');
            try
                lease=lock.getChannel().tryLock();
            catch ME
                lock.close(); rethrow(ME);
            end
            if isempty(lease), lock.close(); error('Runtime:Configuration:Busy','Another app is saving runtime settings. Try again.'); end
            release=onCleanup(@() Runtime.Configuration.unlock(lock,lease));
        end
        function unlock(file,lease)
            if lease.isValid(), lease.release(); end
            file.close();
        end
    end
end
