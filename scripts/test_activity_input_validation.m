function test_activity_input_validation(c)
%TEST_ACTIVITY_INPUT_VALIDATION Reject malformed sampling radii without losing results.
saved = c.Analysis.Controls.radius.Value;
cleanup = onCleanup(@() restore(c, saved));
rows = c.Rows; folder = c.ActivityDirectory;
for value = {'3 3 1 trailing', '3 0 1', '3 NaN 1', '3 3', ''}
    c.Analysis.Controls.radius.Value = value{1};
    c.render();
    try
        c.extractActivity();
        error('test:MissingError', 'Invalid radii were accepted.');
    catch ME
        assert(strcmp(ME.identifier, 'Tracking:ActivityRadius'), ME.message);
    end
    assert(isequal(c.Rows, rows) && strcmp(c.ActivityDirectory, folder));
end
fprintf('ACTIVITY_RADIUS_VALIDATION_NO_MUTATION=PASS\n');
end

function restore(c, value)
c.Analysis.Controls.radius.Value = value;
c.render();
end
