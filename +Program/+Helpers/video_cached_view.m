function [value, cache_hit] = video_cached_view(app, key, producer)
%VIDEO_CACHED_VIEW Retain one video view within a byte limit.
cache_key = 'video_projection_cache';
budget_mib = str2double(getenv('NEUROPAL_VIDEO_CACHE_MIB'));
if ~isfinite(budget_mib), budget_mib = 32; end
budget_bytes = min(max(budget_mib,0),256)*1024^2;
cache_hit = false;
if isappdata(app.CELL_ID,cache_key)
    cache = getappdata(app.CELL_ID,cache_key);
    if cache.bytes <= budget_bytes && strcmp(cache.key,key)
        value = cache.value;
        cache_hit = true;
        return
    end
    rmappdata(app.CELL_ID,cache_key);
    clear cache
end
value = producer();
entry = struct('key',key,'value',value,'bytes',0);
info = whos('entry');
if budget_bytes > 0 && info.bytes <= budget_bytes
    entry.bytes = info.bytes;
    setappdata(app.CELL_ID,cache_key,entry);
end
end
