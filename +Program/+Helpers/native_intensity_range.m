function range = native_intensity_range(data)
% Use one display range for all channels and slices of a source.
low = double(min(data,[],'all','omitnan'));
high = double(max(data,[],'all','omitnan'));
if isempty(low) || ~isfinite(low) || ~isfinite(high)
    range=[0 1]; return
end
if isfloat(data)
    if low>=0 && high<=1, range=[0 1]; else, range=[low high]; end
elseif isinteger(data)
    if low<0
        range=[low high];
    elseif high<=255
        range=[0 255];
    elseif high<=4095
        range=[0 4095];
    else
        range=[0 double(intmax(class(data)))];
    end
else
    range=[0 1];
end
if range(2)<=range(1), range(2)=range(1)+1; end
end
