BEGIN;

CREATE TABLE IF NOT EXISTS ml.feature_snapshot (
    feature_snapshot_id BIGSERIAL PRIMARY KEY,
    feature_set_id BIGINT NOT NULL
        REFERENCES ml.feature_set(feature_set_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    snapshot_code TEXT NOT NULL,
    snapshot_timestamp TIMESTAMPTZ NOT NULL,
    season INT,
    entity_grain TEXT NOT NULL,
    entity_key TEXT NOT NULL,
    game_id BIGINT
        REFERENCES core.game(game_id)
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
    plate_appearance_id BIGINT
        REFERENCES core.plate_appearance(plate_appearance_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    pitch_id BIGINT
        REFERENCES core.pitch(pitch_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    feature_payload JSONB NOT NULL,
    source_window_start TIMESTAMPTZ,
    source_window_end TIMESTAMPTZ,
    is_live_snapshot BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ml_feature_snapshot_unique
        UNIQUE (feature_set_id, snapshot_code, entity_key)
);

COMMENT ON TABLE ml.feature_snapshot IS
    'Point-in-time feature vectors stored as JSONB for maximum flexibility across grains and model families.';

CREATE TABLE IF NOT EXISTS ml.dataset_definition (
    dataset_definition_id BIGSERIAL PRIMARY KEY,
    problem_definition_id BIGINT NOT NULL
        REFERENCES ml.problem_definition(problem_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    feature_set_id BIGINT NOT NULL
        REFERENCES ml.feature_set(feature_set_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    dataset_code TEXT NOT NULL UNIQUE,
    dataset_name TEXT NOT NULL,
    entity_grain TEXT NOT NULL,
    target_sql TEXT,
    filter_sql TEXT,
    point_in_time_safe_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.dataset_definition IS
    'Reusable dataset recipe for training, validation, backtesting, and live scoring.';

CREATE TABLE IF NOT EXISTS ml.dataset_split (
    dataset_split_id BIGSERIAL PRIMARY KEY,
    dataset_definition_id BIGINT NOT NULL
        REFERENCES ml.dataset_definition(dataset_definition_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    split_code TEXT NOT NULL,
    split_type TEXT NOT NULL,
    split_start_date DATE,
    split_end_date DATE,
    fold_number INT,
    holdout_flag BOOLEAN NOT NULL DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.dataset_split IS
    'Train/validation/test/backtest folds, including walk-forward and rolling-window splits.';

CREATE TABLE IF NOT EXISTS ml.training_run (
    training_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_definition_id BIGINT NOT NULL
        REFERENCES ml.model_definition(model_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    dataset_definition_id BIGINT NOT NULL
        REFERENCES ml.dataset_definition(dataset_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    training_status TEXT NOT NULL DEFAULT 'queued',
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    train_rows BIGINT,
    validation_rows BIGINT,
    test_rows BIGINT,
    random_seed BIGINT,
    run_config_json JSONB,
    environment_json JSONB,
    metrics_json JSONB,
    artifact_uri TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ml.training_run IS
    'One execution of training for a specific model version and dataset recipe.';

COMMIT;