function [views, cache_hit] = video_render_views(app, t, z, x, y, mip, xy_only)
%VIDEO_RENDER_VIEWS Read raw XY/XZ/YZ views without assembling an H5 volume.
if nargin < 7, xy_only = false; end
info = app.video_info;
t = local_index(t,info.nt);
z = local_index(z,info.nz);
x = local_index(x,info.ny);
y = local_index(y,info.nx);
request = struct('t',t,'z',z,'x',x,'y',y,'mip',logical(mip),'xy_only',logical(xy_only));
if mip
    request.z = 0;
    request.x = 0;
    request.y = 0;
elseif xy_only
    request.x = 0;
    request.y = 0;
end
key = Program.Helpers.video_request_key(info,request);
[views,cache_hit] = Program.Helpers.video_cached_view(app,key,@read_views);

    function result = read_views()
        if ~endsWith(lower(char(info.file)),'.h5')
            frame = reshape(app.retrieve_frame(t),info.ny,info.nx,info.nz,info.nc);
            if mip
                xy = max(frame,[],3);
                xz = max(frame,[],2);
                yz = max(frame,[],1);
            else
                xy = frame(:,:,z,:);
                xz = frame(:,y,:,:);
                yz = frame(x,:,:,:);
            end
            result = struct('xy',reshape(xy,info.ny,info.nx,info.nc), ...
                'xz',reshape(xz,info.ny,info.nz,info.nc), ...
                'yz',reshape(yz,info.nx,info.nz,info.nc));
            return
        end

        xy = Program.Helpers.read_h5_video_slice(info,t,z);
        result = struct('xy',xy,'xz',[],'yz',[]);
        if xy_only && ~mip, return; end
        if mip
            result.xz = zeros(info.ny,info.nz,info.nc,'like',xy);
            result.yz = zeros(info.nx,info.nz,info.nc,'like',xy);
            for zi = 1:info.nz
                if zi == z
                    slice = xy;
                else
                    slice = Program.Helpers.read_h5_video_slice(info,t,zi);
                end
                result.xy = max(result.xy,slice);
                result.xz(:,zi,:) = reshape(max(slice,[],2),info.ny,1,info.nc);
                result.yz(:,zi,:) = reshape(max(slice,[],1),info.nx,1,info.nc);
            end
        else
            [result.xz,result.yz] = local_cross_sections(info,t,x,y);
        end
    end
end

function index = local_index(value, upper)
index = min(max(round(double(value)),1),double(upper));
if ~isscalar(index) || ~isfinite(index)
    error('Program:Video:InvalidIndex','Video coordinates must be finite scalars.');
end
end

function [xz,yz] = local_cross_sections(info,t,x,y)
layout = 'data';
if isfield(info,'h5_layout'), layout = char(info.h5_layout); end
if strcmp(layout,'data')
    xz = h5read(char(info.file),'/data',[1 y 1 1 t],[info.ny 1 info.nz info.nc 1]);
    yz = h5read(char(info.file),'/data',[x 1 1 1 t],[1 info.nx info.nz info.nc 1]);
    xz = reshape(xz,info.ny,info.nz,info.nc);
    yz = reshape(yz,info.nx,info.nz,info.nc);
elseif strcmp(layout,'grouped-tc')
    for c = 1:info.nc
        dataset = sprintf('/t%d/c%d',local_source_index(info,'time_indices',t), ...
            local_source_index(info,'channel_indices',c));
        xz_channel = h5read(char(info.file),dataset,[1 y 1],[info.ny 1 info.nz]);
        yz_channel = h5read(char(info.file),dataset,[x 1 1],[1 info.nx info.nz]);
        if c == 1
            xz = zeros(info.ny,info.nz,info.nc,'like',xz_channel);
            yz = zeros(info.nx,info.nz,info.nc,'like',yz_channel);
        end
        xz(:,:,c) = reshape(xz_channel,info.ny,info.nz);
        yz(:,:,c) = reshape(yz_channel,info.nx,info.nz);
    end
else
    error('Program:Video:UnsupportedLayout','Unsupported H5 video layout: %s',layout);
end
end

function value = local_source_index(info,field,index)
if isfield(info,field), value = info.(field)(index); else, value = index-1; end
end
