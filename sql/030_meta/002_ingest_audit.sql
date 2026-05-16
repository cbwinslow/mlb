BEGIN;

CREATE TABLE IF NOT EXISTS meta.ingest_run (
    ingest_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system_id SMALLINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    run_status TEXT NOT NULL DEFAULT 'running',
    triggered_by TEXT NOT NULL DEFAULT 'system',
    request_params JSONB,
    request_url TEXT,
    window_start_date DATE,
    window_end_date DATE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    records_seen BIGINT NOT NULL DEFAULT 0,
    records_inserted BIGINT NOT NULL DEFAULT 0,
    records_updated BIGINT NOT NULL DEFAULT 0,
    records_unchanged BIGINT NOT NULL DEFAULT 0,
    records_rejected BIGINT NOT NULL DEFAULT 0,
    error_count BIGINT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ingest_run_status_chk
        CHECK (run_status IN ('running', 'succeeded', 'failed', 'partial', 'cancelled')),
    CONSTRAINT ingest_run_date_window_chk
        CHECK (
            window_start_date IS NULL
            OR window_end_date IS NULL
            OR window_start_date <= window_end_date
        ),
    CONSTRAINT ingest_run_finished_chk
        CHECK (
            finished_at IS NULL
            OR finished_at >= started_at
        )
);

COMMENT ON TABLE meta.ingest_run IS
    'One row per extraction/load execution against a source or endpoint.';

CREATE INDEX IF NOT EXISTS ingest_run_source_started_at_idx
    ON meta.ingest_run (source_system_id, started_at DESC);

CREATE INDEX IF NOT EXISTS ingest_run_endpoint_started_at_idx
    ON meta.ingest_run (source_endpoint_id, started_at DESC);

CREATE TABLE IF NOT EXISTS meta.source_file (
    source_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system_id SMALLINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    file_name TEXT NOT NULL,
    file_path TEXT,
    file_url TEXT,
    file_extension TEXT,
    file_category TEXT,
    season INT,
    content_type TEXT,
    byte_size BIGINT,
    checksum_sha256 TEXT,
    file_created_at TIMESTAMPTZ,
    file_modified_at TIMESTAMPTZ,
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    loaded_at TIMESTAMPTZ,
    CONSTRAINT source_file_unique
        UNIQUE (source_system_id, file_name, checksum_sha256)
);

COMMENT ON TABLE meta.source_file IS
    'Tracks downloaded files, archives, extracts, and generated intermediate source artifacts.';

CREATE INDEX IF NOT EXISTS source_file_source_system_season_idx
    ON meta.source_file (source_system_id, season);

CREATE INDEX IF NOT EXISTS source_file_ingest_run_idx
    ON meta.source_file (ingest_run_id);

CREATE TABLE IF NOT EXISTS meta.raw_payload_registry (
    raw_payload_registry_id BIGSERIAL PRIMARY KEY,
    source_system_id SMALLINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    natural_key TEXT,
    payload_hash BYTEA NOT NULL,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    seen_count BIGINT NOT NULL DEFAULT 1,
    CONSTRAINT raw_payload_registry_unique
        UNIQUE (source_system_id, source_endpoint_id, payload_hash)
);

COMMENT ON TABLE meta.raw_payload_registry IS
    'Hash registry used to detect duplicate raw payloads or repeated source records across ingest runs.';

CREATE INDEX IF NOT EXISTS raw_payload_registry_source_endpoint_idx
    ON meta.raw_payload_registry (source_system_id, source_endpoint_id);

CREATE INDEX IF NOT EXISTS raw_payload_registry_natural_key_idx
    ON meta.raw_payload_registry (natural_key);

CREATE TABLE IF NOT EXISTS meta.ingest_error (
    ingest_error_id BIGSERIAL PRIMARY KEY,
    ingest_run_id UUID NOT NULL
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_id SMALLINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    error_stage TEXT NOT NULL,
    error_code TEXT,
    natural_key TEXT,
    row_number BIGINT,
    error_message TEXT NOT NULL,
    error_detail JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE meta.ingest_error IS
    'Structured ingest errors for extraction, parsing, staging, and load failures.';

CREATE INDEX IF NOT EXISTS ingest_error_run_stage_idx
    ON meta.ingest_error (ingest_run_id, error_stage, created_at DESC);

COMMIT;