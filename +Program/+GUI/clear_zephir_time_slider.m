function clear_zephir_time_slider(app)
%CLEAR_ZEPHIR_TIME_SLIDER Release the preview timer and pending requests.
if isempty(app) || ~isvalid(app) || isempty(app.CELL_ID) || ~isvalid(app.CELL_ID)
    return
end
key = 'video_tslider_timer';
if isappdata(app.CELL_ID,key)
    worker = getappdata(app.CELL_ID,key);
    rmappdata(app.CELL_ID,key);
    if ~isempty(worker) && isvalid(worker)
        stop(worker);
        delete(worker);
    end
end
if isappdata(app.CELL_ID,'video_tslider_state')
    rmappdata(app.CELL_ID,'video_tslider_state');
end
end
