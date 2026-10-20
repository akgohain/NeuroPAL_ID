function geometry = processing_default_geometry(snapshot, source_key, dims3)
% Keep saved downsample settings within their own source volume.
dims3 = max(1,round(double(dims3(1:3))));
geometry = struct('xy_factor',1,'z_slices',dims3(3),'source_matches',false);
if ~isstruct(snapshot) || ~isscalar(snapshot) || ...
        ~isfield(snapshot,'source_key') || ~isequal(snapshot.source_key,source_key)
    return;
end
geometry.source_matches = true;
if isfield(snapshot,'xy_factor') && isnumeric(snapshot.xy_factor) && ...
        isscalar(snapshot.xy_factor) && isreal(snapshot.xy_factor) && isfinite(snapshot.xy_factor)
    geometry.xy_factor = min(1,max(1/max(dims3(1:2)),double(snapshot.xy_factor)));
end
if isfield(snapshot,'z_slices') && isnumeric(snapshot.z_slices) && ...
        isscalar(snapshot.z_slices) && isreal(snapshot.z_slices) && isfinite(snapshot.z_slices)
    geometry.z_slices = min(dims3(3),max(1,round(double(snapshot.z_slices))));
end
end
