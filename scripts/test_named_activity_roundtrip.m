function result = test_named_activity_roundtrip(c,output)
%TEST_NAMED_ACTIVITY_ROUNDTRIP Retain names and edits with measured activity.
assert(c.activityCurrent());
Tracking.NeuronNames.set(c,Tracking.NeuronNames.get(c));
original=c.Rows; identities=Tracking.NeuronNames.get(c); response=c.save(output);
Tracking.SessionReset.clear(c); c.load(fullfile(response.directory,'annotations.h5'));
assert(isequal(c.Rows,original) && isequal(Tracking.NeuronNames.get(c),identities));
assert(c.activityCurrent() && ~isempty(getappdata(c.Grid,'paired_reference_provenance')));
index=find(strlength(string({identities.name}))>0,1); edited=identities;
edited(index).name=[identities(index).name '_review']; edited(index).source='reviewed'; edited(index).confidence=1;
Tracking.NeuronNames.set(c,edited); c.exportActivity(output);
exported=char(extractAfter(c.Status.Text,'Exported activity and tracks: ')); assert(isfolder(exported));
ids=h5read(fullfile(exported,'activity.h5'),'/neuron_id'); names=string(h5read(fullfile(exported,'activity.h5'),'/neuron_name'));
assert(names(ids==edited(index).id)==string(edited(index).name));
sources=string(h5read(fullfile(exported,'activity.h5'),'/identity_source'));
assert(sources(ids==edited(index).id)=="reviewed");
original_names=string(h5read(fullfile(c.ActivityDirectory,'activity.h5'),'/neuron_name'));
assert(original_names(ids==edited(index).id)==string(identities(index).name));
Tracking.NeuronNames.set(c,identities); final=c.save(output);
result=struct('session_directory',final.directory,'edited_export_directory',exported,'name_roundtrip_passed',true);
fprintf('NAMED_ACTIVITY_ROUNDTRIP=PASS\n');
end
