function test_moe_wrapper_contracts(bundle)
%TEST_MOE_WRAPPER_CONTRACTS Check invalid inputs and cancellation without weights execution.
arguments
    bundle (1,1) string
end
volume = ones(8,9,5,4,'single');
local_error(@() Wrapper.runMoECentroids(volume, [0 1 1], 'BundlePath', bundle), 'Wrapper:MoEInvalidSpacing');
local_error(@() Wrapper.runMoECentroids(volume(:,:,:,1:3), [1 1 1], 'BundlePath', bundle), 'Wrapper:MoEInvalidVolume');
local_error(@() Wrapper.runMoECentroids(volume, [1 1 1], 'BundlePath', bundle, ...
    'PythonExecutable', '/definitely/missing/python'), 'Wrapper:MoEPythonUnavailable');
local_error(@() Wrapper.runMoECentroids(volume, [1 1 1], 'BundlePath', bundle, ...
    'KeepArtifacts', false, 'CancelFcn', @() true), 'Wrapper:MoECancelled');
local_error(@() Wrapper.runMoECentroids(volume, [1 1 1], 'BundlePath', bundle, ...
    'KeepArtifacts', false, 'TimeoutSeconds', 0.001), 'Wrapper:MoETimeout');
fprintf('MOE_WRAPPER_CONTRACTS=PASS\n');
end

function local_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier,identifier), 'Expected %s; got %s: %s',identifier,ME.identifier,ME.message);
    return
end
error('Expected %s',identifier);
end
