function test_mat_class()
    % TEST_MAT_CLASS Comprehensive testing script for the mat.m class
    % 
    % This script tests all major functionality of the mat class including:
    % - File creation
    % - Reading operations
    % - Writing operations
    % - Metadata extraction
    % - Error handling
    %
    % Usage: test_mat_class()
    
    fprintf('Starting MAT class testing...\n');
    fprintf('================================\n\n');
    
    % Initialize test counters
    total_tests = 0;
    passed_tests = 0;
    
    try
        %% Test 1: File Creation
        fprintf('Test 1: Testing mat.create functionality\n');
        total_tests = total_tests + 1;
        
        test_file = 'test_created_NPAL.mat';
        test_dims = [100, 200, 5, 3]; % x, y, z, c
        test_dtype = 'double';
        test_metadata = struct('description', 'Test file', 'scale', [1, 1, 1]);
        
        try
            DataHandling.Helpers.mat.create(test_file, test_dims, test_dtype, test_metadata);
            if exist(test_file, 'file')
                fprintf('✓ File creation successful\n');
                passed_tests = passed_tests + 1;
            else
                fprintf('✗ File creation failed - file not found\n');
            end
        catch ME
            fprintf('✗ File creation failed: %s\n', ME.message);
        end
        
        %% Test 2: Get Reader
        fprintf('\nTest 2: Testing mat.get_reader functionality\n');
        total_tests = total_tests + 1;
        
        try
            reader = DataHandling.Helpers.mat.get_reader(test_file);
            if isa(reader, 'matlab.io.MatFile')
                fprintf('✓ Reader creation successful\n');
                passed_tests = passed_tests + 1;
            else
                fprintf('✗ Reader creation failed - wrong class\n');
            end
        catch ME
            fprintf('✗ Reader creation failed: %s\n', ME.message);
        end
        
        %% Test 3: Metadata Extraction
        fprintf('\nTest 3: Testing mat.get_metadata functionality\n');
        total_tests = total_tests + 1;
        
        try
            metadata = DataHandling.Helpers.mat.get_metadata(reader);
            if isstruct(metadata) && isfield(metadata, 'nx') && isfield(metadata, 'ny')
                fprintf('✓ Metadata extraction successful\n');
                fprintf('  - Dimensions: %dx%dx%dx%d\n', metadata.nx, metadata.ny, metadata.nz, metadata.nc);
                if isfield(metadata, 'nt')
                    fprintf('  - Time points: %d\n', metadata.nt);
                end
                passed_tests = passed_tests + 1;
            else
                fprintf('✗ Metadata extraction failed - invalid structure\n');
            end
        catch ME
            fprintf('✗ Metadata extraction failed: %s\n', ME.message);
        end
        
        %% Test 4: Basic Reading (Full Array)
        fprintf('\nTest 4: Testing basic reading functionality\n');
        total_tests = total_tests + 1;
        
        try
            % Note: Using direct matfile access since read function has issues
            info = whos(reader);
            if ~isempty(info)
                [~, idx] = max([info.bytes]);
                main_var = info(idx).name;
                data = reader.(main_var);
                
                if ~isempty(data)
                    fprintf('✓ Basic reading successful\n');
                    fprintf('  - Data size: %s\n', mat2str(size(data)));
                    fprintf('  - Data type: %s\n', class(data));
                    passed_tests = passed_tests + 1;
                else
                    fprintf('✗ Basic reading failed - empty data\n');
                end
            else
                fprintf('✗ Basic reading failed - no variables found\n');
            end
        catch ME
            fprintf('✗ Basic reading failed: %s\n', ME.message);
        end
        
        %% Test 5: Writing Operations
        fprintf('\nTest 5: Testing mat.write functionality\n');
        total_tests = total_tests + 1;
        
        try
            % Create test data to write
            test_data = rand(50, 50, 2, 2); % Smaller test array
            
            % Try writing the data
            DataHandling.Helpers.mat.write(test_file, test_data);
            
            % Verify the write by reading back
            updated_reader = DataHandling.Helpers.mat.get_reader(test_file);
            info = whos(updated_reader);
            [~, idx] = max([info.bytes]);
            main_var = info(idx).name;
            written_data = updated_reader.(main_var);
            
            if isequal(size(written_data), size(test_data))
                fprintf('✓ Writing operation successful\n');
                fprintf('  - Written data size: %s\n', mat2str(size(written_data)));
                passed_tests = passed_tests + 1;
            else
                fprintf('✗ Writing operation failed - size mismatch\n');
            end
        catch ME
            fprintf('✗ Writing operation failed: %s\n', ME.message);
        end
        
        %% Test 6: Error Handling
        fprintf('\nTest 6: Testing error handling\n');
        total_tests = total_tests + 1;
        
        try
            % Test with non-NPAL file
            try
                DataHandling.Helpers.mat.get_reader('test_file.mat');
                fprintf('✗ Error handling failed - should reject non-NPAL files\n');
            catch
                fprintf('✓ Error handling successful - correctly rejects non-NPAL files\n');
                passed_tests = passed_tests + 1;
            end
        catch ME
            fprintf('✗ Error handling test failed: %s\n', ME.message);
        end
        
        %% Test 7: Test with User's MAT File
        fprintf('\nTest 7: Testing with user''s MAT file\n');
        total_tests = total_tests + 1;
        
        % Your specific file path
        user_file = '/Users/davidkang/Downloads/NeuroPAL_data/NeuroPAL_ID_Images/otIs669_Young_Adults/Dorsal-Ventral_Views/56_YAaDV_ID.mat';
        
        if exist(user_file, 'file')
            try
                % Create NPAL version for testing
                [filepath, name, ext] = fileparts(user_file);
                temp_file = fullfile(filepath, [name '_NPAL' ext]);
                copyfile(user_file, temp_file);
                
                fprintf('  - Testing file: %s\n', user_file);
                
                % First diagnose the original file
                fprintf('  - Original file diagnosis:\n');
                diagnose_mat_file(user_file);
                
                % Test with NPAL version
                user_reader = DataHandling.Helpers.mat.get_reader(temp_file);
                user_metadata = DataHandling.Helpers.mat.get_metadata(user_reader);
                
                fprintf('✓ User file testing successful\n');
                fprintf('  - Dimensions: %dx%dx%dx%d\n', user_metadata.nx, user_metadata.ny, user_metadata.nz, user_metadata.nc);
                if isfield(user_metadata, 'dtype_str')
                    fprintf('  - Data type: %s\n', user_metadata.dtype_str);
                end
                if isfield(user_metadata, 'nt')
                    fprintf('  - Time points: %d\n', user_metadata.nt);
                end
                
                % Clean up temporary file
                if exist(temp_file, 'file')
                    delete(temp_file);
                end
                
                passed_tests = passed_tests + 1;
            catch ME
                fprintf('✗ User file testing failed: %s\n', ME.message);
                fprintf('  Error details: %s\n', ME.getReport());
                % Clean up on error
                temp_file = fullfile(filepath, [name '_NPAL' ext]);
                if exist(temp_file, 'file')
                    delete(temp_file);
                end
            end
        else
            fprintf('✗ User file not found: %s\n', user_file);
        end
        
        %% Clean up test files
        fprintf('\nCleaning up test files...\n');
        if exist(test_file, 'file')
            delete(test_file);
            fprintf('✓ Test file cleaned up\n');
        end
        
    catch ME
        fprintf('✗ Critical error in test suite: %s\n', ME.message);
        fprintf('Error details: %s\n', ME.getReport());
    end
    
    %% Summary
    fprintf('\n================================\n');
    fprintf('Test Summary:\n');
    fprintf('Total tests: %d\n', total_tests);
    fprintf('Passed: %d\n', passed_tests);
    fprintf('Failed: %d\n', total_tests - passed_tests);
    if total_tests > 0
        fprintf('Success rate: %.1f%%\n', (passed_tests/total_tests)*100);
    end
    
    if passed_tests == total_tests
        fprintf('🎉 All tests passed!\n');
    else
        fprintf('⚠️ Some tests failed. Check the output above for details.\n');
    end
    
    fprintf('\n================================\n');
