function [predictions,names,confidence,sources] = referenceIdentityResults(predictions,count)
%REFERENCEIDENTITYRESULTS Match Python predictions to the detected reference rows.
required={'neuron_idx','predicted_class','confidence'};
if ~istable(predictions) || ~all(ismember(required,predictions.Properties.VariableNames))
    error('Tracking:ReferenceIdentity','Auto ID returned an invalid prediction table.');
end
indices=double(predictions.neuron_idx(:));
if height(predictions)~=count
    error('Tracking:ReferenceIdentity','Auto ID changed the input neuron count. No names were applied.');
end
% The array inference API returns zero-based input indices, including failures.
if isequal(sort(indices),(0:count-1)'), indices=indices+1; end
if ~isequal(sort(indices),(1:count)')
    error('Tracking:ReferenceIdentity','Auto ID did not preserve the input neuron indices.');
end
failed=string(predictions.predicted_class)=="FAILED";
predictions.neuron_idx=indices; predictions.confidence(failed)=0;
predictions=Methods.MethodContract.identity(predictions);
names=strings(count,1); confidence=zeros(count,1); sources=repmat("unnamed",count,1);
names(indices(~failed))=string(predictions.predicted_class(~failed));
confidence(indices(~failed))=double(predictions.confidence(~failed)); sources(indices(~failed))="auto-id";
end
