function report = run_ui_audit()
%RUN_UI_AUDIT Capture deterministic UI screenshots and layout diagnostics.

repo_root = fileparts(fileparts(mfilename('fullpath')));
cd(repo_root);
addpath(repo_root);

output_dir = getenv('NPAL_UI_AUDIT_OUTPUT');
fixture = getenv('NPAL_UI_AUDIT_FIXTURE');

if isempty(output_dir)
    output_dir = fullfile(repo_root, '.ui_artifacts', ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
end

report = Program.Dev.UIHarness.run( ...
    'OutputDir', output_dir, ...
    'Fixture', fixture);
end
