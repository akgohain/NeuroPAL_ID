function test_video_depth_playback(w)
%TEST_VIDEO_DEPTH_PLAYBACK Change depth while the movie continues playing.
v=w.View; p=v.Playback;
saved=struct('frame',w.Frame.Value,'z',w.Slice.Value,'follow',v.Follow.Value, ...
    'loop',p.Loop.Value,'rate',p.Rate.Value,'tab',w.App.TabGroup.SelectedTab);
cleanup=onCleanup(@() restore(w,saved));
w.App.TabGroup.SelectedTab=w.App.VideoTrackingTab;
p.stop(); p.Loop.Value=false; p.Rate.Value=5; p.rateChanged(); v.navigate(687);
p.toggle();
v.Follow.Value=true; v.previewRequest(8);
assert(p.Playing && w.Slice.Value==8 && ~v.Follow.Value, ...
    sprintf('Playing=%d, Z=%g, Follow=%d, Status=%s',p.Playing,w.Slice.Value,v.Follow.Value,w.Status.Text));
p.tick(); assert(p.Playing && w.Slice.Value==8 && v.SliceValue.Value==8);
v.finishSlice(w.Slice,struct('Value',17));
assert(p.Playing && w.Slice.Value==17 && v.SliceValue.Value==17);
p.tick(); assert(p.Playing && w.Slice.Value==17 && v.SliceValue.Value==17);
v.SliceValue.Value=11; v.SliceValue.ValueChangedFcn([],[]);
assert(p.Playing && w.Slice.Value==11);
frame=w.Frame.Value; pause(1.2);
assert(p.Playing && w.Frame.Value>frame && w.Slice.Value==11 && v.SliceValue.Value==11);
assert(w.CacheFrame==w.Frame.Value && p.Slider.Value==w.Frame.Value);
fprintf('VIDEO_DEPTH_DURING_PLAYBACK=PASS\n');
end
function restore(w,saved)
v=w.View; p=v.Playback; p.stop(); v.Preview.cancel();
p.Loop.Value=saved.loop; p.Rate.Value=saved.rate; p.rateChanged();
v.Follow.Value=false; w.Slice.Value=saved.z; v.navigate(saved.frame); v.Follow.Value=saved.follow;
w.App.TabGroup.SelectedTab=saved.tab;
end
