function test_reference_identity_results()
%TEST_REFERENCE_IDENTITY_RESULTS Preserve indexing and unnamed graph failures.
predictions=table([2;0;1],["FAILED";"AVAL";"RMD"],[NaN;.8;.2], ...
    'VariableNames',{'neuron_idx','predicted_class','confidence'});
[converted,names,confidence,sources]=Tracking.referenceIdentityResults(predictions,3);
assert(isequal(converted.neuron_idx,[3;1;2]));
assert(isequal(names,["AVAL";"RMD";""]) && isequal(confidence,[.8;.2;0]));
assert(isequal(sources,["auto-id";"auto-id";"unnamed"]));
[~,restored]=Tracking.referenceIdentityResults(converted,3); assert(isequal(names,restored));
for bad={predictions(1:2,:),predictions([1 1 3],:)}
    failed=false;
    try, Tracking.referenceIdentityResults(bad{1},3); catch ME, failed=strcmp(ME.identifier,'Tracking:ReferenceIdentity'); end
    assert(failed);
end
fprintf('REFERENCE_IDENTITY_MAPPING=PASS\n');
end
