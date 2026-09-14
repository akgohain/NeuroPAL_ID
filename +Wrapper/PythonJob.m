classdef PythonJob < handle
    %PYTHONJOB Keep the app lease until the supervised worker has stopped.
    properties
        Process = [];
    end
    properties (SetAccess = private)
        Token
        CancelPath
    end
    properties (Access = private)
        Lease
    end
    methods
        function obj = PythonJob(parent_token)
            obj.Lease = Program.HeavyJob.acquire('Python inference', parent_token);
            obj.Token = obj.Lease.Token;
            obj.CancelPath = [tempname '.cancel'];
        end

        function delete(obj)
            lease = obj.Lease;
            release = onCleanup(@() delete(lease));
            if ~isempty(obj.Process) && obj.Process.isAlive()
                fid = fopen(obj.CancelPath, 'w');
                if fid >= 0, fclose(fid); end
                started = tic;
                while obj.Process.isAlive() && toc(started) < 12, pause(0.05); end
                if obj.Process.isAlive()
                    obj.Process.destroy();
                    started = tic;
                    while obj.Process.isAlive() && toc(started) < 3, pause(0.05); end
                    if obj.Process.isAlive(), obj.Process.destroyForcibly(); end
                end
            end
            if exist(obj.CancelPath, 'file') == 2, delete(obj.CancelPath); end
        end
    end
end
