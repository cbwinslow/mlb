BEGIN;

CREATE OR REPLACE FUNCTION util.register_statcast_row_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_game_pk BIGINT,
    p_at_bat_number INT,
    p_pitch_number INT,
    p_row_payload TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_natural_key TEXT;
    v_payload_hash BYTEA;
BEGIN
    v_natural_key := concat_ws(
        ':',
        p_game_pk::TEXT,
        p_at_bat_number::TEXT,
        p_pitch_number::TEXT
    );

    v_payload_hash := util.sha256_text(p_row_payload);

    PERFORM util.register_payload_hash(
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        v_natural_key,
        v_payload_hash
    );
END;
$$;

CREATE OR REPLACE FUNCTION util.register_mlbapi_payload_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_natural_key TEXT,
    p_payload_json JSONB
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_payload_hash BYTEA;
BEGIN
    v_payload_hash := digest(COALESCE(p_payload_json::TEXT, ''), 'sha256');

    PERFORM util.register_payload_hash(
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        p_natural_key,
        v_payload_hash
    );
END;
$$;

CREATE OR REPLACE FUNCTION util.validate_statcast_pitch_business_key(
    p_game_pk BIGINT,
    p_at_bat_number INT,
    p_pitch_number INT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        p_game_pk IS NOT NULL
        AND p_at_bat_number IS NOT NULL
        AND p_pitch_number IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION util.validate_mlbapi_request_method(
    p_request_method TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT upper(trim(p_request_method)) IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE');
$$;

COMMIT;