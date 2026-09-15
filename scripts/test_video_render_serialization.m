function test_video_render_serialization(w)
%TEST_VIDEO_RENDER_SERIALIZATION Keep seeks and depth updates behind an active render.
v=w.View; p=v.Playback; p.stop();
frame=w.Frame.Value; z=w.Slice.Value;
cleanup=onCleanup(@() restore(w,frame,z));
v.Rendering=true;
v.navigate(frame+1,true); assert(w.Frame.Value==frame);
v.navigate(frame+2); assert(w.Frame.Value==frame);
v.previewRequest(7); v.render(); assert(v.PendingRender);
v.finishRender(); v.FramePreview.flush(); v.Preview.flush();
assert(w.Frame.Value==frame+2 && w.CacheFrame==frame+2 && w.Slice.Value==7);
assert(~v.Rendering && ~v.PendingRender);
test_video_depth_playback(w);
p.Rate.Value=20; p.rateChanged(); p.Loop.Value=false; p.toggle();
for i=1:25
    v.previewRequest(mod(i,w.Source.nz)+1); pause(.04);
end
p.stop(); v.finishSlice(w.Slice,struct('Value',13));
assert(w.Frame.Value>frame+2 && w.CacheFrame==w.Frame.Value && v.SliceValue.Value==13);
assert(~v.Rendering && ~v.PendingRender);
fprintf('VIDEO_RENDER_SERIALIZATION_AND_20FPS_DEPTH_STRESS=PASS\n');
end
function restore(w,frame,z)
v=w.View; v.Playback.stop(); v.Rendering=false; v.PendingRender=false;
v.FramePreview.cancel(); v.Preview.cancel(); w.Slice.Value=z; v.navigate(frame);
end
