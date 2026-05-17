BEGIN;

CREATE INDEX IF NOT EXISTS idx_auth_workspace_org
    ON auth.workspace (organization_id);

CREATE INDEX IF NOT EXISTS idx_auth_workspace_membership_user
    ON auth.workspace_membership (app_user_id, workspace_id);

CREATE INDEX IF NOT EXISTS idx_auth_service_account_workspace
    ON auth.service_account (workspace_id);

CREATE INDEX IF NOT EXISTS idx_auth_api_key_workspace
    ON auth.api_key (workspace_id);

CREATE INDEX IF NOT EXISTS idx_auth_data_source_control_source
    ON auth.data_source_control (source_system_id);

CREATE INDEX IF NOT EXISTS idx_auth_workspace_source_entitlement_ws_source
    ON auth.workspace_source_entitlement (workspace_id, source_system_id);

CREATE INDEX IF NOT EXISTS idx_ml_feature_set_workspace
    ON ml.feature_set (workspace_id);

CREATE INDEX IF NOT EXISTS idx_ml_model_definition_workspace
    ON ml.model_definition (workspace_id);

CREATE INDEX IF NOT EXISTS idx_ml_dataset_definition_workspace
    ON ml.dataset_definition (workspace_id);

CREATE INDEX IF NOT EXISTS idx_ml_training_run_workspace
    ON ml.training_run (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ml_backtest_run_workspace
    ON ml.backtest_run (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ml_prediction_run_workspace
    ON ml.prediction_run (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ml_prediction_output_workspace
    ON ml.prediction_output (workspace_id, prediction_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_ml_simulation_run_workspace
    ON ml.simulation_run (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_live_game_poller_workspace
    ON ops.live_game_poller (workspace_id, poll_status);

CREATE INDEX IF NOT EXISTS idx_ops_scheduled_job_workspace
    ON ops.scheduled_job (workspace_id, active_flag);

CREATE INDEX IF NOT EXISTS idx_ops_job_run_workspace
    ON ops.job_run (workspace_id, created_at DESC);

COMMIT;