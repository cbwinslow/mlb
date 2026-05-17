BEGIN;

CREATE TABLE IF NOT EXISTS ops.job_type (
    job_type_id BIGSERIAL PRIMARY KEY,
    job_type_code TEXT NOT NULL UNIQUE,
    job_type_name TEXT NOT NULL,
    job_category TEXT NOT NULL,
    queue_name TEXT NOT NULL DEFAULT 'default',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.job_dependency (
    job_dependency_id BIGSERIAL PRIMARY KEY,
    parent_scheduled_job_id BIGINT NOT NULL
        REFERENCES ops.scheduled_job(scheduled_job_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    child_scheduled_job_id BIGINT NOT NULL
        REFERENCES ops.scheduled_job(scheduled_job_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    dependency_type TEXT NOT NULL DEFAULT 'success',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ops_job_dependency_unique
        UNIQUE (parent_scheduled_job_id, child_scheduled_job_id, dependency_type),
    CONSTRAINT ops_job_dependency_no_self
        CHECK (parent_scheduled_job_id <> child_scheduled_job_id)
);

CREATE TABLE IF NOT EXISTS ops.ingest_profile (
    ingest_profile_id BIGSERIAL PRIMARY KEY,
    source_system_id BIGINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    profile_code TEXT NOT NULL UNIQUE,
    profile_name TEXT NOT NULL,
    endpoint_scope TEXT,
    default_config_json JSONB NOT NULL DEFAULT '{}'::JSONB,
    max_retries INT NOT NULL DEFAULT 5,
    retry_backoff_seconds INT NOT NULL DEFAULT 60,
    retry_backoff_multiplier NUMERIC(10,4) NOT NULL DEFAULT 2.0,
    retry_jitter_seconds INT NOT NULL DEFAULT 15,
    timeout_seconds INT,
    batch_size INT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.job_queue (
    job_queue_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheduled_job_id BIGINT
        REFERENCES ops.scheduled_job(scheduled_job_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    job_type_id BIGINT NOT NULL
        REFERENCES ops.job_type(job_type_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_id BIGINT
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_profile_id BIGINT
        REFERENCES ops.ingest_profile(ingest_profile_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    queue_name TEXT NOT NULL DEFAULT 'default',
    priority SMALLINT NOT NULL DEFAULT 100,
    job_status TEXT NOT NULL DEFAULT 'pending',
    run_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    claimed_at TIMESTAMPTZ,
    claimed_by TEXT,
    claim_token UUID,
    lease_expires_at TIMESTAMPTZ,
    attempts INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 5,
    last_error TEXT,
    last_error_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    payload_json JSONB NOT NULL DEFAULT '{}'::JSONB,
    result_json JSONB,
    idempotency_key TEXT,
    parent_job_queue_id UUID
        REFERENCES ops.job_queue(job_queue_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.job_dead_letter (
    job_dead_letter_id BIGSERIAL PRIMARY KEY,
    job_queue_id UUID NOT NULL
        REFERENCES ops.job_queue(job_queue_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    dead_letter_reason TEXT NOT NULL,
    error_snapshot_json JSONB,
    moved_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.live_poll_rule (
    live_poll_rule_id BIGSERIAL PRIMARY KEY,
    source_system_id BIGINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    rule_code TEXT NOT NULL UNIQUE,
    abstract_game_state_in TEXT[],
    coded_game_state_in TEXT[],
    detailed_state_in TEXT[],
    stop_polling_when_matched BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ops.live_game_poller
    ADD COLUMN IF NOT EXISTS last_claimed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS claimed_by TEXT,
    ADD COLUMN IF NOT EXISTS claim_token UUID,
    ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS consecutive_no_change_polls INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_no_change_polls INT,
    ADD COLUMN IF NOT EXISTS poll_payload_json JSONB;

INSERT INTO ops.job_type (job_type_code, job_type_name, job_category, queue_name)
VALUES
    ('source_ingest', 'Source Ingest', 'ingestion', 'ingestion'),
    ('live_poll', 'Live Game Poll', 'ingestion', 'live'),
    ('mart_refresh', 'Mart Refresh', 'refresh', 'maintenance'),
    ('feature_build', 'Feature Build', 'modeling', 'modeling'),
    ('model_train', 'Model Train', 'modeling', 'modeling'),
    ('model_score', 'Model Score', 'modeling', 'modeling'),
    ('backtest_run', 'Backtest Run', 'modeling', 'modeling'),
    ('alert_eval', 'Alert Evaluation', 'alerting', 'alerts')
ON CONFLICT (job_type_code) DO NOTHING;

COMMIT;