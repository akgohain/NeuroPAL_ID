classdef ManualIDInput
    %MANUALIDINPUT Keep the compact ID editor separate from saved annotations.
    methods (Static)
        function build(app)
            input=getappdata(app.IDEditField,'manual_id_input');
            if ~isempty(input) && isvalid(input), return; end
            input=uieditfield(app.IDEditField.Parent,'text', ...
                'Value',app.IDEditField.Value,'Placeholder','Neuron ID', ...
                'Tag','ManualNeuronIDInput','Enable',app.IDEditField.Enable, ...
                'FontSize',app.IDEditField.FontSize, ...
                'Tooltip','Type an ID. Enter accepts a suggestion; Tab focuses Assign. Activate Assign to save.');
            input.Layout.Row=app.IDEditField.Layout.Row;
            input.Layout.Column=app.IDEditField.Layout.Column;
            app.IDEditField.Visible='off';
            setappdata(app.IDEditField,'manual_id_input',input);
            setappdata(app.IDEditField,'manual_id_owner',app);
            input.ValueChangingFcn=@(~,event) Program.GUI.ManualIDController.edited(app,event.Value);
            input.ValueChangedFcn=@(src,~) Program.GUI.ManualIDController.edited(app,src.Value,false);

            panel=uipanel(app.CELL_ID,'Visible','off','BorderType','line', ...
                'BackgroundColor',[.98 .98 .98],'Position',[1 1 360 290],'Tag','ManualIDSuggestions');
            grid=uigridlayout(panel,[3 1]); grid.Padding=[5 5 5 5]; grid.RowSpacing=3;
            grid.RowHeight={'1x',24,26};
            list=uilistbox(grid,'Items',{},'ItemsData',[], ...
                'Multiselect','on','Value',{},'FontSize',input.FontSize, ...
                'Tag','ManualIDMatches','Tooltip','Individual IDs and explicit anatomical groups.');
            list.ValueChangedFcn=@(src,~) Program.GUI.ManualIDController.highlight(app,src.Value);
            list.ClickedFcn=@(~,event) Program.GUI.ManualIDController.clicked(app,event);
            list.DoubleClickedFcn=@(~,~) [];
            status=uilabel(grid,'Text','','FontSize',11,'FontColor',[.3 .3 .3], ...
                'Tag','ManualIDStatus');
            actions=uigridlayout(grid,[1 3]); actions.Padding=[0 0 0 0];
            actions.ColumnWidth={'1x','1x','1x'}; actions.ColumnSpacing=4;
            all=uibutton(actions,'Text','All atlas names','FontSize',11, ...
                'Tag','ManualIDAllNames','ButtonPushedFcn',@(~,~) Program.GUI.ManualIDController.toggleAll(app));
            clear=uibutton(actions,'Text','Clear ID','FontSize',11, ...
                'Tag','ManualIDClear','ButtonPushedFcn',@(~,~) Program.GUI.ManualIDController.clear(app));
            undo=uibutton(actions,'Text','Undo','FontSize',11, ...
                'Tag','ManualIDUndo','ButtonPushedFcn',@(~,~) Program.GUI.ManualIDController.undo(app));
            setappdata(app.IDEditField,'manual_id_ui',struct('input',input,'panel',panel, ...
                'list',list,'status',status,'all',all,'clear',clear,'undo',undo));
            app.AutoNameCheckBox.Tooltip='Prefill a provisional prediction. Suggestions remain available when off.';
            app.AutoNameCheckBox.ValueChangedFcn=@(~,~) Program.GUI.ManualIDInput.saveAutoName(app);
            if isprop(app,'AutoNameLabel'), app.AutoNameLabel.Text='Prefill prediction:'; end
            Program.GUI.ManualIDController.orderEditor(app);
            Program.GUI.ManualIDController.install(app);
        end
        function sync(app)
            if ~isvalid(app) || isempty(app.IDEditField) || ~isvalid(app.IDEditField), return; end
            input=getappdata(app.IDEditField,'manual_id_input');
            if isempty(input) || ~isvalid(input), return; end
            if ~strcmp(input.Value,app.IDEditField.Value), input.Value=app.IDEditField.Value; end
            input.Enable=app.IDEditField.Enable;
        end
        function setValue(app,value)
            % Existing selection routines can still supply a provisional value.
            app.IDEditField.Value=value;
            Program.GUI.ManualIDInput.sync(app);
            if strcmp(app.IDEditField.Enable,'off'), Program.GUI.ManualIDController.close(app); end
        end
        function setEnabled(app,value)
            app.IDEditField.Enable=value;
            Program.GUI.ManualIDInput.sync(app);
            if strcmp(app.IDEditField.Enable,'off'), Program.GUI.ManualIDController.close(app); end
        end
        function refreshNames(app)
            Program.GUI.ManualIDController.refresh(app);
        end
        function changed(app,input)
            Program.GUI.ManualIDController.edited(app,input.Value,false);
        end
        function result=commit(app,text,index,event)
            if nargin<2, text=[]; end
            if nargin<3, index=app.selected_neuron; end
            gesture=[];
            if nargin>=4, gesture=Program.GUI.ManualIDController.consumeGesture(app,event); end
            result=Program.GUI.ManualIDController.assign(app,index,text,'assign',gesture);
        end
        function saveAutoName(app)
            prefs=Program.GUIPreferences.instance();
            prefs.is_auto_name=app.AutoNameCheckBox.Value;
            prefs.save();
        end
    end
end
