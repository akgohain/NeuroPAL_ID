classdef Legacy
    %LEGACY Keep retained App Designer callbacks on the configured worker path.
    methods (Static)
        function recording(app,action)
            workflow=getappdata(app.CELL_ID,'calcium_reference_workflow');
            if isempty(workflow) || ~isvalid(workflow)
                if isempty(app.video_path), uialert(app.CELL_ID,'Open a recording first.','Video Tracking'); return; end
                if ~Runtime.Settings.ensure(app,'recording_io'), return; end
                workflow=Tracking.ReferenceWorkflow.open(app,app.video_path);
            end
            switch action
                case 'recommend', Tracking.ReferenceFrames.open(workflow);
                case 'track', workflow.safe(@() workflow.track(false));
                case 'activity', workflow.safe(@() workflow.extractActivity());
                case 'save', workflow.saveDialog();
            end
        end
        function segment(folder,values)
            python=Runtime.Resolver.python('legacy_segmentation');
            script=fullfile(Runtime.Configuration.appRoot(),'External_Dependencies','3dct','CellTracker','python','npal_seg.py');
            args=cellfun(@num2str,num2cell(values),'UniformOutput',false);
            [status,detail]=Wrapper.runPythonProcess([{python,script,char(folder)},args], ...
                'WorkingDirectory',fileparts(script));
            if status~=0, error('Runtime:LegacySegmentation','Segmentation failed: %s',detail); end
        end
    end
end
