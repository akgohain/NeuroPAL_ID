function test_processing_transaction()
%TEST_PROCESSING_TRANSACTION Preserve sources and completed files on failures.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));
source_path = fullfile(root, 'source.mat');
requested = fullfile(root, 'source_processed.mat');
data = reshape(uint16(1:120), [4 5 3 2]);
original = data;
info = struct('scale', [0.4 0.6 1.5]);
prefs = struct('gamma', 0.8, 'RGBW', [1 2 2 1]);
version = 1;
save(source_path, 'data', 'info', 'prefs', 'version', '-v7.3');
data = uint8(73);
save(requested, 'data', '-v7.3');
metadata = DataHandling.Helpers.npal_mat.load_fields(source_path, false);
result = DataHandling.Helpers.process_mat_transaction(source_path, requested, ...
    metadata, @(slice) slice(:, end:-1:1, :, :), 3:-1:1);
assert(strcmp(result.path, fullfile(root, 'source_processed_002.mat')));
loaded = load(result.path, 'data', 'info', 'prefs');
assert(isequal(loaded.data, original(:, end:-1:1, end:-1:1, :)));
assert(isequal(loaded.info, info) && isequal(loaded.prefs, prefs));
assert(strcmp(class(loaded.data), 'uint16'));
assert_previous_files();

% Cancellation occurs after work starts, without leaving a completed-looking output.
calls = 0;
cancel_path = fullfile(root, 'cancelled.mat');
assert_error(@() DataHandling.Helpers.process_mat_transaction(source_path, ...
    cancel_path, metadata, @count_transform, 1:3, [], 'CancelFcn', @cancel_requested), ...
    'DataHandling:Processing:Cancelled');
assert(calls == 2 && ~isfile(cancel_path));
assert_previous_files();

calls = 0;
failure_path = fullfile(root, 'failed.mat');
assert_error(@() DataHandling.Helpers.process_mat_transaction(source_path, ...
    failure_path, metadata, @failing_transform, 1:3), 'NeuroPAL:Test:TransformFailed');
assert(~isfile(failure_path));
assert_previous_files();

% A UI state check can abort before publishing while leaving saved data intact.
calls = 0;
state_path = fullfile(root, 'state_changed.mat');
assert_error(@() DataHandling.Helpers.process_mat_transaction(source_path, ...
    state_path, metadata, @count_transform, 1:3, [], 'CheckFcn', @check_state), ...
    'DataHandling:Processing:StateChanged');
assert(~isfile(state_path));
assert_previous_files();

% Processing an existing result must not unlink its own input.
again = DataHandling.Helpers.process_mat_transaction(result.path, result.path, ...
    metadata, @(slice) slice, 1:3);
assert(~strcmp(again.path, result.path));
assert(isequal(load(again.path, 'data'), load(result.path, 'data')));
assert_previous_files();
fprintf('PROCESSING_TRANSACTION=PASS\n');

    function assert_previous_files()
        source = load(source_path, 'data');
        previous = load(requested, 'data');
        assert(isequal(source.data, original));
        assert(isequal(previous.data, uint8(73)));
        assert(isempty(dir(fullfile(root, '.*.npal-partial*'))));
    end

    function slice = count_transform(slice)
        calls = calls + 1;
    end

    function cancelled = cancel_requested()
        cancelled = calls >= 2;
    end

    function slice = failing_transform(slice)
        calls = calls + 1;
        if calls == 2
            error('NeuroPAL:Test:TransformFailed', 'Synthetic processing failure.');
        end
    end

    function check_state()
        if calls >= 2
            error('DataHandling:Processing:StateChanged', 'Synthetic UI state change.');
        end
    end
end

function assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), 'Expected %s; received %s.', identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', 'Expected %s.', identifier);
end
