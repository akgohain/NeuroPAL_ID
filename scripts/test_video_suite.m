function result = test_video_suite(w)
%TEST_VIDEO_SUITE Exercise the shared timeline, views and review actions.
v=w.View; p=v.Playback;
saved=struct('frame',w.Frame.Value,'channel',w.Channel.Value,'z',w.Slice.Value,'mode',v.DisplayMode.Value, ...
    'selection',v.Selection,'preferred',v.PreferredID,'rows',w.Rows,'excluded',w.Excluded,'xyz',v.XYZ.Value,'stage',v.Stage, ...
    'columns',{v.Body.ColumnWidth});
cleanup=onCleanup(@() restore(w,saved));
v.Body.ColumnWidth={700,'1x'}; pause(.2); drawnow; p.resize();
assert(p.Compact && p.Play.Layout.Column==2 && p.Play.Layout.Row==1 && p.Controls{1}==p.Previous);
v.Body.ColumnWidth=saved.columns; drawnow; p.resize();
assert(p.Play.Layout.Column==2 && p.Play.Layout.Row==1);
for i=1:5
    v.Stages{i}.ButtonPushedFcn([],[]);
    assert(v.Stage==i && strcmp(v.Panels{i}.Visible,'on'));
    assert(all(cellfun(@(panel) strcmp(panel.Visible,'off'),v.Panels(setdiff(1:5,i)))));
end
v.setStage(4); v.DisplayMode.Value='Slice'; w.render();
image=getappdata(w.Axes,'main_slice_image'); projection=getappdata(v.Projection,'main_slice_image');
trace=findobj(w.Analysis.Axes,'Tag','activity_trace'); cursor=w.Analysis.FrameCursor;
for frame=[610 611 620 615]
    p.Slider.Value=frame; p.Slider.ValueChangedFcn(p.Slider,[]); drawnow;
    assert(w.Frame.Value==frame && w.CacheFrame==frame && p.Slider.Value==frame && cursor.Value==frame);
    assert(isequal(image,getappdata(w.Axes,'main_slice_image')) && isvalid(trace));
end
for frame=630:650, p.request(frame); end
v.FramePreview.flush(); assert(w.CacheFrame==650);
p.request(651); p.Slider.Value=655; p.Slider.ValueChangedFcn(p.Slider,struct('Value',655)); pause(.1);
assert(w.CacheFrame==655 && w.Frame.Value==655 && p.Slider.Value==655);
p.First.Value=655; p.Last.Value=657; p.Loop.Value=true; p.Rate.Value=20; p.rateChanged();
p.toggle(); pause(1.5); p.stop();
assert(w.Frame.Value>=655 && w.Frame.Value<=657 && ~p.Playing);
assert(w.Analysis.FrameCursor.Value==w.Frame.Value && p.Slider.Value==w.Frame.Value);
frame=w.Frame.Value; pause(.15); assert(w.Frame.Value==frame);
p.toggle(); v.navigate(660); pause(.15); assert(~p.Playing && w.Frame.Value==660);
p.toggle(); w.safe(@() w.render()); assert(~p.Playing);
p.Loop.Value=false; v.navigate(w.Source.nt); p.Playing=true; p.tick(); assert(~p.Playing && w.Frame.Value==w.Source.nt);
v.navigate(660); p.toggle(); w.App.TabGroup.SelectedTab=w.App.NeuroPALIDTab; p.tick(); assert(~p.Playing);
w.App.TabGroup.SelectedTab=w.App.VideoTrackingTab;

