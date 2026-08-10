classdef large_file
    %LARGE_FILE Shared policy for bounded-memory, transactional conversions.

    methods (Static)
        function bytes = memory_budget_bytes()
            default_mib = 128;
            configured = str2double(getenv('NEUROPAL_IO_CHUNK_MIB'));
            if ~isfinite(configured) || configured <= 0
                configured = default_mib;
            end
            configured = min(max(configured, 8), 1024);
            bytes = floor(configured * 1024^2);
        end

        function bytes = bytes_per_element(class_name)
            class_name = char(string(class_name));
            token = regexp(class_name, '^(?:u?int)(\d+)$', 'tokens', 'once');
            if ~isempty(token)
                bytes = str2double(token{1}) / 8;
                return
            end
            switch class_name
                case 'logical'
                    bytes = 1;
                case 'single'
                    bytes = 4;
                case 'double'
                    bytes = 8;
                otherwise
                    error('DataHandling:LargeFile:UnsupportedClass', ...
                        'Unsupported large-file data class: %s', class_name);
            end
        end

        function signature = source_signature(path)
            if exist(path, 'file') ~= 2
                error('DataHandling:LargeFile:MissingSource', ...
                    'Large-file source does not exist: %s', char(string(path)));
            end
            file = javaObject('java.io.File', char(path));
            signature = struct( ...
                'canonical_path', char(file.getCanonicalPath()), ...
                'bytes', double(file.length()), ...
                'modified_millis', double(file.lastModified()));
        end

        function path = partial_path(final_path)
            [folder, name, extension] = fileparts(final_path);
            path = fullfile(folder, sprintf('.%s.npal-partial%s', name, extension));
        end

        function assert_sufficient_disk_space(output_file, raw_bytes, existing_bytes)
            if nargin < 3
                existing_bytes = 0;
            end
            output_dir = fileparts(output_file);
            if isempty(output_dir)
                output_dir = pwd;
            end
            if exist(output_dir, 'dir') ~= 7
                error('DataHandling:LargeFile:MissingOutputDirectory', ...
                    'Large-file output directory does not exist: %s', output_dir);
            end
            file = javaObject('java.io.File', output_dir);
            usable_bytes = double(file.getUsableSpace());
            test_usable_bytes = str2double(getenv('NEUROPAL_IO_TEST_AVAILABLE_BYTES'));
            if isfinite(test_usable_bytes) && test_usable_bytes >= 0
                usable_bytes = test_usable_bytes;
            end
            remaining_raw = max(0, double(raw_bytes) - double(existing_bytes));
            required_bytes = remaining_raw * 1.15 + 256 * 1024^2;
            if usable_bytes < required_bytes
                deficit_bytes = required_bytes - usable_bytes;
                error('DataHandling:LargeFile:InsufficientDiskSpace', ...
                    ['Not enough free disk space for a transactional conversion. ' ...
                     'Need approximately %s additional space; %s is available in %s.'], ...
                    DataHandling.Helpers.large_file.format_bytes(deficit_bytes), ...
                    DataHandling.Helpers.large_file.format_bytes(usable_bytes), ...
                    output_dir);
            end
        end

        function tf = cancel_requested()
            handle = Program.Handlers.dialogue.active();
            try
                tf = ~isempty(handle) && isvalid(handle) && ...
                    isprop(handle, 'CancelRequested') && logical(handle.CancelRequested);
            catch
                tf = false;
            end
        end

        function promote(partial_path, final_path)
            if exist(final_path, 'file') == 2
                error('DataHandling:LargeFile:FinalExists', ...
                    'Refusing to overwrite an existing completed file: %s', final_path);
            end
            [ok, message] = movefile(partial_path, final_path);
            if ~ok
                error('DataHandling:LargeFile:PromotionFailed', ...
                    'Could not promote partial conversion to %s: %s', final_path, message);
            end
        end

        function text = format_bytes(bytes)
            units = {'B', 'KiB', 'MiB', 'GiB', 'TiB'};
            value = double(bytes);
            unit_index = 1;
            while value >= 1024 && unit_index < numel(units)
                value = value / 1024;
                unit_index = unit_index + 1;
            end
            text = sprintf('%.1f %s', value, units{unit_index});
        end
    end
end
