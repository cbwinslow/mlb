BEGIN;

CREATE OR REPLACE FUNCTION util.register_generic_payload_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_natural_key TEXT,
    p_payload_text TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_payload_hash BYTEA;
BEGIN
    v_payload_hash := util.sha256_text(p_payload_text);

    PERFORM util.register_payload_hash(
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        p_natural_key,
        v_payload_hash
    );
END;
$$;

CREATE OR REPLACE FUNCTION util.normalize_lahman_player_id(
    p_player_id TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(lower(trim(p_player_id)), '');
$$;

CREATE OR REPLACE FUNCTION util.normalize_web_natural_key(
    p_source_code TEXT,
    p_entity_key TEXT,
    p_season INT,
    p_page_type TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT concat_ws(
        ':',
        lower(trim(COALESCE(p_source_code, 'unknown'))),
        lower(trim(COALESCE(p_page_type, 'unknown'))),
        lower(trim(COALESCE(p_entity_key, 'unknown'))),
        COALESCE(p_season::TEXT, 'na')
    );
$$;

CREATE OR REPLACE FUNCTION util.validate_lahman_year_id(
    p_year_id INT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_year_id IS NOT NULL AND p_year_id >= 1871 AND p_year_id <= 2100;
$$;

COMMIT;