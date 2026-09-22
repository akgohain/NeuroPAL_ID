classdef SessionReset
    %SESSIONRESET Clear workflow results while keeping the recording open.
    methods (Static)
        function confirm(c)
            if c.Busy, return; end
            c.View.Playback.stop();
            answer=uiconfirm(c.App.CELL_ID, ...
                ['Clear all detections, neuron tracks, activity traces and review history in this session? ' ...
                 'Unsaved work will be lost and this cannot be undone. The recording, image settings and saved files will be kept.'], ...
                'Reset session?','Options',{'Cancel','Reset session'},'DefaultOption',1,'CancelOption',1,'Icon','warning');
            if ~strcmp(answer,'Reset session') || c.Busy, return; end
            c.safe(@() Tracking.SessionReset.clear(c));
            c.View.setStage(2);
        end
        function clear(c)
            c.View.Playback.stop(); c.View.Preview.cancel(); c.View.FramePreview.cancel();
            c.Rows=zeros(0,7); c.Candidates=zeros(0,7); c.CandidateFrame=0; c.NextID=1;
            c.Excluded=zeros(0,2); c.Origins=containers.Map('KeyType','char','ValueType','char');
            Tracking.NeuronNames.set(c,[]); setappdata(c.Grid,'paired_reference_provenance',[]);
            c.History={}; c.Provenance=struct(); c.Cursor=[];
            c.TrackDirectory=''; c.ActivityDirectory='';
            c.ActivityRows=[]; c.ActivityExcluded=[]; c.ActivitySettings=struct();
            c.Reference.Value=c.Frame.Value; c.First.Value=1; c.Last.Value=c.Source.nt;
            v=c.View; v.Review.clear(); v.Selection=[]; v.PreferredID=1;
            v.CorrectMode=false; v.AddMode=false; c.Buttons.add.Text='Add neuron';
            v.ListKey={}; v.TableRows=[]; v.IndexedRows=[]; v.FrameIndices={}; v.ProjectionKey={};
            if ~isempty(v.TableWindow) && isvalid(v.TableWindow), delete(v.TableWindow); v.TableWindow=[]; end
            a=c.Analysis; a.ResultKey=''; a.Frames=[]; a.IDs=[]; a.PlotKey={}; a.ResultOptions=struct();
            a.Mode.UserData=false; a.Mode.Value='ΔF/F';
            button=findobj(a.Mode.Parent,'Tag','activity_population_toggle'); button.Text='Population';
            c.render();
        end
    end
end
