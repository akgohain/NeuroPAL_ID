classdef MainMethodSettings
    %MAINMETHODSETTINGS Keep model choices out of the main image toolbar.
    methods (Static)
        function grid=build(app,group,title)
            window=uifigure('Name',[title ' settings'],'Visible','off','Position',[300 300 760 160]);
            window.CloseRequestFcn=@(src,~) set(src,'Visible','off');
            grid=uigridlayout(window,[2 1]); grid.RowHeight={32,32};
            grid.Padding=[12 12 12 12];
            if strcmp(group,'id')
                grid.RowHeight={32,32,28}; window.Position(4)=190;
                checkbox=uicheckbox(grid,'Text','Use confirmed IDs as CRF constraints', ...
                    'Value',false,'Tag','ManualIDConstraintPolicy', ...
                    'Tooltip','Explicitly constrain a CRF run. Tentative IDs are never hard constraints; other models retain their own supported input rules.', ...
                    'ValueChangedFcn',@(src,~) Program.GUI.ManualIDService.setConstraints(app,src.Value));
                checkbox.Layout.Row=3;
            end
            row=numel(grid.RowHeight)+1; grid.RowHeight{row}=32; window.Position(4)=window.Position(4)+40;
            button=uibutton(grid,'Text','Models & runtimes…', ...
                'ButtonPushedFcn',@(~,~) Runtime.Settings.open(app,Program.GUIHandling.main_method_identity(app,group)));
            button.Layout.Row=row;
            setappdata(app.CELL_ID,['main_' group '_settings_window'],window);
            addlistener(app.CELL_ID,'ObjectBeingDestroyed',@(~,~) Program.GUI.MainMethodSettings.close(window));
        end
        function open(app,group)
            window=getappdata(app.CELL_ID,['main_' group '_settings_window']);
            if isempty(window) || ~isvalid(window), return; end
            Program.GUI.MainDetectionInput.refresh(app);
            if strcmp(group,'id')
                checkbox=findall(window,'Tag','ManualIDConstraintPolicy');
                checkbox.Enable=matlab.lang.OnOffSwitchState(~isempty(app.image_neurons));
                if ~isempty(app.image_neurons)
                    store=Program.GUI.ManualIDService.ensure(app);
                    checkbox.Value=store.constraints_enabled;
                end
            end
            window.Visible='on'; figure(window);
        end
        function close(window)
            if isvalid(window), delete(window); end
        end
    end
end
