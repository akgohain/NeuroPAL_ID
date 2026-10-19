function report=test_manual_individual_id(app)
%TEST_MANUAL_INDIVIDUAL_ID Validate exact IDs and explicit save/reload independently of predictions.
if nargin<1, app=Program.app; end
report=test_manual_id_contract_ui(app);
fprintf('MANUAL_INDIVIDUAL_ID_IL1L_SAVE_RELOAD=PASS\n');
end
