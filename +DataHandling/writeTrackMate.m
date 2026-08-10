function writeTrackMate(video_info, video_neurons, output_file, figure)
%WRITETRACKMATE Export tracked points to a TrackMate XML document.

required = {'file', 'nx', 'ny', 'nz', 'nt'};
if ~isstruct(video_info) || ~all(isfield(video_info, required))
    error('NeuroPAL_ID:InvalidVideoInfo', ...
        'TrackMate export requires file, nx, ny, nz, and nt video metadata.');
end
dims = double([video_info.nx, video_info.ny, video_info.nz, video_info.nt]);
if any(~isfinite(dims)) || any(dims < 1) || any(mod(dims, 1) ~= 0)
    error('NeuroPAL_ID:InvalidVideoInfo', ...
        'TrackMate video dimensions must be positive integers.');
end
if ~isstruct(video_neurons)
    error('NeuroPAL_ID:InvalidVideoNeurons', ...
        'TrackMate annotations must be provided as a structure array.');
end
output_file = char(string(output_file));
[output_dir, ~, ~] = fileparts(output_file);
if isempty(output_dir)
    output_dir = pwd;
    output_file = fullfile(output_dir, output_file);
end
if exist(output_dir, 'dir') ~= 7
    error('NeuroPAL_ID:MissingOutputDirectory', ...
        'TrackMate output directory does not exist: %s', output_dir);
end

repo_root = fileparts(fileparts(mfilename('fullpath')));
template_file = fullfile(repo_root, 'Data', 'NeuroPAL', 'xmlTemplate.xml');
if exist(template_file, 'file') ~= 2
    error('NeuroPAL_ID:MissingTrackMateTemplate', ...
        'TrackMate XML template does not exist: %s', template_file);
end
plaintext = cellstr(splitlines(string(fileread(template_file))));
line_index = find(contains(plaintext, '<AllSpots'), 1);
if isempty(line_index)
    error('NeuroPAL_ID:InvalidTrackMateTemplate', ...
        'TrackMate XML template is missing its AllSpots element.');
end

[video_dir, video_name, video_ext] = fileparts(char(string(video_info.file)));
video_name = xml_escape([video_name, video_ext]);
video_dir = xml_escape(video_dir);
sif_start = '          <SpotsInFrame frame="%.f">';
spot_line = ['            <Spot ID="%.f" name="%s" STD_INTENSITY_CH1="0" ' ...
    'STD_INTENSITY_CH2="0" STD_INTENSITY_CH3="0" QUALITY="0" ' ...
    'TOTAL_INTENSITY_CH3="0" POSITION_T="%.f" TOTAL_INTENSITY_CH2="0" ' ...
    'TOTAL_INTENSITY_CH1="0" CONTRAST_CH1="0" FRAME="%.f" ' ...
    'MEAN_INTENSITY_CH3="0" CONTRAST_CH3="0" CONTRAST_CH2="0" ' ...
    'MEAN_INTENSITY_CH1="0" MAX_INTENSITY_CH2="0" MEAN_INTENSITY_CH2="0" ' ...
    'MAX_INTENSITY_CH3="0" MAX_INTENSITY_CH1="0" MIN_INTENSITY_CH3="0" ' ...
    'MIN_INTENSITY_CH2="0" MIN_INTENSITY_CH1="0" SNR_CH3="0" SNR_CH1="0" ' ...
    'SNR_CH2="0" MEDIAN_INTENSITY_CH1="0" VISIBILITY="1" RADIUS="6.0" ' ...
    'MEDIAN_INTENSITY_CH2="0" MEDIAN_INTENSITY_CH3="0" POSITION_X="%f" ' ...
    'POSITION_Y="%f" POSITION_Z="%.f" />'];

progress = [];
if nargin >= 4 && ~isempty(figure)
    progress = uiprogressdlg(figure, 'Title', 'Saving annotations...', ...
        'Indeterminate', 'off');
end
progress_cleanup = onCleanup(@() close_progress(progress));

