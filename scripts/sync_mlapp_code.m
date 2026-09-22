function sync_mlapp_code(filename, check_only)
%SYNC_MLAPP_CODE Keep App Designer's editable code in sync with the app.
% Run after changing matlab/document.xml in an MLAPP archive. Use check_only
% to reject a package that would lose changes when saved in App Designer.

if nargin < 1
    filename = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'visualize_light.mlapp');
end
if nargin < 2, check_only = false; end
reader = appdesigner.internal.serialization.FileReader(char(filename));
text = reader.readMATLABCodeText();
saved = reader.readAppCodeData();
code = saved;
lines = cellstr(splitlines(string(text)));
parser = appdesigner.internal.codegeneration.MTreeCodeParser();
blocks = parser.parseWithMTree(text);
assert(iscell(blocks), 'NeuroPAL:AppPackage:Parse', ...
    'Cannot parse the app source. The package has not been changed.');

% Keep the generated components and constructor separate from user code.
editable = {};
callback_names = [{code.StartupCallback.Name}, {code.Callbacks.Name}];
found = false(size(callback_names));
for k = 1:numel(blocks)
    block = blocks{k};
    if strcmp(block.Type, 'PROPERTIES')
        if block.Line == blocks{1}.Line, continue; end
    else
        names = cellfun(@(item) item.Name, block.Items, 'UniformOutput', false);
        if any(ismember(names, {'createComponents', code.ClassName}))
            continue;
        end
        matches = ismember(names, callback_names);
        if any(matches)
            assert(all(matches), 'NeuroPAL:AppPackage:Callbacks', ...
                'Unexpected method in the generated callback section.');
            for j = 1:numel(block.Items)
                item = block.Items{j};
                index = find(strcmp(callback_names, item.Name));
                assert(isscalar(index) && ~found(index), ...
                    'NeuroPAL:AppPackage:Callbacks', 'Duplicate callback.');
                % Parser positions omit the first classdef line.
                body = lines(item.Position(1)+2:item.EndPosition(1));
                if index == 1
                    code.StartupCallback.Code = body';
                else
                    code.Callbacks(index-1).Code = body';
                end
                found(index) = true;
            end
            continue;
        end
    end
    editable = [editable; {''}; lines(block.Line+1:block.EndLine+1)]; %#ok<AGROW>
end
assert(all(found), 'NeuroPAL:AppPackage:Callbacks', ...
    'A saved App Designer callback is missing from the runnable source.');
code.EditableSectionCode = [editable; {''}]';

% Ignore blank lines but preserve executable code and comments exactly.
same = same_lines(saved.EditableSectionCode, code.EditableSectionCode) && ...
    same_lines(saved.StartupCallback.Code, code.StartupCallback.Code);
for k = 1:numel(code.Callbacks)
    same = same && same_lines(saved.Callbacks(k).Code, code.Callbacks(k).Code);
end
if check_only
    assert(same, 'NeuroPAL:AppPackage:CodeDrift', ...
        ['The runnable app and App Designer source differ. Run ' ...
         'sync_mlapp_code before distributing this MLAPP file.']);
elseif ~same
    % Update both code representations together; leave the components intact.
    writer = appdesigner.internal.serialization.FileWriter(char(filename));
    writer.writeAppCodeData(text, struct('code', code), reader.readAppMetadata());
    sync_mlapp_code(filename, true);
end
fprintf('MLAPP_CODE_SYNC=PASS\n');
end

function same = same_lines(left, right)
left = strip(string(left(:)));
right = strip(string(right(:)));
same = isequal(left(strlength(left) > 0), right(strlength(right) > 0));
end
