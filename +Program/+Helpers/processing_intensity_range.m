function range = processing_intensity_range(app, mode)
% Share the source intensity scale between histograms, previews, and saved windows.
context = Program.Helpers.processing_colormap_context(app);
key = 'processing_intensity_range';
if nargin < 2, mode=app.VolumeDropDown.Value; end
if strcmp(mode, 'Video')
    key = 'processing_video_intensity_range';
    signature = app.video_info;
    if isappdata(app.CELL_ID,key)
        cached = getappdata(app.CELL_ID,key);
        if isequal(cached.signature,signature), range=cached.range; return; end
    end
    limits = [Inf -Inf];
    for t = unique(round(linspace(1,app.video_info.nt,min(3,app.video_info.nt))))
        for z = unique(round(linspace(1,app.video_info.nz,min(7,app.video_info.nz))))
            sample = Methods.ChunkyMethods.read_video_slice(app,t,z);
            limits(1)=min(limits(1),double(min(sample,[],'all')));
            limits(2)=max(limits(2),double(max(sample,[],'all')));
        end
    end
    range = Program.Helpers.native_intensity_range(cast(limits,class(sample)));
    setappdata(app.CELL_ID,key,struct('signature',signature,'range',range));
    return
end
if isstruct(app.image_info) && isfield(app.image_info,'display_range')
    range=app.image_info.display_range;
    if numel(range)==2 && all(isfinite(range)) && diff(range)>0, return; end
end
signature = {context.path, context.dims, context.source_class};
if isappdata(app.CELL_ID,key)
    cached = getappdata(app.CELL_ID,key);
    if isequal(cached.signature,signature), range=cached.range; return; end
end
if context.has_full_volume
    range = Program.Helpers.native_intensity_range(context.volume);
else
    % Sample bounded planes for a lazy source and keep that range fixed while browsing.
    limits = [Inf -Inf];
    for z = unique(round(linspace(1,context.dims(3),min(7,context.dims(3)))))
        plane = Program.Helpers.read_processing_colormap(app,'z',z);
        limits(1)=min(limits(1),double(min(plane,[],'all')));
        limits(2)=max(limits(2),double(max(plane,[],'all')));
    end
    range = Program.Helpers.native_intensity_range(cast(limits,context.source_class));
end
setappdata(app.CELL_ID,key,struct('signature',{signature},'range',range));
end
