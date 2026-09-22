function response = runMultiChannelCentroids(volume, channel_indices, scale_um_xyz, options)
%RUNMULTICHANNELCENTROIDS Detect selected channels independently and merge centers.
arguments
    volume
    channel_indices double
    scale_um_xyz double
    options.Backend (1,1) string = "moe"
    options.MergeRadiusUm (1,1) double = 2
    options.SourceMetadata (1,1) struct = struct()
    options.OutputDir (1,1) string = ""
    options.ProgressFcn = []
    options.CancelFcn = []
    options.DetectFcn = @Wrapper.runMoECentroids
end
channels=channel_indices(:)'; scale=scale_um_xyz(:)';
if isempty(channels) || numel(unique(channels))~=numel(channels) || any(~isfinite(channels) | channels<0 | channels~=round(channels) | channels>=size(volume,4))
    error('Wrapper:MultiChannelSelection','Select distinct channels within this recording.');
end
if isempty(volume) || ndims(volume)>4 || numel(scale)~=3 || any(~isfinite(scale) | scale<=0) || ...
        ~isfinite(options.MergeRadiusUm) || options.MergeRadiusUm<0 || ~any(options.Backend==["moe","spotiflow"])
    error('Wrapper:MultiChannelInput','Supply a valid recording, detector, spacing and merge distance.');
end
channels=sort(channels); job=Program.HeavyJob.acquire('Multi-channel detection'); cleanup=onCleanup(@() delete(job));
centers=zeros(0,3); scores=zeros(0,1); origins=zeros(0,1); runs=cell(1,numel(channels)); blank=[];
for i=1:numel(channels)
    check_cancel(options.CancelFcn);
    channel=channels(i); plane=volume(:,:,:,channel+1);
    if any(~isfinite(plane),'all'), error('Wrapper:MultiChannelInput','C%d contains nonfinite intensities.',channel); end
    if ~isempty(options.ProgressFcn), options.ProgressFcn(sprintf('Detecting C%d (%d of %d)',channel,i,numel(channels))); end
    if ~any(plane>0,'all')
        blank(end+1)=channel; runs{i}=struct('channel_index',channel,'skipped','no_positive_signal'); continue;
    end
    metadata=options.SourceMetadata; metadata.channel_index=channel; metadata.selected_channels=channels;
    result=options.DetectFcn(plane,scale,'Backend',options.Backend,'InputMode',"single_channel", ...
        'SourceMetadata',metadata,'OutputDir',options.OutputDir,'ProgressFcn',options.ProgressFcn,'CancelFcn',options.CancelFcn,'JobToken',job.Token);
    bounds=[size(volume,1),size(volume,2),size(volume,3)];
    if isempty(result.centroids_yxz), result.centroids_yxz=zeros(0,3); end
    if size(result.centroids_yxz,2)~=3 || size(result.centroids_yxz,1)~=numel(result.scores) || ...
            result.num_centroids~=numel(result.scores) || any(~isfinite(result.centroids_yxz),'all') || ...
            any(result.centroids_yxz<1 | result.centroids_yxz>=bounds+1,'all') || ...
            any(~isfinite(result.scores) | result.scores<0 | result.scores>1,'all')
        error('Wrapper:MultiChannelResponse','C%d returned invalid detections.',channel);
    end
    centers=[centers;result.centroids_yxz]; scores=[scores;result.scores(:)]; origins=[origins;repmat(channel,result.num_centroids,1)];
    runs{i}=result;
end
check_cancel(options.CancelFcn);
response=Wrapper.mergeChannelDetections(centers,scores,origins,scale,options.MergeRadiusUm);
response.input_mode='multi_channel'; response.backend=char(options.Backend); response.selected_channels=channels;
response.merge_radius_um=options.MergeRadiusUm; response.merge_policy='strongest_center_cross_channel_one_to_one';
response.score_policy='score_of_retained_detection'; response.skipped_channels=blank;
response.source_metadata=options.SourceMetadata; response.channel_runs=runs;
response.input_adaptation='independent_single_channel_inference'; response.multi_channel_unvalidated=true;
response.raw_centroids_yxz=centers; response.raw_scores=scores; response.raw_channels=origins;
if strlength(options.OutputDir)>0
    output=char(options.OutputDir); if ~isfolder(output), mkdir(output); end
    output=tempname(output); mkdir(output); response.output_dir=output;
    fid=fopen(fullfile(output,'response.json'),'w');
    if fid<0, error('Wrapper:MultiChannelWrite','Cannot write merged detection results.'); end
    file_cleanup=onCleanup(@() fclose(fid)); fwrite(fid,jsonencode(response),'char');
end
end
function check_cancel(callback)
if ~isempty(callback) && callback(), error('Wrapper:MoECancelled','Detection canceled; existing annotations were preserved.'); end
end
