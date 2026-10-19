function test_multichannel_detection()
%TEST_MULTICHANNEL_DETECTION Check physical matching and channel isolation.
p=[10 10 10;10 10.5 10;10 10.2 10]; scores=[.9;.8;.7]; channels=[0;2;0];
r=Wrapper.mergeChannelDetections(p,scores,channels,[.4 .4 1.5],1);
assert(r.num_centroids==2 && isequal(r.centroids_yxz,p([1 3],:)) && isequal(r.support_channels{1},[0 2]));
reverse=Wrapper.mergeChannelDetections(flipud(p),flipud(scores),flipud(channels),[.4 .4 1.5],1);
assert(isequal(r.centroids_yxz,reverse.centroids_yxz) && isequal(r.support_channels,reverse.support_channels));
r=Wrapper.mergeChannelDetections([1 1 1;1 1.5 1],[.9;.8],[0;0],[1 1 1],2); assert(r.num_centroids==2);
r=Wrapper.mergeChannelDetections([1 1 1;1 1 2],[.9;.8],[0;1],[1 1 5],2); assert(r.num_centroids==2);
r=Wrapper.mergeChannelDetections([1 1 1;1 2 1;1 3 1],[.9;.8;.7],[0;1;2],[1 1 1],1.1); assert(r.num_centroids==2);
r=Wrapper.mergeChannelDetections([1 1 1;1 1 1],[.9;.8],[0;1],[1 1 1],0); assert(r.num_centroids==1);
volume=zeros(20,20,20,5); volume(:,:,:,1)=1; volume(:,:,:,3)=2; volume(:,:,:,2)=NaN;
seen=[]; failure=false; cancel=false;
threshold=NaN;
parent=Program.HeavyJob.acquire('Main detection test');
Wrapper.runMultiChannelCentroids(volume,[0 2],[.4 .4 1.5],'JobToken',parent.Token,'DetectFcn',@fake);
delete(parent); seen=[];
r=Wrapper.runMultiChannelCentroids(volume,[4 2 0],[.4 .4 1.5],'DetectFcn',@fake);
assert(isequal(seen,[0 2]) && r.num_centroids==1 && isequal(r.support_channels{1},[0 2]) && isequal(r.skipped_channels,4));
assert(isequal(r.source_channels,0) && numel(r.channel_runs)==3);
threshold=.2; Wrapper.runMultiChannelCentroids(volume,[0 2],[.4 .4 1.5],'DetectFcn',@fake,'ScoreThreshold',threshold); threshold=NaN;
seen=[]; single=Wrapper.runMultiChannelCentroids(volume,2,[.4 .4 1.5],'DetectFcn',@fake);
assert(single.num_centroids==1 && isequal(seen,2) && single.source_channels==2);
seen=[]; empty=Wrapper.runMultiChannelCentroids(volume,4,[.4 .4 1.5],'DetectFcn',@fake);
assert(empty.num_centroids==0 && isempty(seen));
expect(@() Wrapper.runMultiChannelCentroids(volume,[0 0],[1 1 1],'DetectFcn',@fake),'Wrapper:MultiChannelSelection');
expect(@() Wrapper.runMultiChannelCentroids(volume,5,[1 1 1],'DetectFcn',@fake),'Wrapper:MultiChannelSelection');
expect(@() Wrapper.runMultiChannelCentroids(volume,[0 2],[1 1 1],'DetectFcn',@fake,'ScoreThreshold',1.1),'Wrapper:MoEInvalidThreshold');
failure=true; expect(@() Wrapper.runMultiChannelCentroids(volume,[0 2],[1 1 1],'DetectFcn',@fake),'test:ExpertFailure');
failure=false; cancel=true; seen=[];
expect(@() Wrapper.runMultiChannelCentroids(volume,[0 2],[1 1 1],'DetectFcn',@fake,'CancelFcn',@cancelled),'Wrapper:MoECancelled');
assert(isequal(seen,0));
fprintf('MULTICHANNEL_MERGE_ISOLATION_FAILURE_CANCEL=PASS\n');
    function value=cancelled()
        value=cancel && ~isempty(seen);
    end
    function result=fake(plane,~,varargin)
        options=struct(varargin{:}); channel=options.SourceMetadata.channel_index; seen(end+1)=channel;
        assert(all(plane(:)==channel/2+1) && strcmp(options.InputMode,'single_channel'));
        assert(isequaln(options.ScoreThreshold,threshold));
        if failure && channel==2, error('test:ExpertFailure','Injected failure'); end
        result=struct('centroids_yxz',[10 10 10],'scores',.9-channel*.05,'num_centroids',1,'source_metadata',options.SourceMetadata);
    end
end
function expect(callback,identifier)
try, callback(); catch ME, assert(strcmp(ME.identifier,identifier),ME.message); return; end
error('test:MissingError','Expected %s',identifier);
end
