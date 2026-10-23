classdef NWBIdentityExchange
    %NWBIDENTITYEXCHANGE Preserve structured identities beside the NWB summary.
    methods (Static)
        function attach(module, table, image)
            store = image.annotation_store;
            if isempty(fieldnames(store)), return; end
            projection = Annotations.Store.project(store, image.neurons);
            owners = {projection.annotation_id}';
            if numel(unique(owners)) ~= numel(image.neurons) || any(cellfun(@isempty, owners))
                error('DataHandling:NWBIdentityOwners', 'Neuron annotation owners must be unique before export.');
            end
            file = [tempname '.mat'];
            cleanup = onCleanup(@() DataHandling.Helpers.NWBIdentityExchange.remove(file));
            Annotations.Exchange.export(file, store, image.neurons);
            info = dir(file);
            DataHandling.Helpers.NWBIdentityExchange.checkSize(info.bytes);
            fid = fopen(file, 'rb');
            if fid < 0, error('DataHandling:NWBIdentityRead', 'Cannot read the structured identity export.'); end
            stream = onCleanup(@() fclose(fid));
            bytes = fread(fid, Inf, '*uint8');
            clear stream;
            column = types.untyped.DataPipe('data', bytes, ...
                'maxSize', [numel(bytes) 1], 'axis', 2);
            exchange = types.hdmf_common.DynamicTable( ...
                'description', 'Full NeuroPAL.IdentityExchange/1 MAT payload with verified content integrity', ...
                'colnames', {'identity_exchange_mat'}, ...
                'id', types.hdmf_common.ElementIdentifiers('data', int64(0)), ...
                'identity_exchange_mat', types.hdmf_common.VectorData( ...
                    'description', 'MAT v7.3 bytes; retains tentative IDs, ambiguity, ownership, history and evidence', ...
                    'data', column));
            table.vectordata.set('annotation_owner_id', types.hdmf_common.VectorData( ...
                'description', 'Stable annotation owner for each neuron row', 'data', owners));
            table.colnames = [table.colnames(:)' {'annotation_owner_id'}];
            module.dynamictable.set('FullIdentityExchange', exchange);
        end

        function restore(file, image)
            base = '/processing/NeuronAnnotations/';
            try
                h5info(file, [base 'FullIdentityExchange']);
            catch
                return;
            end
            path = [base 'FullIdentityExchange/identity_exchange_mat'];
            info = h5info(file, path);
            DataHandling.Helpers.NWBIdentityExchange.checkSize(prod(info.Dataspace.Size));
            bytes = h5read(file, path);
            if ~isa(bytes, 'uint8') || ~isvector(bytes)
                error('DataHandling:NWBIdentityFormat', 'The embedded identity exchange must contain MAT bytes.');
            end
            temporary = [tempname '.mat'];
            cleanup = onCleanup(@() DataHandling.Helpers.NWBIdentityExchange.remove(temporary));
            fid = fopen(temporary, 'wb');
            if fid < 0, error('DataHandling:NWBIdentityWrite', 'Cannot unpack the structured identity exchange.'); end
            stream = onCleanup(@() fclose(fid));
            written = fwrite(fid, bytes, 'uint8');
            clear stream;
            if written ~= numel(bytes)
                error('DataHandling:NWBIdentityWrite', 'The structured identity exchange could not be unpacked completely.');
            end
            [store, report] = Annotations.Exchange.read(temporary);
            if ~report.catalog_compatible
                error('DataHandling:NWBIdentityCatalog', 'This NWB uses an incompatible identity catalog. Update NeuroPAL ID before opening it.');
            end
            loaded = load(temporary, 'identity_exchange');
            projection = loaded.identity_exchange.payload.legacy_projection;
            owners = cellstr(string(h5read(file, [base 'NeuronAnnotations/annotation_owner_id'])));
            if numel(owners) ~= numel(image.neurons) || numel(unique(owners)) ~= numel(owners) || ...
                    ~isequal(owners(:), {projection.annotation_id}') || ...
                    ~all(ismember(owners, {store.owners.owner_id}))
                error('DataHandling:NWBIdentityOwners', 'The NWB neuron rows do not match their structured identity owners.');
            end
            for index = 1:numel(owners)
                image.neurons(index).annotation_id = owners{index};
            end
            Program.GUI.ManualIDService.apply(image, store);
        end
    end

    methods (Static, Access = private)
        function checkSize(count)
            if count < 1 || count > 64 * 1024^2
                error('DataHandling:NWBIdentitySize', ...
                    'The embedded identity exchange must be below 64 MiB. Use the full identity MAT export for larger stores.');
            end
        end

        function remove(path)
            if exist(path, 'file') == 2, delete(path); end
        end
    end
end
