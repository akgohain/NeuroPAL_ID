classdef CallbackBoundary
    %CALLBACKBOUNDARY Report menu failures without losing the annotation window.
    methods (Static)
        function install(app)
            overrides={'ZephIRoutputMenu',@(~,~) Program.ActivityImport.choose(app,'csv'); ...
                'NWBfileMenu_2',@(~,~) Program.ActivityImport.choose(app,'nwb'); ...
                'DisplayNeuronActivityMenu',@(~,~) Program.ActivityImport.display(app); ...
                'TraceActivityMenu_2',@(~,~) Program.ActivityImport.recording(app); ...
                'BatchDetectIDNeuronsMenu',@(~,~) Program.ActivityImport.unavailableBatch(app)};
            for i=1:size(overrides,1)
                if ~isprop(app,overrides{i,1}), continue; end
                menu=app.(overrides{i,1});
                if ~isempty(menu) && isvalid(menu) && ~isappdata(menu,'guarded_menu_callback')
                    menu.MenuSelectedFcn=overrides{i,2};
                end
            end
            app.LoadNeuronActivityButton.ButtonPushedFcn=@(~,~) Program.CallbackBoundary.activity(app);
            menus=findall(app.CELL_ID,'Type','uimenu');
            for i=1:numel(menus)
                menu=menus(i);
                if isempty(menu.MenuSelectedFcn) || isappdata(menu,'guarded_menu_callback'), continue; end
                setappdata(menu,'guarded_menu_callback',menu.MenuSelectedFcn);
                menu.MenuSelectedFcn=@(src,event) Program.CallbackBoundary.invoke(app,src,event);
            end
        end
        function activity(app)
            try
                Program.ActivityImport.choose(app);
            catch ME
                Program.CallbackBoundary.report(app,ME,'Import neuron activity');
            end
        end
        function invoke(app,menu,event)
            if ~isvalid(menu), return; end
            callback=getappdata(menu,'guarded_menu_callback');
            try
                Program.GUIHandling.invoke_gui_callback(callback,menu,event);
            catch ME
                Program.CallbackBoundary.report(app,ME,menu.Text);
            end
        end
        function report(app,failure,title)
            try
                if ~isvalid(app.CELL_ID), return; end
                detail=struct('identifier',failure.identifier,'message',failure.message, ...
                    'details',getReport(failure,'extended','hyperlinks','off'));
                setappdata(app.CELL_ID,'last_menu_failure',detail);
                Program.Helpers.debug_event('Menu','%s: %s',title,detail.details);
                uialert(app.CELL_ID,Program.GUIHandling.method_error_message(failure),title);
            catch
                % A closing parent cannot display another dialog or accept further edits.
            end
        end
    end
end
