function assert_main_job_context(app, expected)
%ASSERT_MAIN_JOB_CONTEXT Refuse results belonging to a replaced input.

watch_annotations = true;
if isfield(expected, 'watch_annotations'), watch_annotations = expected.watch_annotations; end
current = Program.Helpers.main_job_context(app, expected.include_neurons, watch_annotations);
if ~isequaln(current, expected)
    error('Program:HeavyJob:SourceChanged', ...
        'The image or annotations changed during the operation. Run it again on the current image.');
end
end
