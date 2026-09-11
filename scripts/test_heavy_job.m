function test_heavy_job()
%TEST_HEAVY_JOB Check app admission and cross-process lease ownership.
previous_path = getenv('NEUROPAL_JOB_LOCK');
previous_token = getenv('NEUROPAL_JOB_TOKEN');
path = tempname;
cleanup = onCleanup(@() restore(previous_path, previous_token, path));
setenv('NEUROPAL_JOB_LOCK', path);
setenv('NEUROPAL_JOB_TOKEN', '');
Program.HeavyJob.assertIdle();
job = Program.HeavyJob.acquire('test');
job_cleanup = onCleanup(@() delete(job));
owner = jsondecode(fileread([path '.owner.json']));
assert(strcmp(owner.token,job.Token));
assert(owner.pid == feature('getpid'));
try
    Program.HeavyJob.assertIdle();
    error('Expected source mutation rejection.');
catch ME
    assert(strcmp(ME.identifier,'Program:HeavyJob:Busy'));
end
Program.HeavyJob.assertIdle(job.Token);
try
    Program.HeavyJob.acquire('duplicate');
    error('Expected busy job rejection.');
catch ME
    assert(strcmp(ME.identifier,'Program:HeavyJob:Busy'));
end
child = Program.HeavyJob.acquire('child', job.Token);
assert(strcmp(child.Token,job.Token));
assert(local_python_lease(path, '') ~= 0);
assert(local_python_lease(path, job.Token) == 0);
delete(child);
clear job_cleanup
Program.HeavyJob.assertIdle();
next = Program.HeavyJob.acquire('next');
delete(next);
test_context();
fprintf('HEAVY_JOB=PASS\n');
end

function test_context()
app = struct('image_file','fixture.mat', 'image_data',zeros(2,3,4,4,'uint8'), ...
    'image_um_scale',[1 1 2], 'image_prefs',struct('RGBW',1:4), ...
    'worm',struct('body','Head'), 'image_neurons',[]);
expected = Program.Helpers.main_job_context(app,true);
Program.Helpers.assert_main_job_context(app,expected);
changes = {app,app,app,app,app};
changes{1}.image_file = 'different.mat';
changes{2}.image_data = zeros(3,3,4,4,'uint8');
changes{3}.image_um_scale = [1 1 3];
changes{4}.image_prefs.RGBW = [2 1 3 4];
changes{5}.worm.body = 'Tail';
for i = 1:numel(changes)
    try
        Program.Helpers.assert_main_job_context(changes{i},expected);
        error('Expected changed source rejection.');
    catch ME
        assert(strcmp(ME.identifier,'Program:HeavyJob:SourceChanged'));
    end
end
end

function restore(path, token, temporary)
setenv('NEUROPAL_JOB_LOCK',path);
setenv('NEUROPAL_JOB_TOKEN',token);
if exist(temporary,'file') == 2, delete(temporary); end
if exist([temporary '.owner.json'],'file') == 2, delete([temporary '.owner.json']); end
end

function status = local_python_lease(lock_path, token)
wrapper = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+Wrapper');
code = ['import sys; sys.path.insert(0,' jsonencode(wrapper) ...
    '); from resource_control import JobLease; lease=JobLease("test"); lease.__enter__(); lease.__exit__()'];
python = 'python3';
if ispc, python = 'python'; end
parts = {python, '-c', code};
command = java.util.ArrayList;
for i = 1:numel(parts), command.add(java.lang.String(parts{i})); end
builder = java.lang.ProcessBuilder(command);
builder.environment().put('NEUROPAL_JOB_LOCK', lock_path);
builder.environment().put('NEUROPAL_JOB_TOKEN', char(token));
process = builder.start();
status = process.waitFor();
end
