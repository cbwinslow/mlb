BEGIN;

CREATE TABLE IF NOT EXISTS ops.source_loader_spec (
    source_loader_spec_id BIGSERIAL PRIMARY KEY,
    source_system_id BIGINT NOT NULL
        REFERENCES meta.source_system(source_system_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    loader_code TEXT NOT NULL UNIQUE,
    loader_name TEXT NOT NULL,
    loader_mode TEXT NOT NULL,
    transport_type TEXT NOT NULL,
    parser_type TEXT NOT NULL,
    target_raw_schema TEXT NOT NULL,
    target_object_family TEXT NOT NULL,
    supports_incremental BOOLEAN NOT NULL DEFAULT FALSE,
    supports_live_polling BOOLEAN NOT NULL DEFAULT FALSE,
    supports_backfill BOOLEAN NOT NULL DEFAULT TRUE,
    requires_file_download BOOLEAN NOT NULL DEFAULT FALSE,
    requires_cli_tool BOOLEAN NOT NULL DEFAULT FALSE,
    cli_tool_name TEXT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    default_config_json JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.source_endpoint_profile (
    source_endpoint_profile_id BIGSERIAL PRIMARY KEY,
    source_loader_spec_id BIGINT NOT NULL
        REFERENCES ops.source_loader_spec(source_loader_spec_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    profile_code TEXT NOT NULL UNIQUE,
    profile_name TEXT NOT NULL,
    endpoint_path_template TEXT,
    http_method TEXT,
    parameter_schema_json JSONB NOT NULL DEFAULT '{}'::JSONB,
    default_parameters_json JSONB NOT NULL DEFAULT '{}'::JSONB,
    supports_diff_patch BOOLEAN NOT NULL DEFAULT FALSE,
    supports_timestamps BOOLEAN NOT NULL DEFAULT FALSE,
    polling_interval_seconds INT,
    timeout_seconds INT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.source_chunking_policy (
    source_chunking_policy_id BIGSERIAL PRIMARY KEY,
    source_loader_spec_id BIGINT NOT NULL
        REFERENCES ops.source_loader_spec(source_loader_spec_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    policy_code TEXT NOT NULL UNIQUE,
    chunk_dimension TEXT NOT NULL,
    chunk_size INT,
    chunk_interval TEXT,
    max_rows_per_pull INT,
    overlap_seconds INT NOT NULL DEFAULT 0,
    backfill_order TEXT NOT NULL DEFAULT 'ascending',
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.file_acquisition_manifest (
    file_acquisition_manifest_id BIGSERIAL PRIMARY KEY,
    source_loader_spec_id BIGINT NOT NULL
        REFERENCES ops.source_loader_spec(source_loader_spec_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INT,
    remote_uri TEXT NOT NULL,
    local_relative_path TEXT,
    file_kind TEXT NOT NULL,
    compression_type TEXT,
    checksum_sha256 TEXT,
    file_status TEXT NOT NULL DEFAULT 'pending',
    downloaded_at TIMESTAMPTZ,
    extracted_at TIMESTAMPTZ,
    loaded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ops_file_acquisition_manifest_unique
        UNIQUE (source_loader_spec_id, remote_uri)
);

CREATE TABLE IF NOT EXISTS ops.loader_run_binding (
    loader_run_binding_id BIGSERIAL PRIMARY KEY,
    ingest_run_id BIGINT NOT NULL
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_loader_spec_id BIGINT NOT NULL
        REFERENCES ops.source_loader_spec(source_loader_spec_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    source_endpoint_profile_id BIGINT
        REFERENCES ops.source_endpoint_profile(source_endpoint_profile_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_chunking_policy_id BIGINT
        REFERENCES ops.source_chunking_policy(source_chunking_policy_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    file_acquisition_manifest_id BIGINT
        REFERENCES ops.file_acquisition_manifest(file_acquisition_manifest_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    binding_status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.live_endpoint_strategy (
    live_endpoint_strategy_id BIGSERIAL PRIMARY KEY,
    source_loader_spec_id BIGINT NOT NULL
        REFERENCES ops.source_loader_spec(source_loader_spec_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    strategy_code TEXT NOT NULL UNIQUE,
    primary_endpoint_profile_id BIGINT
        REFERENCES ops.source_endpoint_profile(source_endpoint_profile_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    fallback_endpoint_profile_id BIGINT
        REFERENCES ops.source_endpoint_profile(source_endpoint_profile_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    use_timestamps_endpoint BOOLEAN NOT NULL DEFAULT FALSE,
    use_diff_patch_endpoint BOOLEAN NOT NULL DEFAULT FALSE,
    stop_when_live_poll_rule_matches BOOLEAN NOT NULL DEFAULT TRUE,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ops.source_loader_spec (
    source_system_id,
    loader_code,
    loader_name,
    loader_mode,
    transport_type,
    parser_type,
    target_raw_schema,
    target_object_family,
    supports_incremental,
    supports_live_polling,
    supports_backfill,
    requires_file_download,
    requires_cli_tool,
    cli_tool_name,
    default_config_json
)
SELECT
    ss.source_system_id,
    'retrosheet_event_zip',
    'Retrosheet Event ZIP Loader',
    'batch_file',
    'http_download',
    'eventfile',
    'raw_retrosheet',
    'event_files',
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    FALSE,
    NULL,
    jsonb_build_object('download_format', 'zip')
FROM meta.source_system ss
WHERE ss.source_code = 'retrosheet'
ON CONFLICT (loader_code) DO NOTHING;

INSERT INTO ops.source_loader_spec (
    source_system_id,
    loader_code,
    loader_name,
    loader_mode,
    transport_type,
    parser_type,
    target_raw_schema,
    target_object_family,
    supports_incremental,
    supports_live_polling,
    supports_backfill,
    requires_file_download,
    requires_cli_tool,
    cli_tool_name,
    default_config_json
)
SELECT
    ss.source_system_id,
    'chadwick_retrosheet_extract',
    'Chadwick Retrosheet Extract Loader',
    'cli_extract',
    'local_file',
    'csv_extract',
    'raw_chadwick',
    'cwevent_cwgame_cwsub',
    FALSE,
    FALSE,
    TRUE,
    FALSE,
    TRUE,
    'chadwick',
    jsonb_build_object('tools', jsonb_build_array('cwevent', 'cwgame', 'cwsub'))
FROM meta.source_system ss
WHERE ss.source_code = 'chadwick'
ON CONFLICT (loader_code) DO NOTHING;

INSERT INTO ops.source_loader_spec (
    source_system_id,
    loader_code,
    loader_name,
    loader_mode,
    transport_type,
    parser_type,
    target_raw_schema,
    target_object_family,
    supports_incremental,
    supports_live_polling,
    supports_backfill,
    requires_file_download,
    requires_cli_tool,
    cli_tool_name,
    default_config_json
)
SELECT
    ss.source_system_id,
    'mlbapi_schedule_live',
    'MLB StatsAPI Schedule and Live Feed Loader',
    'api_pull',
    'http_json',
    'json_expand',
    'raw_mlbapi',
    'schedule_and_live',
    TRUE,
    TRUE,
    TRUE,
    FALSE,
    FALSE,
    NULL,
    jsonb_build_object('supports_diff_patch', true, 'supports_timestamps', true)
FROM meta.source_system ss
WHERE ss.source_code = 'mlb_statsapi'
ON CONFLICT (loader_code) DO NOTHING;

INSERT INTO ops.source_loader_spec (
    source_system_id,
    loader_code,
    loader_name,
    loader_mode,
    transport_type,
    parser_type,
    target_raw_schema,
    target_object_family,
    supports_incremental,
    supports_live_polling,
    supports_backfill,
    requires_file_download,
    requires_cli_tool,
    cli_tool_name,
    default_config_json
)
SELECT
    ss.source_system_id,
    'statcast_search_csv',
    'Baseball Savant Statcast Search Loader',
    'api_pull',
    'http_csv',
    'csv_ingest',
    'raw_statcast',
    'pitch_search',
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    NULL,
    jsonb_build_object('chunk_dimension', 'date_range')
FROM meta.source_system ss
WHERE ss.source_code = 'statcast'
ON CONFLICT (loader_code) DO NOTHING;

COMMIT;