function context = main_job_context(app, include_neurons)
%MAIN_JOB_CONTEXT Capture small source fields needed to import model output.

if nargin < 2, include_neurons = false; end
context = struct('file', string(app.image_file), ...
    'dims', size(app.image_data), 'datatype', class(app.image_data), ...
    'scale', app.image_um_scale, 'rgbw', app.image_prefs.RGBW, ...
    'worm', app.worm, 'include_neurons', include_neurons);
if include_neurons
    context.positions = [];
    context.annotations = {};
    if ~isempty(app.image_neurons)
        context.positions = app.image_neurons.get_positions();
        context.annotations = app.image_neurons.get_annotations();
    end
end
end
