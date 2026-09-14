function test_autoid_resource_cleanup()
%TEST_AUTOID_RESOURCE_CLEANUP Check ownership and exception cleanup with fakes.

old_path = path;
path_cleanup = onCleanup(@() path(old_path));
addpath(fullfile(fileparts(mfilename('fullpath')),'fixtures'));
old_warning = warning('off','Methods:AutoId:FutureCleanup');
warning_cleanup = onCleanup(@() warning(old_warning));

for owns_pool = [false true]
    for fail_job = [false true]
        record = containers.Map('KeyType','char','ValueType','double');
        pool = AlignmentResourceFixture(record,'pool');
        try
            local_job(pool,owns_pool,record,fail_job);
            assert(~fail_job);
        catch ME
            assert(fail_job && strcmp(ME.identifier,'NeuroPAL:Test:AlignmentFailure'));
        end
        assert(record('first_cancel') == 1 && record('second_cancel') == 1);
        assert(record('pool_delete') == double(owns_pool));
        assert(isvalid(pool) == ~owns_pool);
        if isvalid(pool), delete(pool); end
    end
end
fprintf('AUTOID_RESOURCE_CLEANUP=PASS\n');
end

function local_job(pool,owns_pool,record,fail_job)
pool_cleanup = onCleanup(@() Methods.AutoId.close_alignment_pool(pool,owns_pool));
future = AlignmentResourceFixture(record,'first');
first_cleanup = onCleanup(@() Methods.AutoId.cancel_alignment_future(future));
future = AlignmentResourceFixture(record,'second');
future.fail_cancel = fail_job;
second_cleanup = onCleanup(@() Methods.AutoId.cancel_alignment_future(future));
if fail_job
    error('NeuroPAL:Test:AlignmentFailure','Injected alignment failure.');
end
clear first_cleanup second_cleanup pool_cleanup
end
