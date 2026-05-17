BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_workspace_model_summary
AS
SELECT
    md.workspace_id,
    md.model_definition_id,
    md.model_code,
    md.model_name,
    md.model_version,
    mf.model_family_code,
    pd.problem_code,
    COUNT(DISTINCT tr.training_run_id) AS training_run_count,
    COUNT(DISTINCT br.backtest_run_id) AS backtest_run_count,
    COUNT(DISTINCT pr.prediction_run_id) AS prediction_run_count,
    MAX(tr.finished_at) AS last_training_finished_at,
    MAX(br.finished_at) AS last_backtest_finished_at,
    MAX(pr.finished_at) AS last_prediction_finished_at,
    MAX(pr.created_at) AS last_prediction_created_at
FROM ml.model_definition md
JOIN ml.model_family mf
    ON mf.model_family_id = md.model_family_id
JOIN ml.problem_definition pd
    ON pd.problem_definition_id = md.problem_definition_id
LEFT JOIN ml.training_run tr
    ON tr.model_definition_id = md.model_definition_id
LEFT JOIN ml.backtest_run br
    ON br.model_definition_id = md.model_definition_id
LEFT JOIN ml.prediction_run pr
    ON pr.model_definition_id = md.model_definition_id
GROUP BY
    md.workspace_id,
    md.model_definition_id,
    md.model_code,
    md.model_name,
    md.model_version,
    mf.model_family_code,
    pd.problem_code
WITH NO DATA;

CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_workspace_recent_predictions
AS
SELECT
    po.workspace_id,
    po.prediction_output_id,
    po.prediction_run_id,
    pr.model_definition_id,
    md.model_code,
    pd.problem_code,
    po.entity_grain,
    po.entity_key,
    po.game_id,
    po.team_id,
    po.player_id,
    po.prediction_timestamp,
    po.prediction_value,
    po.prediction_probability,
    po.lower_bound,
    po.upper_bound,
    po.class_label,
    po.rank_score,
    po.created_at
FROM ml.prediction_output po
JOIN ml.prediction_run pr
    ON pr.prediction_run_id = po.prediction_run_id
JOIN ml.model_definition md
    ON md.model_definition_id = pr.model_definition_id
JOIN ml.problem_definition pd
    ON pd.problem_definition_id = po.problem_definition_id
WITH NO DATA;

CREATE MATERIALIZED VIEW IF NOT EXISTS mart.mv_workspace_backtest_summary
AS
SELECT
    br.workspace_id,
    br.backtest_run_id,
    br.model_definition_id,
    md.model_code,
    pd.problem_code,
    br.backtest_code,
    br.backtest_status,
    br.evaluation_window_start,
    br.evaluation_window_end,
    br.bankroll_strategy_code,
    br.stake_sizing_method,
    br.started_at,
    br.finished_at,
    br.created_at,
    br.metrics_json,
    br.summary_json
FROM ml.backtest_run br
JOIN ml.model_definition md
    ON md.model_definition_id = br.model_definition_id
JOIN ml.problem_definition pd
    ON pd.problem_definition_id = md.problem_definition_id
WITH NO DATA;

COMMIT;