frame_blocks = cell(dims(4), 1);
spot_id = 0;
for t = 1:dims(4)
    if ~isempty(progress) && isvalid(progress)
        progress.Value = t / dims(4);
    end
    spots = cell(numel(video_neurons), 1);
    spot_count = 0;
    for n = 1:numel(video_neurons)
        if ~isfield(video_neurons(n), 'rois') || numel(video_neurons(n).rois) < t
            continue
        end
        roi = video_neurons(n).rois(t);
        if ~has_position(roi)
            continue
        end
        name = worldline_name(video_neurons(n), n);
        spot_count = spot_count + 1;
        spots{spot_count} = sprintf(spot_line, spot_id, xml_escape(name), ...
            t - 1, t - 1, roi.x_slice, roi.y_slice, roi.z_slice);
        spot_id = spot_id + 1;
    end
    if spot_count > 0
        frame_blocks{t} = strjoin([{sprintf(sif_start, t - 1)}; ...
            spots(1:spot_count); {'          </SpotsInFrame>'}], newline);
    end
end
frame_blocks = frame_blocks(~cellfun('isempty', frame_blocks));

new_file = [plaintext(1:line_index); frame_blocks; plaintext(line_index+1:end)];
new_file{line_index} = sprintf('        <AllSpots nspots="%.f">', spot_id);
data_index = find(contains(new_file, '<ImageData filename="file.fmt"'), 1);
settings_index = find(contains(new_file, '<BasicSettings tend="nt-1"'), 1);
if isempty(data_index) || isempty(settings_index)
    error('NeuroPAL_ID:InvalidTrackMateTemplate', ...
        'TrackMate XML template is missing image or bounds settings.');
end
new_file{data_index} = sprintf(['        <ImageData filename="%s" folder="%s" ' ...
    'height="%.f" width="%.f" nframes="%.f" nslices="%.f" ' ...
    'pixelheight="1.0" pixelwidth="1.0" timeinterval="1.0" voxeldepth="1.0" />'], ...
    video_name, video_dir, dims(2), dims(1), dims(4), dims(3));
new_file{settings_index} = sprintf(['        <BasicSettings tend="%.f" tstart="0" ' ...
    'xend="%.f" xstart="0" yend="%.f" ystart="0" zend="%.f" zstart="0" />'], ...
    dims(4) - 1, dims(1) - 1, dims(2) - 1, dims(3) - 1);

temp_file = [tempname(output_dir), '.xml'];
file_cleanup = onCleanup(@() delete_if_present(temp_file));
writecell(new_file, temp_file, FileType='text', QuoteStrings='none');
[ok, message] = movefile(temp_file, output_file, 'f');
if ~ok
    error('NeuroPAL_ID:TrackMatePromotionFailed', ...
        'Could not publish TrackMate XML: %s', message);
end
clear file_cleanup progress_cleanup
close_progress(progress);
end

function tf = has_position(roi)
fields = {'x_slice', 'y_slice', 'z_slice'};
tf = true;
for i = 1:numel(fields)
    value = [];
    if isfield(roi, fields{i})
        value = roi.(fields{i});
    end
    tf = tf && isnumeric(value) && isscalar(value) && isfinite(value);
end
end

function name = worldline_name(video_neuron, index)
name = sprintf('Track %.f', index);
if isfield(video_neuron, 'worldline') && isstruct(video_neuron.worldline) && ...
        isfield(video_neuron.worldline, 'name') && ~isempty(video_neuron.worldline.name)
    name = char(string(video_neuron.worldline.name));
end
end

function value = xml_escape(value)
value = char(string(value));
value = strrep(value, '&', '&amp;');
value = strrep(value, '"', '&quot;');
value = strrep(value, '''', '&apos;');
value = strrep(value, '<', '&lt;');
value = strrep(value, '>', '&gt;');
end

function close_progress(progress)
if ~isempty(progress) && isvalid(progress)
    close(progress);
end
end

function delete_if_present(path)
if exist(path, 'file') == 2
    delete(path);
end
end
