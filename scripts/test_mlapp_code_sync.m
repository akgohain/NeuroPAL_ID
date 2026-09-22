function test_mlapp_code_sync()
%TEST_MLAPP_CODE_SYNC Reject stale editable methods and callbacks.
root = fileparts(fileparts(mfilename('fullpath')));
source = fullfile(root, 'visualize_light.mlapp');
sync_mlapp_code(source, true);
folder = tempname; mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
target = fullfile(folder, 'visualize_light.mlapp');
copyfile(source, target);
reader = appdesigner.internal.serialization.FileReader(target);
text = reader.readMATLABCodeText();
original = reader.readAppCodeData();
metadata = reader.readAppMetadata();
writer = appdesigner.internal.serialization.FileWriter(target);

for kind = 1:2
    code = original;
    if kind == 1
        code.EditableSectionCode = strrep(code.EditableSectionCode, ...
            'refreshAutoIDList', 'missingAutoIDList');
    else
        code.Callbacks(1).Code = {'            error(''Stale callback'');'};
    end
    writer.writeAppCodeData(text, struct('code', code), metadata);
    caught = false;
    try
        sync_mlapp_code(target, true);
    catch ME
        assert(strcmp(ME.identifier, 'NeuroPAL:AppPackage:CodeDrift'));
        caught = true;
    end
    assert(caught, 'A stale App Designer source passed the package check.');
    sync_mlapp_code(target);
    assert(strcmp(text, reader.readMATLABCodeText()), ...
        'Synchronizing editable code must preserve the runnable source.');
end
fprintf('MLAPP_CODE_SYNC_TEST=PASS\n');
end
