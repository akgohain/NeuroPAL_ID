function render_processing_zticklabels(app)
    % Processing z labels now use the slider's native MajorTickLabels.

    delete(findall(app.ProcAxPanel, 'Tag', 'proc_z_tick_label'));
end
