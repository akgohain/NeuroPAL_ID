classdef NeuronIDChooser
    %NEURONIDCHOOSER Browse individual atlas names independently of model ranks.
    methods (Static)
        function open(app)
            index=app.selected_neuron;
            if isempty(app.image_neurons) || isempty(index) || ~isscalar(index) || ...
                    ~isfinite(index) || index~=round(index) || index<1 || ...
                    index>numel(app.image_neurons.neurons)
                uialert(app.CELL_ID,'Select a neuron in the image or candidate list first.','Choose neuron ID'); return;
            end
            Program.GUI.ManualIDInput.build(app);
            app.TabGroup.SelectedTab=app.NeuroPALIDTab;
            Program.GUI.ManualIDController.select(app,index);
            Program.GUI.ManualIDController.open(app);
            ui=Program.GUI.ManualIDController.ui(app);
            if ~isempty(ui), Program.GUIHandling.send_focus(ui.input); end
        end
        function names=names(sex)
            % Include the full atlas, independently of the image's model ranks.
            if nargin<1, sex=''; end
            names=Annotations.Catalog.names(sex);
        end
        function name=individualName(candidate,sex)
            % A model class must be resolved before it can be assigned as an ID.
            if nargin<2, sex=''; end
            name=''; info=Annotations.Catalog.lookup(candidate,sex);
            if strcmp(info.kind,'individual') && info.applicable, name=info.token; end
        end
        function matches=matchingNames(names,predictions,scope,query,mapping)
            % Unqualified labels are catalog lookups, not inferred model mappings.
            if nargin<5, mapping=[]; end
            names=cellstr(string(names(:)));
            keep=contains(upper(string(names)),upper(strtrim(string(query))));
            exact=Annotations.Catalog.lookup(query,'');
            if strcmp(exact.kind,'individual'), keep=keep | strcmp(names,exact.token); end
            if strcmp(scope,'Suggested classes')
                suggested=false(size(keep));
                predictions=cellstr(string(predictions));
                for i=1:numel(predictions)
                    token=strtrim(predictions{i});
                    if isempty(token), continue; end
                    if isempty(mapping)
                        members=Annotations.Catalog.members(token,'',true);
                    elseif isstruct(mapping) && isscalar(mapping) && isfield(mapping,'bundle_id')
                        vocabulary='';
                        if isfield(mapping,'vocabulary_version'), vocabulary=mapping.vocabulary_version; end
                        members=Annotations.Catalog.modelMembers(mapping.bundle_id,token,vocabulary);
                    else
                        members={};
                    end
                    suggested=suggested | ismember(names,members);
                end
                keep=keep & suggested;
            end
            matches=names(keep);
        end
        function filter(list,use,names,predictions,scope,query)
            selected=cellstr(string(list.Value));
            matches=Program.GUI.NeuronIDChooser.matchingNames(names,predictions,scope,query);
            list.Multiselect='on'; list.Value={}; list.ItemsData=[];
            list.Items=matches;
            if numel(selected)==1 && any(strcmp(matches,selected{1}))
                list.Value=selected;
            end
            use.Enable=matlab.lang.OnOffSwitchState(~isempty(list.Value));
        end
        function matches=selectionMatches(app,index,file,neuron)
            % A replaced neuron array may reuse the same selected index.
            matches=isvalid(app) && ~isempty(app.image_neurons) && ...
                isequal(app.selected_neuron,index) && isscalar(index) && ...
                isfinite(index) && index==round(index) && index>=1 && ...
                index<=numel(app.image_neurons.neurons) && strcmp(app.image_file,file) && ...
                isequal(app.image_neurons.neurons(index),neuron);
        end
        function use(app,index,file,list,window)
            if isempty(list.Value), return; end
            selected=cellstr(string(list.Value));
            if numel(selected)~=1, return; end
            selection=getappdata(window,'neuron_id_chooser_selection');
            if isempty(selection) || ...
                    ~Program.GUI.NeuronIDChooser.selectionMatches(app,index,file,selection.neuron) || ...
                    ~strcmp(app.worm.sex,selection.sex)
                uialert(window,'The selected neuron changed. Reopen the chooser.','Choose neuron ID'); return;
            end
            info=Annotations.Catalog.lookup(selected{1},app.worm.sex);
            if ~strcmp(info.kind,'individual') || ~info.applicable
                uialert(window,'Choose an individual neuron name from the current atlas.','Choose neuron ID'); return;
            end
            delete(window);
            Program.GUI.NeuronIDChooser.open(app);
            Program.GUI.ManualIDController.edited(app,info.token,true);
        end
    end
end
