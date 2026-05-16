BEGIN;

CREATE INDEX IF NOT EXISTS ml_problem_definition_grain_idx
    ON ml.problem_definition (target_grain, target_type);

CREATE INDEX IF NOT EXISTS ml_feature_set_grain_idx
    ON ml.feature_set (entity_grain, is_realtime_compatible);

CREATE INDEX IF NOT EXISTS ml_feature_definition_feature_name_idx
    ON ml.feature_definition (feature_name);

CREATE INDEX IF NOT EXISTS ml_model_definition_problem_status_idx
    ON ml.model_definition (problem_definition_id, status_code);

CREATE INDEX IF NOT EXISTS ml_training_run_model_status_idx
    ON ml.training_run (model_definition_id, training_status, created_at DESC);

CREATE INDEX IF NOT EXISTS ml_feature_snapshot_lookup_idx
    ON ml.feature_snapshot (feature_set_id, entity_grain, snapshot_timestamp DESC);

CREATE INDEX IF NOT EXISTS ml_feature_snapshot_game_idx
    ON ml.feature_snapshot (game_id, snapshot_timestamp DESC);

CREATE INDEX IF NOT EXISTS ml_dataset_split_lookup_idx
    ON ml.dataset_split (dataset_definition_id, split_type, fold_number);

CREATE INDEX IF NOT EXISTS ml_backtest_run_model_status_idx
    ON ml.backtest_run (model_definition_id, backtest_status, created_at DESC);

CREATE INDEX IF NOT EXISTS ml_prediction_run_model_status_idx
    ON ml.prediction_run (model_definition_id, run_status, created_at DESC);

CREATE INDEX IF NOT EXISTS ml_prediction_output_entity_idx
    ON ml.prediction_output (entity_grain, entity_key, prediction_timestamp DESC);

CREATE INDEX IF NOT EXISTS ml_prediction_output_game_idx
    ON ml.prediction_output (game_id, prediction_timestamp DESC);

CREATE INDEX IF NOT EXISTS ml_prediction_output_player_idx
    ON ml.prediction_output (player_id, prediction_timestamp DESC);

CREATE INDEX IF NOT EXISTS ml_prediction_evaluation_prediction_idx
    ON ml.prediction_evaluation (prediction_output_id);

CREATE INDEX IF NOT EXISTS ml_simulation_run_type_idx
    ON ml.simulation_run (simulation_type, created_at DESC);

CREATE INDEX IF NOT EXISTS ops_live_game_poller_status_idx
    ON ops.live_game_poller (poll_status, start_poll_at);

CREATE INDEX IF NOT EXISTS ops_scheduled_job_type_active_idx
    ON ops.scheduled_job (job_type, active_flag);

CREATE INDEX IF NOT EXISTS ops_job_run_job_code_status_idx
    ON ops.job_run (job_code, run_status, created_at DESC);

COMMIT;