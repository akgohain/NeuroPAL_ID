classdef Checkpoint
    %CHECKPOINT Keep inference outputs out of a shared, possibly read-only model.
    methods (Static)
        function folder = stage(source,folder)
            if isfolder(source), weights=fullfile(source,'best_model.pt'); else, weights=char(source); end
            config=fullfile(fileparts(weights),'train_config.json');
            if ~isfolder(folder), mkdir(folder); end
            [ok,message]=copyfile(weights,fullfile(folder,'best_model.pt'));
            if ~ok, error('Runtime:Checkpoint','Cannot stage GAT weights: %s',message); end
            [ok,message]=copyfile(config,fullfile(folder,'train_config.json'));
            if ~ok, error('Runtime:Checkpoint','Cannot stage GAT configuration: %s',message); end
        end
    end
end
