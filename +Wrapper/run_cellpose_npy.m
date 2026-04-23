function [masksMatPath, cmdout] = run_cellpose_npy(inNpy, outDir, varargin)
%RUN_CELLPOSE_NPY  Call Python matlab_cellpose_cli.py (single) and optional display
%
%   Runs the same process as: python ... matlab_cellpose_cli.py single IN OUT ...
%   then optionally opens Wrapper.display_cellpose_masks on *_masks.mat.
%   All paths are normalized to full absolute paths before calling Python.
%
%   SYNTAX
%     run_cellpose_npy(inNpy, outDir)
%     run_cellpose_npy(inNpy, outDir, 'Prefix', 'myrun', 'ModelPath', pth, 'Python', p)
%
%   INPUTS (use full absolute paths; do not rely on CWD)
%     inNpy  — 3D/4D .npy file, e.g. '/Users/you/data/volume.npy'
%     outDir — output directory, e.g. '/Users/you/NeuroPAL_ID/+CellPose/Output'
%              (created if missing; relative inputs are taken relative to pwd, then
%              converted to a full path)
%
%   NAME-VALUE
%     'Prefix'     — file prefix (default "matlab_volume", matches CLI)
%     'ModelPath'  — full path to a Cellpose model file or folder (pretrained_model)
%                    e.g. '.../+CellPose/models/cellpose_000715' or '' to use defaults
%     'Python'     — full path to the interpreter, e.g.
%                    '/Users/you/NeuroPAL_ID/neuropal_env_new/bin/python'
%                    If omitted, uses repo venvs when present, else 'python3' on PATH
%                    (resolved to a full path when the OS reports one)
%     'NoFigures'  — true to pass --no-figures (faster, no MIP png from Python)
%     'Display'    — true (default) to run display_cellpose_masks on *_masks.mat
%     'PlotCentroids' — if true and Display is true, pass to display_cellpose_masks
%                    (centroid markers on Z-MIP panels; default false)
%
%   OUTPUTS
%     masksMatPath — full path to <prefix>_masks.mat (may not exist if run failed)
%     cmdout      — text from the Python run (for debugging)
%
%   See also: +CellPose/scripts/matlab_cellpose_cli.py, Wrapper.display_cellpose_masks

p = inputParser;
addParameter(p, 'Prefix', 'matlab_volume', @local_is_nonempty_text);
addParameter(p, 'ModelPath', '', @local_is_text);
addParameter(p, 'Python', '', @local_is_text);
addParameter(p, 'NoFigures', false, @islogical);
addParameter(p, 'Display', true, @islogical);
addParameter(p, 'PlotCentroids', false, @islogical);
parse(p, varargin{:});
prefix = char(p.Results.Prefix);

% Repo root: .../NeuroPAL_ID
here = mfilename('fullpath');
[wrapperDir, ~, ~] = fileparts(here);
root = fileparts(wrapperDir);
if exist(root, 'dir') ~= 7
    error('run_cellpose_npy:Root', 'Could not resolve NeuroPAL_ID root from %s', here);
end

scriptPath = fullfile(root, '+CellPose', 'scripts', 'matlab_cellpose_cli.py');
if exist(scriptPath, 'file') ~= 2
    error('run_cellpose_npy:NoScript', 'Not found: %s', scriptPath);
end

inNpy = local_realpath(local_abs_path(inNpy, pwd));
if exist(inNpy, 'file') ~= 2
    error('run_cellpose_npy:NoInput', 'Input .npy not found: %s', inNpy);
end

outDir = local_abs_path(outDir, pwd);
if exist(outDir, 'dir') ~= 7
    [ok, msg] = mkdir(outDir);
    if ~ok
        error('run_cellpose_npy:MkOut', 'Could not create outDir: %s\n%s', outDir, msg);
    end
end
outDir = local_realpath(outDir);

scriptPath = local_realpath(scriptPath);

py = strtrim(char(p.Results.Python));
if isempty(py)
    py = local_pick_python(root);
end
if isempty(py)
    error('run_cellpose_npy:NoPython', ...
        ['Set Name-Value ''Python'' to a full path to the interpreter, e.g. ' ...
         'fullfile(''<repo>'',''neuropal_env_new'',''bin'',''python''), ' ...
         'or create ./neuropal_env_new or ./venv at repo root.']);
end
py = local_realpath_interpreter(py);
if isempty(py)
    error('run_cellpose_npy:NoPython', ...
        'Could not resolve Python; pass ''Python'' with the full path to the executable.');
end

