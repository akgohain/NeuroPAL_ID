function annotations = constraints(image, backend, vocabulary)
%CONSTRAINTS Supply only explicitly selected, supported human constraints.
annotations = repmat({''}, numel(image.neurons), 1);
if ~isprop(image, 'annotation_store') || isempty(fieldnames(image.annotation_store)), return; end
records = Annotations.Store.constraints(image.annotation_store, backend);
for i = 1:numel(records)
    if ~strcmp(records(i).kind, 'individual')
        error('Annotations:UnsupportedConstraint', 'This adapter only accepts individual constraints. Use the typed constraint API for unresolved membership.');
    end
    if nargin >= 3 && ~any(strcmp(vocabulary, records(i).candidates{1}))
        error('Annotations:UnsupportedConstraint', ...
            'The selected atlas does not contain the hard constraint %s. Disable this constraint or select an atlas that supports it.', records(i).candidates{1});
    end
end
for i = 1:numel(image.neurons)
    index = find(strcmp({records.owner_id}, image.neurons(i).annotation_id), 1);
    if ~isempty(index)
        annotations{i} = records(index).candidates{1};
    end
end
end
