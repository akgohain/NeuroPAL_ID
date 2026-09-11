function key = video_request_key(info, request)
%VIDEO_REQUEST_KEY Identify the source and coordinates of a cached video view.
file = char(info.file);
signature = struct('file',file,'bytes',NaN,'modified',NaN, ...
    'shape',[info.ny info.nx info.nz info.nc info.nt]);
entry = dir(file);
if ~isempty(entry)
    signature.bytes = entry(1).bytes;
    signature.modified = entry(1).datenum;
end
fields = {'h5_layout','time_indices','channel_indices'};
for i = 1:numel(fields)
    if isfield(info,fields{i}), signature.(fields{i}) = info.(fields{i}); end
end
key = jsonencode(struct('source',signature,'request',request));
end
