function test_trackmate_export()
%TEST_TRACKMATE_EXPORT Validate safe, portable TrackMate XML export.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() local_cleanup(root));
output = fullfile(root, 'tracks.xml');
video_info = struct('file', fullfile(root, 'video & "sample".h5'), ...
    'nx', 12, 'ny', 10, 'nz', 4, 'nt', 3);
roi = struct('x_slice', [], 'y_slice', [], 'z_slice', []);
rois = repmat(roi, 1, video_info.nt);
rois(1) = struct('x_slice', 7, 'y_slice', 4, 'z_slice', 2);
rois(3) = struct('x_slice', 9, 'y_slice', 6, 'z_slice', 3);
neurons = struct('worldline', struct('name', 'AVA & "test"'), 'rois', rois);

original_dir = pwd;
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
cd(root);
directory_cleanup = onCleanup(@() cd(original_dir));
feval('DataHandling.writeTrackMate', video_info, neurons, output, []);
xml = fileread(output);
assert(contains(xml, '<AllSpots nspots="2">'));
assert(contains(xml, 'name="AVA &amp; &quot;test&quot;"'));
assert(contains(xml, 'filename="video &amp; &quot;sample&quot;.h5"'));
assert(contains(xml, '<SpotsInFrame frame="0">'));
assert(~contains(xml, '<SpotsInFrame frame="1">'));
assert(contains(xml, '<SpotsInFrame frame="2">'));

fid = fopen(output, 'w');
assert(fid >= 0);
fwrite(fid, 'sentinel', 'char');
fclose(fid);
invalid_info = rmfield(video_info, 'nt');
local_assert_error(@() feval('DataHandling.writeTrackMate', ...
    invalid_info, neurons, output, []), 'NeuroPAL_ID:InvalidVideoInfo');
assert(strcmp(fileread(output), 'sentinel'));

clear directory_cleanup
cd(original_dir);
clear cleanup
local_cleanup(root);
fprintf('TRACKMATE_EXPORT=PASS\n');
end

function local_assert_error(callback, identifier)
try
    callback();
catch ME
    assert(strcmp(ME.identifier, identifier), ...
        'Expected %s, received %s.', identifier, ME.identifier);
    return
end
error('NeuroPAL:Test:ExpectedError', 'Expected %s.', identifier);
end

function local_cleanup(root)
if exist(root, 'dir') == 7
    rmdir(root, 's');
end
end
