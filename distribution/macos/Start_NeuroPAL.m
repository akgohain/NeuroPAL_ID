% Start the packaged NeuroPAL ID application with its installed models.
folder = fileparts(mfilename('fullpath'));
launcher = fullfile(folder, 'installed_launcher.m');
if ~isfile(launcher)
    error('NeuroPAL:SetupRequired', ...
        'Run Setup-Mac.command or Setup-with-Auto-ID.command before starting this package.');
end
run(launcher);
