% Start the packaged NeuroPAL ID application with its installed models.
folder = fileparts(mfilename('fullpath'));
launcher = fullfile(folder, 'installed_launcher.m');
if ~isfile(launcher)
    root=fileparts(fileparts(folder));
    if isfile(fullfile(root,'visualize_light.mlapp'))
        addpath(root,'-begin'); app=visualize_light; return;
    end
    error('NeuroPAL:SetupRequired', ...
        'Run Setup-Mac.command or Setup-with-Auto-ID.command before starting this package.');
end
run(launcher);
