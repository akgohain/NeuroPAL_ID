function handle = set_video_image(ax, data, tag)
%SET_VIDEO_IMAGE Reuse the image object while preserving other axes objects.
handle = findobj(ax,'Type','image','Tag',tag);
if isempty(handle)
    existing = findobj(ax,'Type','image');
    if isempty(existing)
        handle = image(ax,data,'Tag',tag);
    else
        handle = existing(1);
        handle.Tag = tag;
        handle.CData = data;
        if numel(existing) > 1, delete(existing(2:end)); end
    end
else
    handle = handle(1);
    handle.CData = data;
end
handle.XData = [1 size(data,2)];
handle.YData = [1 size(data,1)];
end
