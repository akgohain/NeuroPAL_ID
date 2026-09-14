function test_video_views()
%TEST_VIDEO_VIEWS Check lazy layouts, projection parity, and cache bounds.
old_path = path;
old_budget = getenv('NEUROPAL_VIDEO_CACHE_MIB');
addpath(fullfile(fileparts(mfilename('fullpath')),'fixtures'));
setenv('NEUROPAL_VIDEO_CACHE_MIB','32');
root = tempname;
try
    mkdir(root);
    app = VideoViewTestApp();
catch exception
    if exist(root,'dir') == 7, rmdir(root,'s'); end
    local_restore(old_path,old_budget);
    rethrow(exception);
end
cleanup = onCleanup(@() local_finish(app,root,old_path,old_budget));
data = reshape(uint16(1:5*7*4*2*3),5,7,4,2,3);
file = fullfile(root,'data.h5');
h5create(file,'/data',size(data),'Datatype','uint16','ChunkSize',[5 7 1 2 1]);
h5write(file,'/data',data);

grouped = fullfile(root,'grouped.h5');
times = [5 11 20];
channels = [2 6];
for t = 1:3
    for c = 1:2
        dataset = sprintf('/t%d/c%d',times(t),channels(c));
        h5create(grouped,dataset,[5 7 4],'Datatype','uint16');
        h5write(grouped,dataset,data(:,:,:,c,t));
    end
end

for source = {file,grouped}
    app.video_info = Program.Helpers.h5_video_info(source{1});
    for t = [1 3]
        for z = [1 4]
            actual = Program.Helpers.video_render_views(app,t,z,2,6,false);
            expected = local_views(data(:,:,:,:,t),z,2,6,false);
            assert(isequal(actual,expected));
            [repeated,hit] = Program.Helpers.video_render_views(app,t,z,2,6,false);
            assert(hit && isequal(repeated,expected));
        end
        actual = Program.Helpers.video_render_views(app,t,1,1,1,true);
        expected = local_views(data(:,:,:,:,t),1,1,1,true);
        assert(isequal(actual,expected));
        [~,hit] = Program.Helpers.video_render_views(app,t,4,5,7,true);
        assert(hit,'MIP cache should not depend on crosshair coordinates.');
        preview = Program.Helpers.video_render_views(app,t,3,1,1,false,true);
        assert(isequal(preview.xy,reshape(data(:,:,3,:,t),5,7,2)));
        assert(isempty(preview.xz) && isempty(preview.yz));
        [~,hit] = Program.Helpers.video_render_views(app,t,3,5,7,false,true);
        assert(hit,'XY cache should not depend on orthogonal coordinates.');
    end
end

% A different source cannot reuse a same-time projection.
app.video_info = Program.Helpers.h5_video_info(file);
Program.Helpers.video_render_views(app,1,1,1,1,false);
app.video_info = Program.Helpers.h5_video_info(grouped);
[~,hit] = Program.Helpers.video_render_views(app,1,1,1,1,false);
assert(~hit);
cached = getappdata(app.CELL_ID,'video_projection_cache');
assert(cached.bytes <= 32*1024^2);
setenv('NEUROPAL_VIDEO_CACHE_MIB','0.000001');
Program.Helpers.video_render_views(app,1,1,1,1,false);
assert(~isappdata(app.CELL_ID,'video_projection_cache'));

% Display gains keep native integer rounding and pad missing RGB channels.
app.RSlider.Value = 0.5;
app.GSlider.Value = 2;
projection = reshape(uint8([0 1 127 255 64 100 200 250]),2,2,2);
rgb = Program.Helpers.scale_video_projection(app,projection);
assert(isa(rgb,'uint8') && isequal(rgb(:,:,1),projection(:,:,1)*0.5));
assert(isequal(rgb(:,:,2),projection(:,:,2)*2) && ~any(rgb(:,:,3),'all'));
first = Program.Helpers.set_video_image(app.xyAxes,rgb,'npal_video_xy');
second = Program.Helpers.set_video_image(app.xyAxes,zeros(size(rgb),'like',rgb),'npal_video_xy');
assert(first == second && numel(findobj(app.xyAxes,'Type','image')) == 1);

app.video_info.file = fullfile(root,'fallback.nwb');
app.fallback_frame = data;
actual = Program.Helpers.video_render_views(app,2,3,4,5,false);
assert(isequal(actual,local_views(data(:,:,:,:,2),3,4,5,false)));
clear cleanup
fprintf('VIDEO_VIEWS=PASS\n');
end

function views = local_views(frame,z,x,y,mip)
if mip
    xy = max(frame,[],3);
    xz = max(frame,[],2);
    yz = max(frame,[],1);
else
    xy = frame(:,:,z,:);
    xz = frame(:,y,:,:);
    yz = frame(x,:,:,:);
end
views = struct('xy',reshape(xy,size(frame,1),size(frame,2),size(frame,4)), ...
    'xz',reshape(xz,size(frame,1),size(frame,3),size(frame,4)), ...
    'yz',reshape(yz,size(frame,2),size(frame,3),size(frame,4)));
end

function local_restore(old_path,old_budget)
path(old_path);
setenv('NEUROPAL_VIDEO_CACHE_MIB',old_budget);
end

function local_finish(app,root,old_path,old_budget)
% Delete fixture objects before removing their class definitions from path.
restore = onCleanup(@() local_restore(old_path,old_budget));
delete(app);
if exist(root,'dir') == 7, rmdir(root,'s'); end
end
