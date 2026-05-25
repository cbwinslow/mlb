BEGIN;

CREATE TABLE IF NOT EXISTS ml.backtest_run (
    backtest_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_definition_id BIGINT NOT NULL
        REFERENCES ml.model_definition(model_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    dataset_definition_id BIGINT
        REFERENCES ml.dataset_definition(dataset_definition_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    backtest_code TEXT NOT NULL,
    backtest_status TEXT NOT NULL DEFAULT 'queued',
    evaluation_window_start DATE,
    evaluation_window_end DATE,
    bankroll_strategy_code TEXT,
    stake_sizing_method TEXT,
    run_config_json JSONB,
    metrics_json JSONB,
    summary_json JSONB,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ml_backtest_run_unique
        UNIQUE (model_definition_id, backtest_code)
);

COMMENT ON TABLE ml.backtest_run IS
    'Backtest execution record for historical simulation and strategy testing.';

CREATE TABLE IF NOT EXISTS ml.prediction_run (
    prediction_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_definition_id BIGINT NOT NULL
        REFERENCES ml.model_definition(model_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    run_mode TEXT NOT NULL,
    run_status TEXT NOT NULL DEFAULT 'queued',
    scheduled_for TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    trigger_source TEXT,
    run_context_json JSONB,
    metrics_json JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.prediction_run IS
    'Prediction execution record for batch, scheduled, ad hoc, or live scoring runs.';

CREATE TABLE IF NOT EXISTS ml.prediction_output (
    prediction_output_id BIGSERIAL PRIMARY KEY,
    prediction_run_id UUID NOT NULL
        REFERENCES ml.prediction_run(prediction_run_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    problem_definition_id BIGINT NOT NULL
        REFERENCES ml.problem_definition(problem_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    entity_grain TEXT NOT NULL,
    entity_key TEXT NOT NULL,
    game_id UUID
        REFERENCES core.games(game_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    team_id BIGINT
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id BIGINT
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    plate_appearance_id UUID
        REFERENCES core.plate_appearances(plate_appearance_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    pitch_id UUID
        REFERENCES core.pitches(pitch_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    prediction_timestamp TIMESTAMPTZ NOT NULL,
    prediction_value NUMERIC(18,8),
    prediction_probability NUMERIC(18,8),
    lower_bound NUMERIC(18,8),
    upper_bound NUMERIC(18,8),
    class_label TEXT,
    rank_score NUMERIC(18,8),
    explanation_json JSONB,
    feature_snapshot_id BIGINT
        REFERENCES ml.feature_snapshot(feature_snapshot_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.prediction_output IS
    'Stores model predictions, probabilities, intervals, ranks, and explanation payloads.';

CREATE TABLE IF NOT EXISTS ml.prediction_evaluation (
    prediction_evaluation_id BIGSERIAL PRIMARY KEY,
    prediction_output_id BIGINT NOT NULL
        REFERENCES ml.prediction_output(prediction_output_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    actual_value NUMERIC(18,8),
    actual_class_label TEXT,
    evaluation_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    error_value NUMERIC(18,8),
    absolute_error NUMERIC(18,8),
    squared_error NUMERIC(18,8),
    log_loss_value NUMERIC(18,8),
    brier_score_value NUMERIC(18,8),
    roi_value NUMERIC(18,8),
    evaluation_notes TEXT
);

COMMENT ON TABLE ml.prediction_evaluation IS
    'Stores realized outcomes and scoring metrics for each prediction.';

CREATE TABLE IF NOT EXISTS ml.simulation_run (
    simulation_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_definition_id BIGINT
        REFERENCES ml.model_definition(model_definition_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    simulation_code TEXT NOT NULL UNIQUE,
    simulation_type TEXT NOT NULL,
    entity_grain TEXT NOT NULL,
    simulation_count INT NOT NULL,
    parameter_json JSONB,
    summary_json JSONB,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.simulation_run IS
    'Monte Carlo, state-transition, or scenario simulation runs.';

CREATE TABLE IF NOT EXISTS ops.live_game_poller (
    live_game_poller_id BIGSERIAL PRIMARY KEY,
    mlbam_game_pk BIGINT NOT NULL,
    game_id UUID
        REFERENCES core.games(game_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    poll_status TEXT NOT NULL DEFAULT 'queued',
    start_poll_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_poll_at TIMESTAMPTZ,
    poll_interval_seconds INT NOT NULL DEFAULT 15,
    last_polled_at TIMESTAMPTZ,
    stop_reason TEXT,
    latest_abstract_game_state TEXT,
    latest_coded_game_state TEXT,
    latest_detailed_state TEXT,
    latest_payload_timestamp TIMESTAMPTZ,
    latest_payload_hash BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ops_live_game_poller_game_unique
        UNIQUE (mlbam_game_pk)
);

COMMENT ON TABLE ops.live_game_poller IS
    'Tracks active polling jobs for live MLB games and stores latest status fields used to determine when polling should stop.';

CREATE TABLE IF NOT EXISTS ops.scheduled_job (
    scheduled_job_id BIGSERIAL PRIMARY KEY,
    job_code TEXT NOT NULL UNIQUE,
    job_name TEXT NOT NULL,
    job_type TEXT NOT NULL,
    cron_expression TEXT,
    interval_seconds INT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    run_timeout_seconds INT,
    max_concurrency INT,
    job_config_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ops.scheduled_job IS
    'Generic registry for ingestion, feature refresh, model training, backtest, and live scoring jobs.';

CREATE TABLE IF NOT EXISTS ops.job_run (
    job_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheduled_job_id BIGINT
        REFERENCES ops.scheduled_job(scheduled_job_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    job_code TEXT NOT NULL,
    run_status TEXT NOT NULL DEFAULT 'queued',
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    triggered_by TEXT,
    run_config_json JSONB,
    result_json JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ops.job_run IS
    'Execution history for scheduled or ad hoc operational jobs.';

COMMIT;