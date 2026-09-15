function test_video_contrast(w)
%TEST_VIDEO_CONTRAST Check fixed channel ranges and display-only adjustments.
v = w.View; contrast = v.Contrast;
mode = v.DisplayMode.Value; v.DisplayMode.Value='Slice';
frame = w.Frame.Value; channel = w.Channel.Value; z = w.Slice.Value;
ranges = contrast.Ranges; bounds = contrast.Bounds;
cleanup = onCleanup(@() restore(w,frame,channel,z,ranges,bounds,mode));
assert(isequal(Tracking.DisplayContrast.autoRange(zeros(3,'uint8')),[0 1]));
assert(isequal(Tracking.DisplayContrast.autoRange(single([NaN NaN])),[0 1]));
assert(isequal(Tracking.DisplayContrast.autoRange(single([-2 3 NaN])),[-2 3]));
pixels = Tracking.DisplayContrast.pixels(single([-3 -2 0 2 4]),[-2 2]);
assert(isequal(pixels(:,:,1),uint8([0 0 128 255 255])));

w.render(); raw = w.Cache; rows = w.Rows; excluded = w.Excluded;
options = w.Analysis.options(); current = w.activityCurrent();
image = getappdata(w.Axes,'main_slice_image');
projection = getappdata(v.Projection,'main_slice_image');
trace = findobj(w.Analysis.Axes,'Tag','activity_trace');
contrast.Black.Value = 0; contrast.Black.ValueChangedFcn(contrast.Black,[]);
contrast.White.Value = 100; contrast.White.ValueChangedFcn(contrast.White,[]);
plane = w.frameData(); expected = Tracking.DisplayContrast.pixels(plane(:,:,z),[0 100]);
assert(isequal(image.CData,expected));
assert(isequal(projection.CData,Tracking.DisplayContrast.pixels(max(plane,[],3),[0 100])));
assert(isequal(raw,w.Cache) && isequal(rows,w.Rows) && isequal(excluded,w.Excluded));
assert(isequal(options,w.Analysis.options()) && current==w.activityCurrent());
assert(isvalid(image) && isvalid(projection) && all(isvalid(trace)));

w.Frame.Value = min(w.Source.nt,frame+1); w.render();
assert(isequal(contrast.Ranges(channel+1,:),[0 100]));
if w.Source.nc>1
    w.Channel.Value = mod(channel+1,w.Source.nc); w.render();
    contrast.setLevel(2,200); w.Channel.Value = channel; w.render();
    assert(isequal(contrast.Ranges(channel+1,:),[0 100]));
end
contrast.setLevel(1,100); assert(contrast.Black.Value==0);
contrast.setLevel(2,NaN); assert(contrast.White.Value==100);
contrast.Preview{2}.request(800);
contrast.WhiteSlider.Value = 500; contrast.WhiteSlider.ValueChangedFcn(contrast.WhiteSlider,[]);
expected_range = contrast.Ranges; pause(.1); assert(isequaln(contrast.Ranges,expected_range));
contrast.Preview{1}.request(100); w.Frame.Value = frame; w.render();
contrast.Preview{1}.flush(); assert(isequaln(contrast.Ranges,expected_range));
contrast.Auto.ButtonPushedFcn([],[]);
assert(isequal(contrast.Ranges(channel+1,:),Tracking.DisplayContrast.autoRange(w.frameData())));
contrast.Button.ButtonPushedFcn([],[]); assert(strcmp(contrast.Panel.Visible,'on'));
contrast.Button.ButtonPushedFcn([],[]); assert(strcmp(contrast.Panel.Visible,'off'));
v.setBusy(true); assert(strcmp(contrast.Auto.Enable,'off')); v.setBusy(false);
assert(strcmp(contrast.Auto.Enable,'on'));
fprintf('VIDEO_CONTRAST_FIXED_CHANNELS_PIXELS_RAW_PARITY_CALLBACKS=PASS\n');
end
function restore(w,frame,channel,z,ranges,bounds,mode)
w.Frame.Value = frame; w.Channel.Value = channel; w.Slice.Value = z; w.View.DisplayMode.Value=mode;
w.View.Contrast.Ranges = ranges; w.View.Contrast.Bounds = bounds; w.render();
end
