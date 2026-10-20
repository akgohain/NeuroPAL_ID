function test_processing_defaults_source()
% Check source changes and bounds before downsample values reach UI controls.
app = struct('VolumeDropDown',struct('Value','Colormap'), ...
    'image_file','first.mat','video_info',struct('file','first.mat'));
first = Program.GUIHandling.processing_defaults_source_key(app);
snapshot = struct('source_key',first,'xy_factor',.5,'z_slices',39);
geometry = Program.Helpers.processing_default_geometry(snapshot,first,[218 905 39]);
assert(geometry.source_matches && geometry.xy_factor==.5 && geometry.z_slices==39);

% A different volume starts at full resolution, even when old values fit.
app.image_file = 'second.mat';
second = Program.GUIHandling.processing_defaults_source_key(app);
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 5]);
assert(~geometry.source_matches && geometry.xy_factor==1 && geometry.z_slices==5);
snapshot.z_slices = 3;
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 5]);
assert(~geometry.source_matches && geometry.xy_factor==1 && geometry.z_slices==5);
video = Program.GUIHandling.processing_defaults_source_key(app,'video');
assert(~strcmp(video,first));
geometry = Program.Helpers.processing_default_geometry(snapshot,video,[21 23 5]);
assert(~geometry.source_matches && geometry.xy_factor==1 && geometry.z_slices==5);

% Same-source saved settings survive reset, with bounds applied before Value.
snapshot.source_key = second; snapshot.xy_factor = .5; snapshot.z_slices = 3;
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 5]);
assert(geometry.source_matches && geometry.xy_factor==.5 && geometry.z_slices==3);
snapshot.xy_factor = 4; snapshot.z_slices = 39;
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 5]);
assert(geometry.xy_factor==1 && geometry.z_slices==5);
snapshot.xy_factor = 0; snapshot.z_slices = -2;
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 5]);
assert(geometry.xy_factor==1/23 && geometry.z_slices==1);
snapshot.xy_factor = NaN; snapshot.z_slices = Inf;
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 1]);
assert(geometry.xy_factor==1 && geometry.z_slices==1);

% Unbound snapshots from older app versions cannot carry prior-source settings.
snapshot = rmfield(snapshot,'source_key');
geometry = Program.Helpers.processing_default_geometry(snapshot,second,[21 23 5]);
assert(~geometry.source_matches && geometry.xy_factor==1 && geometry.z_slices==5);
fprintf('PROCESSING_DEFAULTS_SOURCE_BOUNDS=PASS\n');
end
