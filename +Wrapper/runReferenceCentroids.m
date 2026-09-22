function response = runReferenceCentroids(volume, scale_um_xyz, options)
%RUNREFERENCECENTROIDS Detect a large reference in overlapping, bounded tiles.
arguments
    volume
    scale_um_xyz double
    options.Backend (1,1) string = "moe"
    options.OutputDir (1,1) string = ""
    options.ProgressFcn = []
    options.CancelFcn = []
end
scale=double(scale_um_xyz(:)'); shape=[size(volume,1) size(volume,2) size(volume,3)];
if numel(scale)~=3 || any(~isfinite(scale) | scale<=0) || isempty(volume) || size(volume,4)~=4 || ndims(volume)>4
    error('Tracking:ReferenceVolume','Supply an RGBW volume and three positive voxel spacings.');
end
setting=getenv('NEUROPAL_MOE_WORKSPACE_MIB'); limit=4096;
if ~isempty(setting), limit=str2double(setting); end
if ~isfinite(limit) || limit<=1536, error('Tracking:ReferenceBudget','The detector workspace budget must exceed 1536 MiB.'); end
spacing=scale([2 1 3]); target_spacing=[.4 .4 1.5];
estimate=@(dims) prod(dims)*4*4*4+prod(max(1,ceil(dims.*spacing./target_spacing)))*4*4*12+1536*2^20;
% Keep halo context around each owned region; process only one tile at a time.
halo=max(8,ceil(12.8./spacing)); cores={[ones(1,3);shape]};
i=1;
while i<=numel(cores)
    core=cores{i}; first=max(1,core(1,:)-halo); last=min(shape,core(2,:)+halo);
    if estimate(last-first+1)<=limit*2^20, i=i+1; continue; end
    [extent,dimension]=max(core(2,:)-core(1,:)+1);
    if extent<=2*halo(dimension)+1, error('Tracking:ReferenceBudget','This reference cannot be tiled within the detector workspace budget.'); end
    middle=floor(mean(core(:,dimension))); left=core; right=core;
    left(2,dimension)=middle; right(1,dimension)=middle+1;
    cores(i)=[]; cores=[cores(1:i-1) {left right} cores(i:end)];
end
centers=zeros(0,3); scores=zeros(0,1); tiles=zeros(0,1); provenance=cell(size(cores));
for i=1:numel(cores)
    if ~isempty(options.CancelFcn) && options.CancelFcn(), error('Wrapper:MoECancelled','Detection canceled; previous results were kept.'); end
    if ~isempty(options.ProgressFcn), options.ProgressFcn(sprintf('Detecting NeuroPAL tile %d of %d',i,numel(cores))); end
    core=cores{i}; first=max(1,core(1,:)-halo); last=min(shape,core(2,:)+halo);
    tile=volume(first(1):last(1),first(2):last(2),first(3):last(3),:);
    detected=Wrapper.runMoECentroids(tile,scale,'Backend',options.Backend,'InputMode','rgbw','DatasetID','unknown', ...
        'OutputDir',options.OutputDir,'KeepArtifacts',false,'CancelFcn',options.CancelFcn,'ProgressFcn',options.ProgressFcn);
    xyz=detected.centroids_yxz+first-1;
    % Ownership is disjoint even when the image context overlaps.
    keep=all(xyz>=core(1,:)-.5 & xyz<core(2,:)+.5,2);
    centers=[centers;xyz(keep,:)]; scores=[scores;detected.scores(keep)]; tiles=[tiles;repmat(i,nnz(keep),1)]; %#ok<AGROW>
    provenance{i}=struct('core_yxz',core,'read_yxz',[first;last],'metadata',rmfield(detected,{'centroids_yxz','scores'}));
end
merged=Wrapper.mergeChannelDetections(centers,scores,tiles,scale,1);
response=struct('centroids_yxz',merged.centroids_yxz,'scores',merged.scores,'num_centroids',merged.num_centroids, ...
    'tiles',{provenance},'tile_count',numel(cores),'halo_yxz',halo,'merge_radius_um',1,'workspace_budget_mib',limit);
end
