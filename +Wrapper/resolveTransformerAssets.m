function [repo_dir, checkpoint_path] = resolveTransformerAssets(repo_option, checkpoint_option)
%RESOLVETRANSFORMERASSETS Resolve Anshita GAT code and weights portably.

arguments
    repo_option (1,1) string = ""
    checkpoint_option (1,1) string = ""
end

project_root = fileparts(fileparts(mfilename('fullpath')));
workspace_root = fileparts(project_root);

if strlength(strtrim(repo_option)) > 0
    repo_dir = char(repo_option);
else
    repo_dir = local_first_existing({ ...
    getenv('NEUROPAL_GAT_REPO'), ...
    fullfile(workspace_root, 'GAT-NeuroPAL'), ...
    fullfile(project_root, 'External_Dependencies', 'GAT-NeuroPAL')});
end

if strlength(strtrim(checkpoint_option)) > 0
    checkpoint_path = char(checkpoint_option);
else
    checkpoint_path = local_first_existing({ ...
    getenv('NEUROPAL_GAT_CHECKPOINT'), ...
    getenv('NEUROPAL_TRANSFORMER_CHECKPOINT'), ...
    fullfile(workspace_root, 'artifacts', 'anshita_transformer'), ...
    fullfile(project_root, 'artifacts', 'anshita_transformer')});
end
end

function value = local_first_existing(candidates)
value = '';
for i = 1:numel(candidates)
    candidate = strtrim(char(string(candidates{i})));
    if isempty(candidate)
        continue
    end
    if isempty(value)
        value = candidate;
    end
    if exist(candidate, 'file') == 2 || exist(candidate, 'dir') == 7
        value = candidate;
        return
    end
end
end
