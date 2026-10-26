classdef Installer
    %INSTALLER Run an existing methods package without replacing system Python.
    methods (Static)
        function run(parent)
            if ~ismac || ~strcmp(computer('arch'),'maca64')
                uialert(parent,'Managed package installation currently supports Apple silicon Macs. You can select an existing compatible installation with Choose.','Install package'); return;
            end
            folder=uigetdir('','Choose the extracted NeuroPAL methods package');
            if isequal(folder,0), return; end
            script=fullfile(folder,'Setup-Mac.command');
            if ~isfile(script) || ~isfile(fullfile(folder,'SHA256SUMS')) || ~isfile(fullfile(folder,'PACKAGE_VERSION'))
                uialert(parent,'Choose the complete extracted methods package, including Setup-Mac.command, PACKAGE_VERSION and SHA256SUMS. A source clone does not contain the model archives.','Incomplete package'); return;
            end
            logdir=fullfile(fileparts(Runtime.Configuration.location()),'logs');
            if ~isfolder(logdir), mkdir(logdir); end
            log=fullfile(logdir,['setup-' char(java.util.UUID.randomUUID()) '.log']);
            progress=uiprogressdlg(parent,'Title','Installing methods package','Message','Preparing isolated runtimes. This can take several minutes.', ...
                'Indeterminate','on','Cancelable','on');
            cleanup=onCleanup(@() Runtime.Installer.close(progress));
            try
                job=Program.HeavyJob.acquire('Installing model runtimes');
                release=onCleanup(@() delete(job));
                args=java.util.ArrayList; args.add('/bin/bash'); args.add(script);
                builder=java.lang.ProcessBuilder(args); builder.directory(java.io.File(folder));
                builder.redirectErrorStream(true); builder.redirectOutput(java.io.File(log));
                process=builder.start(); stop=onCleanup(@() Runtime.Resolver.stop(process)); started=tic;
                while process.isAlive()
                    if ~isvalid(progress) || progress.CancelRequested, error('Runtime:Cancelled','Setup canceled. Verified completed components can be reused on retry.'); end
                    if toc(started)>3600, error('Runtime:InstallTimeout','Setup timed out. Completed components are retained.'); end
                    drawnow limitrate; pause(.15);
                end
                if process.exitValue()~=0, error('Runtime:InstallFailed','%s',Runtime.Resolver.tail(log)); end
                close(progress);
                uialert(parent,'Setup completed. Use detected to select and validate the installed components.','Methods installed','Icon','success');
            catch ME
                if isvalid(progress), close(progress); end
                uialert(parent,sprintf('%s\n\nSetup log: %s',ME.message,log),'Methods setup');
            end
        end
        function close(progress)
            if isvalid(progress), close(progress); end
        end
    end
end
