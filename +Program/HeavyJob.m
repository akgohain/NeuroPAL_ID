classdef HeavyJob < handle
    %HEAVYJOB Own a heavyweight operation across app and worker processes.
    properties (SetAccess = private)
        Token = '';
    end
    properties (Access = private)
        File = [];
        Lease = [];
        OwnerPath = '';
        Registered = false;
    end
    methods (Static)
        function assertIdle(parent_token)
            %ASSERTIDLE Reject source edits while another operation owns the app.
            if nargin < 1, parent_token = ''; end
            active = Program.HeavyJob.current();
            if ~isempty(active) && isvalid(active) && ...
                    (isempty(parent_token) || ~strcmp(parent_token, active.Token))
                error('Program:HeavyJob:Busy', ...
                    'Wait for the current NeuroPAL operation to finish or cancel it before changing the image or annotations.');
            end
        end

        function obj = acquire(name, parent_token)
            if nargin < 2, parent_token = ''; end
            active = Program.HeavyJob.current();
            obj = Program.HeavyJob();
            if ~isempty(active) && isvalid(active)
                if ~isempty(parent_token) && strcmp(parent_token, active.Token)
                    obj.Token = active.Token;
                    return
                end
                error('Program:HeavyJob:Busy', 'Another NeuroPAL heavy job is running. Wait for it to finish or cancel it.');
            end
            path = getenv('NEUROPAL_JOB_LOCK');
            if isempty(path), path = fullfile(tempdir, 'neuropal-heavy-job.lock'); end
            owner_path = [path '.owner.json'];
            inherited = getenv('NEUROPAL_JOB_TOKEN');
            if ~isempty(inherited) && exist(owner_path, 'file') == 2
                try
                    owner = jsondecode(fileread(owner_path));
                    if strcmp(owner.token, inherited)
                        obj.Token = inherited;
                    end
                catch
                    % An unrelated or incomplete lease is acquired normally.
                end
            end
            if isempty(obj.Token)
                try
                    obj.File = java.io.RandomAccessFile(path, 'rw');
                    obj.Lease = obj.File.getChannel().tryLock(0, 1, false);
                    if isempty(obj.Lease)
                        error('Program:HeavyJob:Busy', 'Another NeuroPAL heavy job is running. Wait for it to finish or cancel it.');
                    end
                    obj.Token = char(java.util.UUID.randomUUID());
                    obj.OwnerPath = owner_path;
                    owner = struct('pid', feature('getpid'), 'token', obj.Token, 'name', char(name));
                    fid = fopen(owner_path, 'w');
                    if fid < 0
                        error('Program:HeavyJob:Metadata', 'Cannot write job ownership metadata.');
                    end
                    metadata_cleanup = onCleanup(@() fclose(fid));
                    fwrite(fid, jsonencode(owner), 'char');
                    clear metadata_cleanup
                catch ME
                    delete(obj);
                    rethrow(ME);
                end
            end
            obj.Registered = true;
            Program.HeavyJob.current(obj);
        end
    end
    methods
        function delete(obj)
            if ~isempty(obj.Lease)
                try
                    if exist(obj.OwnerPath, 'file') == 2
                        owner = jsondecode(fileread(obj.OwnerPath));
                        if strcmp(owner.token, obj.Token), delete(obj.OwnerPath); end
                    end
                catch
                end
                try
                    obj.Lease.release();
                catch
                end
                obj.Lease = [];
            end
            if ~isempty(obj.File)
                try
                    obj.File.close();
                catch
                end
                obj.File = [];
            end
            if obj.Registered
                Program.HeavyJob.current([]);
                obj.Registered = false;
            end
        end
    end
    methods (Static, Access = private)
        function value = current(varargin)
            persistent active
            if nargin > 0, active = varargin{1}; end
            value = active;
        end
    end
end
