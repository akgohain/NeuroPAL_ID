classdef LargeFileHarness
    %LARGEFILEHARNESS Repeatable cancellation/resume audit for NWB streaming.

    methods (Static)
        function report = run(source_file, output_dir)
            arguments
                source_file {mustBeTextScalar}
                output_dir {mustBeTextScalar} = fullfile(pwd, '.ui_artifacts', 'large-file-audit')
            end

            source_file = char(source_file);
            output_dir = char(output_dir);
            if exist(source_file, 'file') ~= 2
                error('NeuroPAL:LargeFileHarness:MissingFixture', ...
                    'NWB fixture does not exist: %s', source_file);
            end
            if exist(output_dir, 'dir') ~= 7
                mkdir(output_dir);
            end

            final_file = fullfile(output_dir, 'stream-audit.mat');
            partial_file = DataHandling.Helpers.large_file.partial_path(final_file);
            Program.Dev.LargeFileHarness.delete_if_present(final_file);
            Program.Dev.LargeFileHarness.delete_if_present(partial_file);

            original_cancel = getenv('NEUROPAL_IO_CANCEL_AFTER_CHUNKS');
            restore_environment = onCleanup(@() setenv( ...
                'NEUROPAL_IO_CANCEL_AFTER_CHUNKS', original_cancel));

            image_info = DataHandling.Helpers.nwb.image_data_info(source_file);
            layout = DataHandling.Helpers.nwb.image_layout(image_info);
            metadata = struct('audit_source', source_file);

            setenv('NEUROPAL_IO_CANCEL_AFTER_CHUNKS', '1');
            cancelled = false;
            try
                DataHandling.Helpers.nwb.stream_image_to_mat( ...
                    source_file, image_info, final_file, metadata);
            catch exception
                if strcmp(exception.identifier, 'DataHandling:LargeFile:Cancelled')
                    cancelled = true;
                else
                    rethrow(exception);
                end
            end
            assert(cancelled, 'The intentional checkpoint cancellation did not occur.');
            assert(exist(final_file, 'file') ~= 2, ...
                'A cancelled conversion exposed a final output file.');
            assert(exist(partial_file, 'file') == 2, ...
                'A cancelled conversion did not preserve its checkpoint.');

            checkpoint = load(partial_file, 'conversion_state');
            setenv('NEUROPAL_IO_CANCEL_AFTER_CHUNKS', '');
            conversion = DataHandling.Helpers.nwb.stream_image_to_mat( ...
                source_file, image_info, final_file, metadata);
            assert(conversion.resumed, 'The second conversion did not resume its checkpoint.');
            assert(exist(partial_file, 'file') ~= 2, ...
                'The checkpoint remained after successful promotion.');

            reader = matfile(final_file);
            tested_z = unique([1, ceil(layout.output_z_count / 2), layout.output_z_count]);
            equality = false(size(tested_z));
            for index = 1:numel(tested_z)
                output_z = tested_z(index);
                source_start = ones(1, 4);
                source_count = layout.source_dims;
                source_start(layout.source_z_axis) = output_z;
                source_count(layout.source_z_axis) = 1;
                expected = h5read(source_file, image_info.data_path, ...
                    source_start, source_count);
                if ~isequal(layout.permutation, 1:4)
                    expected = permute(expected, layout.permutation);
                end
                actual = reader.data(:, :, output_z, :);
                equality(index) = isequal(expected, actual);
            end
            assert(all(equality), 'One or more streamed slices differ from the NWB source.');

            completed = load(final_file, 'conversion_state');
            report = struct( ...
                'source_file', source_file, ...
                'output_file', final_file, ...
                'source_dims', layout.source_dims, ...
                'output_dims', layout.output_dims, ...
                'cancelled_after_z', checkpoint.conversion_state.completed_z, ...
                'resumed', conversion.resumed, ...
                'chunks_written', conversion.chunks_written, ...
                'tested_z', tested_z, ...
                'slice_equality', equality, ...
                'status', completed.conversion_state.status);

            report_file = fullfile(output_dir, 'large-file-audit.json');
            file_id = fopen(report_file, 'w');
            if file_id < 0
                error('NeuroPAL:LargeFileHarness:ReportWriteFailed', ...
                    'Cannot write report: %s', report_file);
            end
            close_report = onCleanup(@() fclose(file_id));
            fwrite(file_id, jsonencode(report, PrettyPrint=true), 'char');
            clear close_report restore_environment
            fprintf('NeuroPAL large-file audit: %s\n', report_file);
        end
    end

    methods (Static, Access = private)
        function delete_if_present(path)
            if exist(path, 'file') == 2
                delete(path);
            end
        end
    end
end
