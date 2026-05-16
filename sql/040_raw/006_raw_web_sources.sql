BEGIN;

CREATE TABLE IF NOT EXISTS raw_fangraphs.request (
    raw_fangraphs_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

CREATE TABLE IF NOT EXISTS raw_fangraphs.payload (
    raw_fangraphs_payload_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID NOT NULL
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    leaderboard_name TEXT,
    stat_group TEXT,
    season INT,
    split_code TEXT,
    page_number INT,
    payload_json JSONB,
    payload_html TEXT,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_fangraphs.payload IS
    'Raw FanGraphs leaderboard or split payloads, usually driven by pybaseball-style parameterization.';

CREATE TABLE IF NOT EXISTS raw_bref.request (
    raw_bref_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

CREATE TABLE IF NOT EXISTS raw_bref.page (
    raw_bref_page_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID NOT NULL
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    page_type TEXT NOT NULL,
    entity_key TEXT,
    season INT,
    table_id TEXT,
    payload_html TEXT,
    payload_json JSONB,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_bref.page IS
    'Raw Baseball Reference page captures; useful because page/table structures can vary by entity type.';

CREATE TABLE IF NOT EXISTS raw_espn.request (
    raw_espn_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

CREATE TABLE IF NOT EXISTS raw_espn.page (
    raw_espn_page_id BIGSERIAL PRIMARY KEY,
    raw_espn_request_id UUID NOT NULL
        REFERENCES raw_espn.request(raw_espn_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    page_type TEXT NOT NULL,
    entity_key TEXT,
    season INT,
    payload_html TEXT,
    payload_json JSONB,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_espn.page IS
    'Raw ESPN page/API captures for standings, schedules, injuries, and matchup context when needed.';

CREATE TABLE IF NOT EXISTS raw_odds.provider_request (
    raw_odds_provider_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    provider_code TEXT NOT NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

CREATE TABLE IF NOT EXISTS raw_odds.provider_payload (
    raw_odds_provider_payload_id BIGSERIAL PRIMARY KEY,
    raw_odds_provider_request_id UUID NOT NULL
        REFERENCES raw_odds.provider_request(raw_odds_provider_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    provider_code TEXT NOT NULL,
    endpoint_code TEXT NOT NULL,
    sport_key TEXT,
    event_key TEXT,
    market_key TEXT,
    bookmaker_key TEXT,
    payload_json JSONB NOT NULL,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_odds.provider_payload IS
    'Raw odds-provider payloads; keep provider-specific structures intact before conformance.';

COMMIT;