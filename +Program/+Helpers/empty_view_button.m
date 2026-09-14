function button = empty_view_button(parent, text, callback, button)
% Keep unloaded views focused on their open action.
grid = uigridlayout(parent, 'ColumnWidth', {'1x', 180, '1x'}, ...
    'RowHeight', {'1x', 40, '1x'}, 'Padding', [16 16 16 16]);
grid.BackgroundColor = [0.97 0.97 0.97];
if nargin < 4
    button = uibutton(grid, 'push', 'ButtonPushedFcn', callback);
else
    button.Parent = grid;
end
button.Layout.Row = 2;
button.Layout.Column = 2;
button.Text = text;
button.FontSize = 15;
button.FontWeight = 'normal';
button.BackgroundColor = [0.88 0.88 0.88];
button.FontColor = [0.15 0.15 0.15];
button.Visible = 'on';
button.Enable = 'on';
end
