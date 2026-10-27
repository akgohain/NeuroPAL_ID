function [repo_dir, checkpoint_path] = resolveTransformerAssets(repo_option, checkpoint_option)
%RESOLVETRANSFORMERASSETS Resolve Anshita GAT code and weights portably.

arguments
    repo_option (1,1) string = ""
    checkpoint_option (1,1) string = ""
end

profile = Runtime.Discovery.profile('anshita_gat');

if strlength(strtrim(repo_option)) > 0
    repo_dir = char(repo_option);
else
    repo_dir = profile.source;
end

if strlength(strtrim(checkpoint_option)) > 0
    checkpoint_path = char(checkpoint_option);
else
    checkpoint_path = profile.checkpoint;
end
end
