function test_python_process(python)
%TEST_PYTHON_PROCESS Verify live worker output, cancellation, and bounded tails.
arguments
    python (1,1) string = ""
end
if strlength(python) == 0
    python = "python3";
    if ispc, python = "python"; end
end
directory = tempname;
mkdir(directory);
cleanup = onCleanup(@() rmdir(directory,'s'));
received = {};
[status, output] = Wrapper.runPythonProcess({char(python), '-c', ...
    'print("NEUROPAL_PROGRESS:ready", flush=True); print("x"*200000); print("finished")'}, ...
    'LogPath', fullfile(directory,'success.log'), 'ProgressFcn', @capture);
assert(status == 0 && endsWith(strtrim(output),'finished'));
assert(numel(output) <= 65536);
assert(any(strcmp(received,'ready')));
assert_error(@() Wrapper.runPythonProcess({char(python),'-c','import time; time.sleep(30)'}, ...
    'LogPath', fullfile(directory,'cancel.log'), 'CancelFcn', @() true), 'Wrapper:ProcessCancelled');
assert_error(@() Wrapper.runPythonProcess({char(python),'-c','import time; time.sleep(30)'}, ...
    'LogPath', fullfile(directory,'timeout.log'), 'TimeoutSeconds',0.3), 'Wrapper:ProcessTimeout');
assert_error(@() Wrapper.runPythonProcess({char(python), '-c', ...
    'import time; print("NEUROPAL_PROGRESS:cancel-ready", flush=True); time.sleep(30)'}, ...
    'LogPath',fullfile(directory,'running-cancel.log'), 'ProgressFcn', @capture, ...
    'CancelFcn', @cancel_requested), 'Wrapper:ProcessCancelled');
job = Program.HeavyJob.acquire('wrapper parent');
job_cleanup = onCleanup(@() delete(job));
[status,~] = Wrapper.runPythonProcess({char(python),'-c','print("nested")'}, ...
    'LogPath',fullfile(directory,'nested.log'),'JobToken',job.Token);
assert(status == 0);
fprintf('PYTHON_PROCESS=PASS\n');
    function value = cancel_requested()
        value = any(strcmp(received,'cancel-ready'));
    end
    function capture(message)
        received{end+1} = message;
    end
end

function assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier,identifier), 'Expected %s; got %s.',identifier,ME.identifier);
    return
end
error('Expected %s.',identifier);
end
