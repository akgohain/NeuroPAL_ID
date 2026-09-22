function test_processing_normalization(app)
% Normalization uses one channel range throughout the volume and rejects empty ranges.
setappdata(app.CELL_ID,'proc_normalize_background_percentile',0);
setappdata(app.CELL_ID,'proc_normalize_max_percentile',100);
data=zeros(10,10,3,2,'uint8');
data(2:9,2:9,:,1)=40; data(4:6,4:6,3,1)=200;
output=Methods.ChunkyMethods.apply_vol(app,'zscore',data);
assert(output(2,2,1,1)==output(2,2,3,1));
assert(output(2,2,1,1)<output(5,5,3,1));
assert(~any(output(:,:,:,2),'all'));
for values={[100 99.9],[1 0],[NaN 99.9],[-1 99.9]}
    failed=false;
    try
        Methods.Preprocess.normalize_frame(data,values{1}(1),values{1}(2));
    catch ME
        failed=strcmp(ME.identifier,'NeuroPAL:NormalizePercentiles');
    end
    assert(failed);
end
setappdata(app.CELL_ID,'proc_normalize_background_percentile',1);
setappdata(app.CELL_ID,'proc_normalize_max_percentile',99.9);
fprintf('PROCESSING_NORMALIZATION=PASS\n');
end
