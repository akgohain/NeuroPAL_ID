function report = run_large_file_audit()
%RUN_LARGE_FILE_AUDIT Exercise transactional NWB cancellation and resume.

source_file = getenv('NPAL_LARGE_FILE_FIXTURE');
if isempty(source_file)
    error('NeuroPAL:LargeFileAudit:FixtureRequired', ...
        'Set NPAL_LARGE_FILE_FIXTURE to an NWB file.');
end

output_dir = getenv('NPAL_LARGE_FILE_OUTPUT');
if isempty(output_dir)
    output_dir = fullfile(pwd, '.ui_artifacts', 'large-file-audit');
end

report = Program.Dev.LargeFileHarness.run(source_file, output_dir);
end