raw=w.Cache; v.DisplayMode.Value='Slab'; w.render();
z=w.Slice.Value; volume=w.frameData(); expected=max(volume(:,:,max(1,z-2):min(w.Source.nz,z+2)),[],3);
assert(isequal(image.CData,v.displayPixels(expected)));
v.DisplayMode.Value='MIP'; w.render(); assert(strcmp(v.ProjectionPanel.Visible,'on') && strcmp(v.SlicePanel.Visible,'off'));
assert(isequal(projection.CData,v.displayPixels(max(w.frameData(),[],3))));
v.DisplayMode.Value='Slice'; v.XYZ.Value=true; w.render(); assert(strcmp(v.OrthogonalPanel.Visible,'on'));
assert(all(cellfun(@(ax) ~isempty(findobj(ax,'Type','image')),v.Orthogonal)));
assert(isequal(raw,w.Cache)); v.XYZ.Value=false;

row=find(w.Rows(:,1)==saved.preferred & w.Rows(:,2)==660,1); assert(~isempty(row));
v.select(w.Rows(row,:),false); original=w.Rows;
origin_key=sprintf('%d:%d',w.Rows(row,1),w.Rows(row,2)); had_origin=isKey(w.Origins,origin_key);
if had_origin, origin=w.Origins(origin_key); else, origin=''; end
v.Review.confirm(); assert(strcmp(w.Origins(origin_key),'confirmed'));
v.Review.undo(); assert(isequal(w.Rows,original));
if had_origin, assert(strcmp(w.Origins(origin_key),origin)); else, assert(~isKey(w.Origins,origin_key)); end
v.Position{1}.Value=w.Rows(row,3)+.1; v.Position{1}.ValueChangedFcn([],[]);
assert(abs(w.Rows(row,3)-original(row,3)-.1)<1e-9); assert(~w.activityCurrent());
v.Review.undo(); assert(isequal(w.Rows,original) && w.activityCurrent());
v.Exclude.Value=true; v.Exclude.ValueChangedFcn([],[]); assert(ismember(w.Rows(row,[1 2]),w.Excluded,'rows'));
v.Review.undo(); assert(isequal(w.Excluded,saved.excluded));
v.Review.Filter.Value='All quality flags'; v.redraw();
if ~isempty(v.Review.Issues)
    v.Review.List.Value=1; v.Review.choose(); assert(w.Frame.Value==v.Review.Issues(1,1));
end
v.Review.Filter.Value='Tracking cues';

% A missing observation keeps the selected identity and its trace.
v.navigate(660); key=w.Rows(:,1)==saved.preferred & w.Rows(:,2)==660; w.Rows(key,:)=[]; w.render();
assert(v.PreferredID==saved.preferred && isempty(v.Selection));
w.Rows=original; w.render();
fprintf('SUITE_GRAPHICS image_valid=%d same_image=%d cursor_valid=%d\n',isvalid(image),isequal(image,getappdata(w.Axes,'main_slice_image')),isvalid(w.Analysis.FrameCursor));
assert(isequal(image,getappdata(w.Axes,'main_slice_image')) && isvalid(w.Analysis.FrameCursor));

v.XYZ.Value=false; timings=zeros(1,20);
for i=1:20
    t=tic; v.navigate(700+i); drawnow; timings(i)=toc(t);
end
assert(w.Reader.Capacity==5 && numel(w.Reader.Frames)<=5);
result=struct('navigation_median',median(timings),'navigation_max',max(timings),'frames',20,'cache_frames',numel(w.Reader.Frames));
fprintf('VIDEO_SUITE_TIMELINE_PLAYBACK_LOOP_VIEWS_REVIEW_UNDO=PASS\n');
end
function restore(w,saved)
v=w.View; v.Playback.stop(); v.FramePreview.cancel(); v.Preview.cancel();
v.Body.ColumnWidth=saved.columns; drawnow; v.Playback.resize();
w.Rows=saved.rows; w.Excluded=saved.excluded; w.Frame.Value=saved.frame; w.Channel.Value=saved.channel; w.Slice.Value=saved.z;
v.DisplayMode.Value=saved.mode; v.Selection=saved.selection; v.PreferredID=saved.preferred;
v.XYZ.Value=saved.xyz; v.Review.Filter.Value='Tracking cues'; v.Review.clear(); v.setStage(saved.stage); w.render();
end
