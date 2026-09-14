function assert_main_job_context(app, expected)
%ASSERT_MAIN_JOB_CONTEXT Refuse results belonging to a replaced input.

current = Program.Helpers.main_job_context(app, expected.include_neurons);
if ~isequaln(current, expected)
    error('Program:HeavyJob:SourceChanged', ...
        'The image or annotations changed during the operation. Run it again on the current image.');
end
end
