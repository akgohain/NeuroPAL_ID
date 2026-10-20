classdef OpenSource
    %OPENSOURCE Distinguish NeuroPAL images from calcium recordings.
    methods (Static)
        function sources = inspect(path)
            [~,~,ext] = fileparts(path);
            sources = struct('image',true,'recording',false);
            if strcmpi(ext,'.nwb')
                sources.image = false;
                try
                    file = H5F.open(path,'H5F_ACC_RDONLY','H5P_DEFAULT');
                    file_cleanup = onCleanup(@() H5F.close(file));
                    acquisition = H5G.open(file,'/acquisition');
                    group_cleanup = onCleanup(@() H5G.close(acquisition));
                    info = H5G.get_info(acquisition);
                    % Read acquisition metadata without walking image chunks.
                    for i = 0:double(info.nlinks)-1
                        name = H5L.get_name_by_idx(acquisition,'.', ...
                            'H5_INDEX_NAME','H5_ITER_INC',i,'H5P_DEFAULT');
                        group_path = ['/acquisition/' name];
                        try
                            type = string(h5readatt(path,group_path,'neurodata_type'));
                            rank = DataHandling.OpenSource.dataset_rank(file,[group_path '/data']);
                            if type == "MultiChannelVolume" && rank == 4
                                sources.image = true;
                            elseif type == "MultiChannelVolumeSeries" && any(rank == [4 5])
                                sources.recording = true;
                            end
                        catch
                            % Unrelated acquisition objects need no image data.
                        end
                    end
                catch
                    % Leave unreadable files to the image loader's diagnostics.
                end
            elseif any(strcmpi(ext,{'.h5','.hdf5'}))
                try
                    file = H5F.open(path,'H5F_ACC_RDONLY','H5P_DEFAULT');
                    file_cleanup = onCleanup(@() H5F.close(file));
                    sources.recording = DataHandling.OpenSource.dataset_rank(file,'/data') == 5;
                    sources.image = ~sources.recording;
                catch
                end
            end
        end

        function route = resolve(path, requested, choose)
            % Explicit routes allow callers to open either part of a paired NWB.
            if nargin < 2 || isempty(requested), requested = 'auto'; end
            requested = lower(string(requested));
            if ~isscalar(requested) || ~any(requested == ["auto" "image" "recording"])
                error('DataHandling:OpenSource:Route','Choose auto, image, or recording when opening a source.');
            end
            sources = DataHandling.OpenSource.inspect(path);
            if requested == "image"
                if ~sources.image && sources.recording
                    error('DataHandling:OpenSource:NoImage','This file contains a calcium recording without a NeuroPAL image volume.');
                end
                route = 'image';
            elseif requested == "recording"
                if ~sources.recording
                    error('DataHandling:OpenSource:NoRecording','This file does not contain a supported calcium recording.');
                end
                route = 'recording';
            elseif sources.image && sources.recording
                if nargin < 3 || isempty(choose)
                    error('DataHandling:OpenSource:ChoiceRequired', ...
                        'This NWB contains a NeuroPAL volume and a calcium recording. Choose image or recording.');
                end
                answer = string(choose());
                if answer == "NeuroPAL volume"
                    route = 'image';
                elseif answer == "Calcium recording"
                    route = 'recording';
                elseif answer == "Cancel"
                    route = 'cancel';
                else
                    error('DataHandling:OpenSource:Choice','The source selection was not recognized.');
                end
            elseif sources.recording
                route = 'recording';
            else
                route = 'image';
            end
        end
    end
    methods (Static, Access = private)
        function rank = dataset_rank(file, path)
            dataset = H5D.open(file,path);
            dataset_cleanup = onCleanup(@() H5D.close(dataset));
            space = H5D.get_space(dataset);
            space_cleanup = onCleanup(@() H5S.close(space));
            rank = H5S.get_simple_extent_ndims(space);
        end
    end
end
