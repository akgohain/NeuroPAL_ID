function test_processing_spectral(app)
% Spectral corrections must agree across slices, source mappings, and pixel types.
names=app.proc_c1_dropdown.Items;
assert(numel(names)>=3);
previous={app.proc_c1_dropdown.Value,app.proc_c2_dropdown.Value,app.proc_c3_dropdown.Value};
cache=app.spectral_cache;
cleanup=onCleanup(@() restore(app, previous, cache));
app.proc_c1_dropdown.Value=names{3};
app.proc_c2_dropdown.Value=names{1};
app.proc_c3_dropdown.Value=names{2};
data=zeros(7,11,3,3,'single');
for z=1:3
    data(:,:,z,3)=0.1*z;
    data(:,:,z,1)=0.4+0.05*z;
    data(:,:,z,2)=0.8;
end
app.spectral_cache=Methods.ChunkyMethods.spectral_cache_template();
app.spectral_cache.coefficients=eye(3);
assert(max(abs(Methods.ChunkyMethods.debleed(app,data)-data),[],'all')<1e-7);
app.spectral_cache.coefficients(1,2)=0.5;
expected=data;
expected(:,:,:,1)=data(:,:,:,1)-0.5*data(:,:,:,3);
whole=Methods.ChunkyMethods.debleed(app,data);
assert(max(abs(whole-expected),[],'all')<1e-7);
for z=1:3
    slice=Methods.ChunkyMethods.debleed(app,data(:,:,z,:));
    assert(max(abs(slice-whole(:,:,z,:)),[],'all')<1e-7);
end
app.spectral_cache.coefficients=nan(3);
app.spectral_cache.background_vector=[0.1 0.2 0.3];
expected=data;
indices=[3 1 2]; background=[0.1 0.2 0.3];
for i=1:3, expected(:,:,:,indices(i))=max(data(:,:,:,indices(i))-background(i),0); end
actual=Methods.ChunkyMethods.debleed(app,data);
assert(max(abs(actual-expected),[],'all')<1e-7);
filtered=Methods.ChunkyMethods.spectral_filtered_rgb_volume(data(:,:,1,:),[3 1 2],1);
assert(all(isfinite(filtered),'all'));
fprintf('PROCESSING_SPECTRAL=PASS\n');
end

function restore(app, previous, cache)
app.proc_c1_dropdown.Value=previous{1};
app.proc_c2_dropdown.Value=previous{2};
app.proc_c3_dropdown.Value=previous{3};
app.spectral_cache=cache;
end
