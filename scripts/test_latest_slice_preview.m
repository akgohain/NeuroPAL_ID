function test_latest_slice_preview()
%TEST_LATEST_SLICE_PREVIEW Verify coalescing, release ordering and cleanup.
owner = figure('Visible', 'off');
cleanup = onCleanup(@() delete(owner));
values = [];
committed = [];
revision = 1;
previous = numel(timerfindall('Name', 'NeuroPAL main slice preview'));
controller = Program.LatestSlicePreview(@record_preview, @record_commit, @get_revision, owner);
controller_cleanup = onCleanup(@() delete(controller));

% A burst schedules one preview of the latest position.
for z = [2 15 30 4 19 7]
    controller.request(z);
end
assert(isempty(values));
controller.flush();
assert(isequal(values, 7));

% Release cancels scheduled work before committing its final value.
controller.request(30);
controller.finish([], struct('Value', 12));
controller.flush();
pause(0.1);
assert(isequal(values, 7) && isequal(committed, 12));

% A later gesture works, but pending work cannot cross an image change.
controller.request(6);
revision = 2;
controller.flush();
assert(isequal(values, 7));
controller.request(9);
started = tic;
while numel(values) < 2 && toc(started) < 2
    pause(0.02);
end
assert(isequal(values, [7 9]));

% Closing the owner removes its pending timer and controller.
controller.request(18);
delete(owner);
assert(~isvalid(controller));
assert(numel(timerfindall('Name', 'NeuroPAL main slice preview')) == previous);
fprintf('LATEST_SLICE_PREVIEW=PASS\n');

    function value = get_revision()
        value = revision;
    end
    function record_preview(value)
        values(end+1) = value;
    end
    function record_commit(~, event)
        committed = event.Value;
    end
end
