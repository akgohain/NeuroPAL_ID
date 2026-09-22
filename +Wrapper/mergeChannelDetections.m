function result = mergeChannelDetections(centers, scores, channels, scale_um_xyz, radius_um)
%MERGECHANNELDETECTIONS Keep the strongest center among cross-channel matches.
scale=double(scale_um_xyz(:)'); scores=double(scores(:)); channels=double(channels(:));
if size(centers,2)~=3 || size(centers,1)~=numel(scores) || numel(scores)~=numel(channels) || ...
        any(~isfinite(centers),'all') || any(~isfinite(scores) | scores<0 | scores>1) || ...
        any(~isfinite(channels) | channels<0 | channels~=round(channels)) || ...
        numel(scale)~=3 || any(~isfinite(scale) | scale<=0) || ~isscalar(radius_um) || ~isfinite(radius_um) || radius_um<0
    error('Wrapper:MultiChannelMerge','Invalid channel detections, spacing or merge distance.');
end
n=numel(scores); selected=zeros(0,1); supports=cell(0,1); members=cell(0,1);
% Break ties by channel and position so channel-selection order does not matter.
[~,order]=sortrows([-scores,channels,centers],[1 2 3 4 5]);
physical=double(centers).*scale([2 1 3]); assigned=false(n,1);
for i=1:n
    anchor=order(i); if assigned(anchor), continue; end
    group=anchor; assigned(anchor)=true;
    nearby=order(~assigned(order) & sum((physical(order,:)-physical(anchor,:)).^2,2)<=radius_um^2);
    available=setdiff(unique(channels(nearby)),channels(anchor));
    for channel=reshape(available,1,[])
        matches=nearby(channels(nearby)==channel);
        % At most one proposal per channel; no transitive chain merging.
        [~,nearest]=min(sum((physical(matches,:)-physical(anchor,:)).^2,2));
        match=matches(nearest); group(end+1)=match; assigned(match)=true;
    end
    selected(end+1,1)=anchor; supports{end+1,1}=sort(channels(group))'; members{end+1,1}=group;
end
result=struct('centroids_yxz',double(centers(selected,:)),'scores',scores(selected),'num_centroids',numel(selected), ...
    'source_channels',channels(selected),'support_channels',{supports},'member_indices',{members});
end
