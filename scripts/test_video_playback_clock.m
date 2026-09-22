function result = test_video_playback_clock(w)
%TEST_VIDEO_PLAYBACK_CLOCK Check playback speed against elapsed time on a recording.
v=w.View; p=v.Playback; p.stop();
saved=struct('frame',w.Frame.Value,'rate',p.Rate.Value,'loop',p.Loop.Value, ...
    'first',p.First.Value,'last',p.Last.Value);
cleanup=onCleanup(@() restore(w,saved));
assert(w.Source.nt>=1500,'Use a recording with at least 1500 frames.');
result=zeros(5,3); rates=[2 30 60 144 240];
for i=1:numel(rates)
    rate=rates(i); p.Loop.Value=false; v.navigate(400);
    p.Rate.Value=num2str(rate); p.rateChanged(); p.toggle(); samples=[];
    while toc(p.Clock)<4
        pause(.05); samples(end+1,:)=[toc(p.Clock),w.Frame.Value]; %#ok<AGROW>
    end
    times=p.Times; p.stop(); fit=polyfit(samples(:,1),samples(:,2),1);
    result(i,:)=[rate,fit(1),1/mean(diff(times))];
    assert(abs(fit(1)/rate-1)<.12,'Playback did not keep pace with elapsed time.');
end
% A late tick reaches the final frame, then stops without losing it.
v.navigate(w.Source.nt-2); p.Rate.Value='240'; p.rateChanged(); p.toggle(); pause(.5);
assert(~p.Playing && w.Frame.Value==w.Source.nt && w.CacheFrame==w.Source.nt);
% Multiple wraps stay inside the selected loop, even with skipped display frames.
p.First.Value=700; p.Last.Value=708; p.Loop.Value=true; v.navigate(700); p.toggle(); pause(.8);
assert(p.Playing && w.Frame.Value>=700 && w.Frame.Value<=708);
p.stop(); frame=w.Frame.Value; p.step(1); assert(w.Frame.Value==frame+1);
disp(array2table(result,'VariableNames',{'Requested','TimelineFPS','DisplayFPS'}));
fprintf('WALL_CLOCK_PLAYBACK_RATES_END_LOOP_STEP=PASS\n');
end
function restore(w,saved)
p=w.View.Playback; p.stop(); p.First.Value=saved.first; p.Last.Value=saved.last;
p.Loop.Value=saved.loop; p.Rate.Value=saved.rate; p.rateChanged(); w.View.navigate(saved.frame);
end
