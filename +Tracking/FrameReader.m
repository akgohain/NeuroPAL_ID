classdef FrameReader < handle
    %FRAMEREADER Keep a small frame cache and reuse the H5 reader between requests.
    properties (SetAccess=private)
        Frames = []
        Pixels = {}
        Capacity
        Hits = 0
        Reads = 0
        Backend = 'native'
    end
    properties (Access=private)
        Source
        Directory = ''
        Process = []
        Sequence = 0
    end
    methods
        function obj = FrameReader(source)
            obj.Source=source;
            bytes=prod([source.ny source.nx source.nz source.nc])*numel(typecast(cast(0,source.dtype),'uint8'));
            obj.Capacity=max(1,min(5,floor(64*2^20/bytes)));
        end
        function pixels = read(obj,frame)
            s=obj.Source;
            if ~isscalar(frame) || ~isfinite(frame) || frame~=round(frame) || frame<1 || frame>s.nt
                error('Tracking:Frame','Frame index is outside recording');
            end
            index=find(obj.Frames==frame,1);
            if ~isempty(index)
                pixels=obj.Pixels{index}; obj.Hits=obj.Hits+1;
                obj.Frames(index)=[]; obj.Pixels(index)=[];
            else
                if strcmp(obj.Backend,'native')
                    try
                        if strcmp(s.axis_order,'TCZYX')
                            raw=h5read(s.file,'/data',[1 1 1 1 frame],[s.nx s.ny s.nz s.nc 1]);
                            pixels=permute(reshape(raw,[s.nx s.ny s.nz s.nc]),[2 1 3 4]);
                        else
                            raw=h5read(s.file,'/data',[1 1 1 1 frame],[s.ny s.nx s.nz s.nc 1]);
                            pixels=reshape(raw,[s.ny s.nx s.nz s.nc]);
                        end
                    catch
                        % Some recordings use filters supplied by h5py rather than MATLAB.
                        obj.Backend='python'; pixels=obj.readPython(frame);
                    end
                else
                    pixels=obj.readPython(frame);
                end
                if any(~isfinite(pixels),'all'), error('Tracking:Frame','Selected frame contains nonfinite values'); end
                obj.Reads=obj.Reads+1;
            end
            obj.Frames=[obj.Frames frame]; obj.Pixels{end+1}=pixels;
            if numel(obj.Frames)>obj.Capacity, obj.Frames(1)=[]; obj.Pixels(1)=[]; end
        end
        function pixels = readPython(obj,frame)
            if isempty(obj.Process)
                obj.Directory=tempname; mkdir(obj.Directory);
                obj.writeJSON('source.json',obj.Source);
                root=fileparts(fileparts(mfilename('fullpath')));
                command={Tracking.ReferenceWorkflow.python(),'-u',fullfile(root,'+Wrapper','reference_frame_server.py'), ...
                    '--directory',obj.Directory,'--parent',num2str(feature('getpid'))};
                args=java.util.ArrayList;
                for i=1:numel(command), args.add(java.lang.String(command{i})); end
                builder=java.lang.ProcessBuilder(args); builder.redirectErrorStream(true);
                builder.redirectOutput(java.io.File(fullfile(obj.Directory,'reader.log')));
                obj.Process=builder.start(); obj.wait('ready.json');
            end
            obj.Sequence=obj.Sequence+1;
            obj.writeJSON('request.json',struct('frame',frame-1,'sequence',obj.Sequence));
            response=obj.wait('response.json');
            if response.sequence~=obj.Sequence, error('Tracking:Frame','Frame reader response is out of sequence'); end
            fid=fopen(fullfile(obj.Directory,'frame.bin'),'r');
            if fid<0, error('Tracking:Frame','Could not read the frame buffer'); end
            cleanup=onCleanup(@() fclose(fid)); s=obj.Source;
            shape=[s.ny s.nx s.nz s.nc]; raw=fread(fid,prod(shape),['*' s.dtype]);
            if numel(raw)~=prod(shape), error('Tracking:Frame','Frame buffer is incomplete'); end
            pixels=reshape(raw,shape);
        end
        function value = wait(obj,name)
            path=fullfile(obj.Directory,name); started=tic;
            while ~isfile(path)
                if ~obj.Process.isAlive() || toc(started)>15
                    error('Tracking:FrameReader','Frame reader stopped or timed out. Reopen the recording.');
                end
                java.lang.Thread.sleep(2);
            end
            value=jsondecode(fileread(path)); delete(path);
            if isfield(value,'error'), error('Tracking:FrameReader','%s',value.error); end
        end
        function writeJSON(obj,name,value)
            path=fullfile(obj.Directory,name); temporary=[path '.tmp'];
            fid=fopen(temporary,'w'); cleanup=onCleanup(@() fclose(fid));
            fwrite(fid,jsonencode(value)); clear cleanup
            movefile(temporary,path,'f');
        end
        function delete(obj)
            if ~isempty(obj.Process) && obj.Process.isAlive()
                obj.Process.destroy();
                obj.Process.waitFor(2,java.util.concurrent.TimeUnit.SECONDS);
                if obj.Process.isAlive(), obj.Process.destroyForcibly(); end
            end
            if isfolder(obj.Directory), rmdir(obj.Directory,'s'); end
        end
    end
end
