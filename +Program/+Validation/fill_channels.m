function fill_channels(data)
    app = Program.app;
    if isempty(app)
        return
    end
    if strcmp(app.proc_c1_dropdown.Value, 'None')
        channel_count = size(data, 4);
        new_items = arrayfun(@(x) sprintf('Fluor #%d', x), 1:size(data,4), 'UniformOutput', false);

        % Display roles are fixed; every source channel remains selectable in each row.
        row_count = Program.Handlers.channels.config{'max_channels'};
        for c=1:min(channel_count,row_count)
            handle = sprintf(Program.Handlers.channels.handles{'pp_dd'}, c);
            if ~isprop(app, handle) || ~isgraphics(app.(handle)), continue; end

            app.(handle).Items = new_items;
            app.(handle).Value = new_items{c};
        end
    end
end
