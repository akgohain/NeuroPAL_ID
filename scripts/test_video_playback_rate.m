function test_video_playback_rate(w)
%TEST_VIDEO_PLAYBACK_RATE Accept arbitrary rates and retain playback on changes.
p=w.View.Playback; saved=p.Rate.Value;
assert(strcmp(p.Rate.Editable,'on'));
cleanup=onCleanup(@() restore(p,saved));
p.stop();
for rate=[.1 .5 7.5 30 60 120 144 240]
    p.Rate.Value=num2str(rate); p.Rate.ValueChangedFcn([],[]);
    assert(p.Rate.UserData==rate && p.Worker.Period==.01);
end
p.Rate.Value='7.5'; p.rateChanged(); p.toggle();
assert(p.Playing);
p.Rate.Value='60'; p.Rate.ValueChangedFcn([],[]);
assert(p.Playing && strcmp(p.Worker.Running,'on'));
for value={'bad','0','241','NaN','Inf'}
    p.Rate.Value=value{1}; p.rateChanged();
    assert(strcmp(p.Rate.Value,'60') && p.Playing);
end
fprintf('EDITABLE_PLAYBACK_RATE=PASS\n');
end
function restore(p,value)
p.stop(); p.Rate.Value=value; p.rateChanged();
end
