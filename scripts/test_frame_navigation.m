function result = test_frame_navigation(w,fixtures)
%TEST_FRAME_NAVIGATION Check cached frames, stable graphics and latest-frame requests.
for name={'native','legacy','singleton'}
    folder=fullfile(fixtures,name{1}); source=jsondecode(fileread(fullfile(folder,'source.json')));
    reader=Tracking.FrameReader(source); cleanup=onCleanup(@() delete(reader));
    pixels=reader.read(source.nt); fid=fopen(fullfile(folder,'expected.bin'),'r'); expected=fread(fid,inf,'*uint16'); fclose(fid);
    assert(isequal(pixels(:),expected)); assert(isequal(reader.read(source.nt),pixels)); assert(reader.Hits==1);
    fprintf('FRAME_FIXTURE_%s_BACKEND=%s\n',name{1},reader.Backend);
    if ~strcmp(name{1},'singleton'), assert(strcmp(reader.Backend,'native')); end
    clear cleanup
end
w.Analysis.Mode.Value='ΔF/F'; w.Analysis.showActivity();
frames=[400 401 402 401 400]; times=zeros(size(frames)); reads=times;
for i=1:numel(frames)
    w.Frame.Value=frames(i); t=tic; w.frameData(); reads(i)=toc(t);
    if frames(i)==400
        fid=fopen(fullfile(fixtures,'bedant-frame400.bin'),'r'); expected=fread(fid,inf,'*uint8'); fclose(fid);
        assert(isequal(w.Cache(:),expected));
    end
    t=tic; w.render(); drawnow; times(i)=toc(t);
end
assert(w.Reader.Capacity==5 && numel(w.Reader.Frames)<=5);
trace=findobj(w.Analysis.Axes,'Tag','activity_trace'); image=getappdata(w.Axes,'main_slice_image'); cursor=w.Analysis.FrameCursor;
markers=findobj(w.View.Projection,'Tag','reference_neurons_0');
for frame=410:419, w.Frame.Value=frame; w.render(); drawnow; end
assert(numel(w.Reader.Frames)==5 && isequal(w.Reader.Frames,415:419));
assert(isvalid(trace) && isvalid(cursor) && isvalid(markers));
assert(isequal(image,getappdata(w.Axes,'main_slice_image')) && cursor.Value==419);
assert(size(w.View.ListRows,1)==39 && all(w.View.ListRows(:,2)==419));
for frame=420:450, w.View.FramePreview.request(frame); end
w.View.FramePreview.flush(); assert(w.CacheFrame==450 && w.Frame.Value==450);
w.View.FramePreview.request(451); w.Frame.Value=460; w.View.FramePreview.finish(w.Frame,[]);
pause(.1); assert(w.CacheFrame==460 && w.Frame.Value==460);
ztime=zeros(1,5); for i=1:5, w.Slice.Value=10+i; t=tic; w.render(); drawnow; ztime(i)=toc(t); end
result=struct('frames',frames,'load_seconds',reads,'render_seconds',times,'z_seconds',ztime, ...
    'backend',w.Reader.Backend,'cache_capacity',w.Reader.Capacity,'cache_hits',w.Reader.Hits);
fprintf('FRAME_NAVIGATION_PARITY_CACHE_GRAPHICS_COALESCING=PASS\n');
end
