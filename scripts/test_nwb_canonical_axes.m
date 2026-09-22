function test_nwb_canonical_axes(folder)
% Check schema XYZC/TXYZC storage without allocating a transposed volume.
if nargin<1, folder=tempname; end
if ~isfolder(folder), mkdir(folder); end
data=reshape(uint16(1:4*7*3*5),[4 7 3 5]);
source=DataHandling.Helpers.nwb_stream_export.image_source(data);
source.metadata=struct('axes','XYZC');
file=fullfile(folder,'image.nwb');
write_fixture(source,file);
actual=h5read(file,source.path);
assert(isequal(size(actual),[5 3 4 7]));
assert(isequal(actual,permute(data,[4 3 1 2])));
info=struct('dims',size(actual),'data_path',source.path,'axes','XYZC');
DataHandling.Helpers.nwb.stream_image_to_mat(file,info,fullfile(folder,'image.mat'),struct());
loaded=load(fullfile(folder,'image.mat'),'data');
assert(isequal(loaded.data,data));
movie=reshape(uint16(1:4*7*3*5*2),[4 7 3 5 2]);
source.dims=size(movie); source.permutation=[4 3 1 2 5];
source.read_plane=@(t,z,c)movie(:,:,z,c,t); source.metadata.axes='TXYZC';
file=fullfile(folder,'movie.nwb'); write_fixture(source,file);
assert(isequal(h5read(file,source.path),permute(movie,[4 3 1 2 5])));
fprintf('NWB_CANONICAL_XYZC_TXYZC_STORAGE=PASS\n');
end

function write_fixture(source,file)
nwb=NwbFile('session_description','Synthetic axis fixture', ...
    'identifier','axes','session_start_time',datetime(2026,9,21,'TimeZone','UTC'));
pipe=DataHandling.Helpers.nwb_stream_export.make_pipe(source);
nwb.acquisition.set('NeuroPALImageRaw',types.core.TimeSeries( ...
    'data',pipe,'data_unit','a.u.','starting_time',0,'starting_time_rate',1));
DataHandling.Helpers.nwb_stream_export.write(nwb,file,{source});
end