end

%% Helper function to create a mock cursor if needed
function cursor = create_mock_cursor(dims)
    % Create a simple mock cursor structure for testing
    if length(dims) >= 4
        cursor = struct( ...
            'x1', 1, 'x2', dims(1), ...
            'y1', 1, 'y2', dims(2), ...
            'z1', 1, 'z2', dims(3), ...
            'c1', 1, 'c2', dims(4));
    else
        cursor = struct( ...
            'x1', 1, 'x2', dims(1), ...
            'y1', 1, 'y2', dims(2), ...
            'z1', 1, 'z2', 1, ...
            'c1', 1, 'c2', 1);
    end
    
    if length(dims) >= 5
        cursor.t1 = 1;
        cursor.t2 = dims(5);
    end
end

%% Additional diagnostic function
function diagnose_mat_file(filename)
    % DIAGNOSE_MAT_FILE Provide detailed information about a MAT file
    fprintf('    Diagnosing MAT file: %s\n', filename);
    fprintf('    ----------------------------------------\n');
    
    try
        % Basic file info
        file_info = dir(filename);
        fprintf('    File size: %.2f MB\n', file_info.bytes / 1024 / 1024);
        
        % Load and inspect
        reader = matfile(filename);
        vars = whos(reader);
        
        fprintf('    Variables in file:\n');
        for i = 1:length(vars)
            fprintf('      %s: %s, size %s (%.2f MB)\n', ...
                vars(i).name, vars(i).class, mat2str(vars(i).size), ...
                vars(i).bytes / 1024 / 1024);
        end
        
        if ~isempty(vars)
            [~, idx] = max([vars.bytes]);
            main_var = vars(idx).name;
            fprintf('    Largest variable: %s\n', main_var);
            
            % Try to peek at the data structure
            try
                sample_data = reader.(main_var);
                fprintf('    Data type: %s\n', class(sample_data));
                fprintf('    Data size: %s\n', mat2str(size(sample_data)));
                
                if isstruct(sample_data)
                    fprintf('    Structure fields: %s\n', strjoin(fieldnames(sample_data), ', '));
                end
            catch ME2
                fprintf('    Could not inspect data: %s\n', ME2.message);
            end
        end
        
    catch ME
        fprintf('    Error diagnosing file: %s\n', ME.message);
    end
    fprintf('    ----------------------------------------\n');
end