function test_performance_contracts()
%TEST_PERFORMANCE_CONTRACTS Check bounded operations without loading ML models.
previous_path = path;
cleanup = onCleanup(@() path(previous_path));
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, fullfile(root, 'scripts'));
addpath(genpath(fullfile(root, 'External_Dependencies')));
test_heavy_job;
test_color_readout;
test_histmatch_memory;
test_debug_array_summary;
test_main_display_view;
test_npal_mat_source;
test_import_memory;
test_nwb_stream_export;
test_processing_transaction;
test_nn_streaming;
test_autoid_resource_cleanup;
test_display_export_source;
test_ui_resource_lifecycle;
test_tracking_roi;
test_video_views;
test_video_slider;
test_python_process;
fprintf('PERFORMANCE_CONTRACTS=PASS\n');
end
