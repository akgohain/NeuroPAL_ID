function test_nn_streaming()
%TEST_NN_STREAMING Check patch order and output parity without loading a model.

for shape = {[256 384 3 4],[273 400 2 4]}
    input = reshape(single(mod(1:prod(shape{1}),997)),shape{1});
    expected = local_legacy_prediction(input);
    calls = zeros(0,1);
    progress = zeros(0,2);
    max_patch_bytes = 0;
    actual = Methods.NNDetect.predict_tiles(input,@predict_patch,@update_progress);
    assert(isequal(actual,expected) && isa(actual,'double'));
    expected_order = [];
    for row = 1:128:size(input,1)-127
        for column = 1:128:size(input,2)-127
            expected_order(end+1,1) = double(input(row,column,1,1));
        end
    end
    assert(isequal(calls,expected_order));
    assert(isequal(progress,[(1:numel(calls))',repmat(numel(calls),numel(calls),1)]));
    assert(max_patch_bytes == 128*128*size(input,3)*size(input,4)*4);
    output_info = whos('actual');
    assert(output_info.bytes == prod(shape{1}(1:3))*8);
end

calls = zeros(0,1);
actual = Methods.NNDetect.predict_tiles(input,@predict_patch,@(index,total) index < 3);
assert(isempty(actual) && numel(calls) == 2);
try
    Methods.NNDetect.predict_tiles(input,@fail_prediction);
    error('NeuroPAL:Test:ExpectedError','Expected a predictor failure.');
catch ME
    assert(strcmp(ME.identifier,'NeuroPAL:Test:PredictorFailure'));
end
fprintf('NN_STREAMING=PASS\n');

    function prediction = predict_patch(patch)
        calls(end+1,1) = double(patch(1,1,1,1));
        info = whos('patch');
        max_patch_bytes = max(max_patch_bytes,info.bytes);
        prediction = local_prediction(patch);
    end

    function keep_going = update_progress(index,total)
        progress(end+1,:) = [index,total];
        keep_going = true;
    end
end

function prediction = local_legacy_prediction(data)
% Preserve the previous materialized patches and prediction assembly.
patches = {};
for i = 1:floor(size(data,1)/128)
    for j = 1:floor(size(data,2)/128)
        patches{end+1} = data((i-1)*128+1:i*128,(j-1)*128+1:j*128,:,:);
    end
end
predicted = cell(size(patches));
for i = 1:numel(patches)
    predicted{i} = local_prediction(patches{i});
end
prediction = zeros(size(data,1),size(data,2),size(data,3));
columns = floor(size(data,2)/128);
for i = 1:floor(size(data,1)/128)
    for j = 1:columns
        prediction((i-1)*128+1:i*128,(j-1)*128+1:j*128,:) = predicted{(i-1)*columns+j};
    end
end
end

function prediction = local_prediction(patch)
prediction = patch(:,:,:,1)*0.125+patch(:,:,:,2)*0.25-patch(:,:,:,4)*0.5;
end

function prediction = fail_prediction(~)
prediction = [];
error('NeuroPAL:Test:PredictorFailure','Injected predictor failure.');
end
