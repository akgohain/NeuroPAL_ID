function [status, output] = runPythonProcess(parts, options)
%RUNPYTHONPROCESS Supervise a worker with bounded logs and live cancellation.
arguments
    parts cell
    options.JobToken (1,1) string = ""
    options.WorkingDirectory (1,1) string = ""
    options.LogPath (1,1) string = ""
    options.ProgressFcn = []
    options.CancelFcn = []
    options.TimeoutSeconds (1,1) double = 10800
end
if ~isfinite(options.TimeoutSeconds) || options.TimeoutSeconds <= 0
    error('Wrapper:ProcessTimeout', 'TimeoutSeconds must be finite and positive.');
end
owner = Wrapper.PythonJob(options.JobToken);
cleanup = onCleanup(@() delete(owner));
cancel_path = owner.CancelPath;
log_path = char(options.LogPath);
if isempty(log_path), log_path = [tempname '.log']; end
supervisor = fullfile(fileparts(mfilename('fullpath')), 'resource_control.py');
command = [{parts{1}, '-u', supervisor, '--report', [log_path '.resources.jsonl'], ...
    '--timeout', num2str(options.TimeoutSeconds), '--cancel-file', cancel_path, '--'}, parts];
arguments_list = java.util.ArrayList;
for i = 1:numel(command), arguments_list.add(java.lang.String(char(string(command{i})))); end
builder = java.lang.ProcessBuilder(arguments_list);
builder.environment().put('NEUROPAL_JOB_TOKEN', owner.Token);
builder.environment().put('NEUROPAL_PARENT_PID', num2str(feature('getpid')));
settings = {'NEUROPAL_JOB_LOCK', 'NEUROPAL_MAX_JOB_MIB', ...
    'NEUROPAL_MOE_WORKSPACE_MIB', 'NEUROPAL_ROUTER_MIB', 'NEUROPAL_IMAGE_MAX_MIB'};
for i = 1:numel(settings)
    value = getenv(settings{i});
    if ~isempty(value), builder.environment().put(settings{i}, value); end
end
if strlength(options.WorkingDirectory) > 0
    builder.directory(java.io.File(char(options.WorkingDirectory)));
end
builder.redirectErrorStream(true);
builder.redirectOutput(java.io.File(log_path));
if ~isempty(options.CancelFcn) && options.CancelFcn()
    error('Wrapper:ProcessCancelled', 'Operation canceled.');
end
process = builder.start();
owner.Process = process;
started = tic;
offset = 0;
pending = '';
output = '';
while true
    [chunk, offset] = local_read(log_path, offset);
    output = [output chunk]; %#ok<AGROW>
    output = output(max(1,end-65535):end);
    pending = [pending chunk]; %#ok<AGROW>
    boundary = find(pending == newline, 1, 'last');
    if ~isempty(boundary)
        completed = pending(1:boundary);
        pending = pending(boundary+1:end);
        messages = regexp(completed, 'NEUROPAL_PROGRESS:([^\r\n]+)', 'tokens');
        if ~isempty(options.ProgressFcn)
            for i = 1:numel(messages), options.ProgressFcn(messages{i}{1}); end
        end
    end
    pending = pending(max(1,end-4095):end);
    if ~process.isAlive(), break; end
    if ~isempty(options.CancelFcn) && options.CancelFcn()
        error('Wrapper:ProcessCancelled', 'Operation canceled.');
    end
    if toc(started) > options.TimeoutSeconds
        error('Wrapper:ProcessTimeout', 'Operation timed out. See %s.', log_path);
    end
    drawnow limitrate;
    pause(0.1);
end
% Drain a final bounded tail after the process closes its output stream.
metadata = dir(log_path);
[output, ~] = local_read(log_path, max(0,metadata.bytes-65536));
status = process.exitValue();
if status == 124
    error('Wrapper:ProcessTimeout', 'Operation timed out. See %s.', log_path);
elseif status == 130
    error('Wrapper:ProcessCancelled', 'Operation canceled. See %s.', log_path);
end

end

function [text, offset] = local_read(path, offset)
fid = fopen(path, 'r');
if fid < 0, text = ''; return; end
cleanup = onCleanup(@() fclose(fid));
fseek(fid, offset, 'bof');
text = fread(fid, 65536, '*char')';
offset = ftell(fid);
end
