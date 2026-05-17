BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_workspace_model_summary
    ON mart.mv_workspace_model_summary (workspace_id, model_definition_id);

CREATE INDEX IF NOT EXISTS idx_mv_workspace_model_summary_workspace_problem
    ON mart.mv_workspace_model_summary (workspace_id, problem_code, last_prediction_created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_workspace_recent_predictions
    ON mart.mv_workspace_recent_predictions (prediction_output_id);

CREATE INDEX IF NOT EXISTS idx_mv_workspace_recent_predictions_workspace_ts
    ON mart.mv_workspace_recent_predictions (workspace_id, prediction_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_mv_workspace_recent_predictions_workspace_game
    ON mart.mv_workspace_recent_predictions (workspace_id, game_id, prediction_timestamp DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_workspace_backtest_summary
    ON mart.mv_workspace_backtest_summary (backtest_run_id);

CREATE INDEX IF NOT EXISTS idx_mv_workspace_backtest_summary_workspace_created
    ON mart.mv_workspace_backtest_summary (workspace_id, created_at DESC);

COMMIT;