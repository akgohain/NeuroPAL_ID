repo_root = fileparts(fileparts(mfilename('fullpath')));
cd(repo_root);

app_path = fullfile(repo_root, 'visualize_light.mlapp');
if exist(app_path, 'file') ~= 2
    error('NeuroPAL:MissingApp', 'Could not find %s', app_path);
end

addpath(repo_root);
app = visualize_light;

% Keep an explicit reference in the base workspace. App Designer normally
% registers the app, but retaining the object makes development launches
% deterministic and gives diagnostics/UI tooling a stable handle.
assignin('base', 'NEUROPAL_DEV_APP', app);
