function test_display_export_source()
%TEST_DISPLAY_EXPORT_SOURCE Verify streamed export and legacy-dialog admission.
repo_root = fileparts(fileparts(mfilename('fullpath')));
original_path = path;
addpath(fullfile(repo_root, 'scripts', 'fixtures'));
try
    app = MainDisplayTestApp();
catch exception
    path(original_path);
    rethrow(exception);
end
cleanup = onCleanup(@() local_finish(app, original_path));
app.image_data = reshape(uint8(mod(0:8*9*5*6-1, 256)), 8, 9, 5, 6);
source = Program.Helpers.main_display_export_source(app);
expected = Program.Helpers.get_display_volume(app, 'main');
expected = single(expected.display_volume) / 255;
assert(isequal(source.dims, [8 9 5 3]));
for z = 1:5
    assert(isequal(source.read_slice(z), reshape(expected(:, :, z, :), 8, 9, 3)));
end
for span = {[1], [2 3 4], [1 2 3 4 5]}
    actual = Output.Illustration.readProjection(source, span{1});
    assert(isequal(actual, squeeze(max(expected(:, :, span{1}, :), [], 3))));
end
for position = {[1 1 1], [8 9 5], [4 4 3]}
    actual = Output.Illustration.readNeuronColor(source, position{1}, [1 1 1]);
    reference = Output.Illustration.readNeuronColor(expected, position{1}, [1 1 1]);
    assert(isequal(actual, reference), 'Streamed neuron colors must preserve boundary padding.');
end
legacy = Program.Helpers.main_display_legacy_volume(app);
assert(isequal(legacy, expected), 'Legacy dialogs must receive their full RGB stack.');
projection = Program.Helpers.main_display_projection(app, true);
assert(isequal(size(projection), [8 9 1 3]));

previous_budget = getenv('NEUROPAL_IO_CHUNK_MIB');
budget_cleanup = onCleanup(@() setenv('NEUROPAL_IO_CHUNK_MIB', previous_budget));
setenv('NEUROPAL_IO_CHUNK_MIB', '8');
app.image_data = zeros(32, 32, 100, 6, 'uint8');
try
    Program.Helpers.main_display_legacy_volume(app);
    error('Expected legacy materialization to be refused before rendering.');
catch exception
    assert(strcmp(exception.identifier, 'Program:Display:LegacyVolumeBudget'));
end
clear cleanup
fprintf('DISPLAY_EXPORT_SOURCE=PASS\n');
end

function local_finish(app, original_path)
% Delete fixture objects while their class definitions remain on the path.
delete(app);
path(original_path);
end