% Build: python "script" single "in" "out" --prefix p [--model_path m] [--no-figures]
parts = {char(py), scriptPath, 'single', inNpy, outDir, ...
    '--prefix', char(prefix)};
mp = strtrim(char(p.Results.ModelPath));
if ~isempty(mp)
    mp2 = local_realpath(local_abs_path(mp, pwd));
    if exist(mp2, 'file') ~= 2 && exist(mp2, 'dir') ~= 7
        error('run_cellpose_npy:NoModel', 'ModelPath not found (file or directory): %s', mp2);
    end
    parts{end+1} = '--model_path';
    parts{end+1} = mp2;
end
if p.Results.NoFigures
    parts{end+1} = '--no-figures';
end
cmd = local_join_quoted_command(parts);
[st, cmdout] = system(cmd);
masksCandidate = fullfile(outDir, [char(prefix) '_masks.mat']);
if exist(masksCandidate, 'file') == 2
    masksMatPath = local_realpath(masksCandidate);
else
    masksMatPath = masksCandidate;
end

if st ~= 0
    error('run_cellpose_npy:Python', ...
        'Cellpose CLI failed (exit %d). Command:\n%s\n\nOutput:\n%s', st, cmd, cmdout);
end

if p.Results.Display && exist(masksMatPath, 'file') == 2
    % Must use package name: bare display_cellpose_masks is not always resolved
    % when this file is run as part of the +Wrapper package.
    Wrapper.display_cellpose_masks(masksMatPath, 'PlotCentroids', p.Results.PlotCentroids);
elseif p.Results.Display && exist(masksMatPath, 'file') ~= 2
    warning('run_cellpose_npy:NoMat', 'Expected not found: %s\n%s', masksMatPath, cmdout);
end
end

function ok = local_is_text(s)
ok = ischar(s) || (isstring(s) && isscalar(s));
end

function ok = local_is_nonempty_text(s)
if ~(ischar(s) || (isstring(s) && isscalar(s)))
    ok = false;
    return;
end
t = strtrim(char(s));
ok = ~isempty(t);
end

function s = local_abs_path(p, cwd)
p = strtrim(char(string(p)));
if isempty(p)
    s = p;
    return
end
if p(1) == filesep || (ispc && numel(p) > 1 && p(2) == ':')
    s = p;
else
    s = fullfile(cwd, p);
end
end

function s = local_realpath(p)
% Return canonical absolute path; if not found, return p unchanged
p = strtrim(char(string(p)));
if isempty(p)
    s = p;
    return
end
[tf, a] = fileattrib(p);
if tf
    s = a.Name;
else
    s = p;
end
end

function py = local_realpath_interpreter(py)
% If full path to an existing file, normalize; else resolve on PATH
py = strtrim(char(string(py)));
if isempty(py)
    return
end
[tf, a] = fileattrib(py);
if tf
    c = a.Name;
    if exist(c, 'file') == 2
        py = c;
        return
    end
end
if ispc
    [st, w] = system([ 'where ' py ' 2>nul' ]);
else
    [st, w] = system([ 'command -v ' py ' 2>/dev/null' ]);
end
w = deblank(w);
if st ~= 0 || isempty(w)
    py = '';
    return
end
n = find(w==10 | w==13, 1);
if ~isempty(n)
    w = w(1:n-1);
end
w = strtrim(w);
[tf2, a2] = fileattrib(w);
if tf2
    py = a2.Name;
else
    py = w;
end
end

function cmd = local_join_quoted_command(parts)
% Double-quote every token for sh (paths with +, spaces, etc.)
q = @(x) ['"' strrep(x, '"', '\"') '"'];
b = cellfun(@(a) [q(char(a)) ' '], cellstr(string(parts(:))), 'uni', 0);
cmd = strtrim([b{:}]);
end

function py = local_pick_python(root)
if ispc
    cands = {
        fullfile(root, 'neuropal_env_new', 'Scripts', 'python.exe')
        fullfile(root, 'venv', 'Scripts', 'python.exe')
        };
else
    cands = {
        fullfile(root, 'neuropal_env_new', 'bin', 'python')
        fullfile(root, 'venv', 'bin', 'python3')
        fullfile(root, 'venv', 'bin', 'python')
        };
end
for i = 1:numel(cands)
    if exist(cands{i}, 'file') == 2
        py = local_realpath(cands{i});
        return
    end
end
[st, ~] = system('command -v python3 >/dev/null 2>&1');
if st == 0
    py = 'python3';
else
    [st2, ~] = system('command -v python >/dev/null 2>&1');
    if st2 == 0
        py = 'python';
    else
        py = '';
    end
end
end
