function context = main_job_context(app, include_neurons, watch_annotations)
%MAIN_JOB_CONTEXT Capture small source fields needed to import model output.

if nargin < 2, include_neurons = false; end
if nargin < 3, watch_annotations = true; end
context = struct('file', string(app.image_file), ...
    'dims', size(app.image_data), 'datatype', class(app.image_data), ...
    'scale', app.image_um_scale, 'rgbw', app.image_prefs.RGBW, ...
    'worm', app.worm, 'include_neurons', include_neurons, 'watch_annotations', watch_annotations);
if include_neurons
    context.positions = [];
    context.annotations = {};
    if ~isempty(app.image_neurons)
        context.positions = app.image_neurons.get_positions();
        context.owners = {app.image_neurons.neurons.annotation_id};
        if watch_annotations
            context.annotations = app.image_neurons.get_annotations();
            context.annotation_revision = 0;
            if isfield(app.image_neurons.annotation_store, 'revision')
                context.annotation_revision = app.image_neurons.annotation_store.revision;
            end
        end
        context.constraints = struct();
        store = app.image_neurons.annotation_store;
        if isfield(store, 'constraints_enabled') && store.constraints_enabled
            selected = store.records(~strcmp({store.records.constraint_policy}, 'off'));
            fields = {'owner_id', 'revision', 'kind', 'candidates', 'certainty', ...
                'review', 'constraint_policy', 'context_exception_reason', 'issue'};
            context.constraints = struct('enabled', true, 'records', keepFields(selected, fields));
        end
    end
end
end

function records = keepFields(records, fields)
% Keep only the selected assertions used by this model dispatch.
records = rmfield(records, setdiff(fieldnames(records), fields));
end
