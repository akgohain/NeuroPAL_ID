function test_processing_legacy_orientation(app)
%TEST_PROCESSING_LEGACY_ORIENTATION Supply missing legacy display preferences.
if nargin<1, app=Program.app; end
original=app.image_file;
folder=fullfile(tempname,'processing-audit'); mkdir(folder);
cleanup=onCleanup(@() restore(app,original,folder));
for preserve=[false true]
    file=fullfile(folder,sprintf('legacy-%d.mat',preserve));
    data=reshape(uint16(1:9*13*5*4),[9 13 5 4]);
    info=struct('scale',[.4 .6 1.5],'gamma',.8);
    prefs=struct('RGBW',[1 2 3 4],'DIC',NaN,'GFP',NaN,'gamma',.8, ...
        'rotate',struct('horizontal',false,'vertical',false));
    if preserve, prefs.is_Z_LR=false; prefs.is_Z_flip=false; end
    worm=struct('body','Head','age','Adult','sex','XX','strain','','notes','');
    version=Program.ProgramInfo.version;
    save(file,'data','info','prefs','worm','version','-v7.3');
    before=Annotations.Store.fingerprint(file);
    Program.ProcessingSession.clear(app); app.flags=struct(); app.image_data=[];
    Program.Routines.Processing.load_file('image',file);
    assert(app.image_prefs.z_center==3);
    assert(app.image_prefs.is_Z_LR==~preserve && app.image_prefs.is_Z_flip==~preserve);
    assert(isequaln(Annotations.Store.fingerprint(file),before),'Loading must not rewrite legacy pixels or preferences.');
    Program.Helpers.sync_main_display_from_processing(app,true);
    Program.Routines.Processing.reset();
    assert(app.image_prefs.z_center==3 && app.image_prefs.is_Z_flip==~preserve);
    assert(isequal(app.image_data,data));
end
fprintf('PROCESSING_LEGACY_ORIENTATION_DEFAULTS_PRESERVE_EXPLICIT_VALUES=PASS\n');
end

function restore(app,file,folder)
Program.ProcessingSession.clear(app); app.flags=struct();
if ~isempty(file) && isfile(file), Program.Routines.Processing.load_file('image',file); end
if isfolder(folder), rmdir(fileparts(folder),'s'); end
end
