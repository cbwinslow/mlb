BEGIN;

CREATE INDEX IF NOT EXISTS idx_ml_feature_set_workspace_created
    ON ml.feature_set (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ml_model_definition_workspace_created
    ON ml.model_definition (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ml_dataset_definition_workspace_created
    ON ml.dataset_definition (workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ml_prediction_output_workspace_game_ts
    ON ml.prediction_output (workspace_id, game_id, prediction_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_ops_scheduled_job_workspace_active_created
    ON ops.scheduled_job (workspace_id, active_flag, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ops_job_run_workspace_status_created
    ON ops.job_run (workspace_id, run_status, created_at DESC);

COMMIT;