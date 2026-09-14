function test_debug_array_summary()
%TEST_DEBUG_ARRAY_SUMMARY Check diagnostic sampling without opening the app.

old_debug = getenv('NPAL_DEBUG');
cleanup = onCleanup(@() setenv('NPAL_DEBUG',old_debug));
setenv('NPAL_DEBUG','1');

fixtures = {reshape(uint16(1:120),4,5,6), ...
    reshape(uint16(mod(1:200006,4096)),2,100003), ...
    single([NaN Inf -Inf 0 1])};
for i = 1:numel(fixtures)
    arr = fixtures{i};
    values = double(arr(:));
    if numel(values) > 1e5
        values = values(round(linspace(1,numel(values),1e5)));
    end
    expected = sprintf('fixture: size=%s class=%s min=%g max=%g mean=%g', ...
        mat2str(size(arr)),class(arr),min(values),max(values),mean(values));
    output = evalc('Program.Helpers.debug_array_summary(''Test'',''fixture'',arr);');
    assert(contains(output,expected));
end

output = evalc('Program.Helpers.debug_array_summary(''Test'',''fixture'',[]);');
assert(contains(output,'fixture: empty'));
setenv('NPAL_DEBUG','0');
output = evalc('Program.Helpers.debug_array_summary(''Test'',''fixture'',arr);');
assert(isempty(output));
fprintf('DEBUG_ARRAY_SUMMARY=PASS\n');
end
