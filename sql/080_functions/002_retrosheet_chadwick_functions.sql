BEGIN;

CREATE OR REPLACE FUNCTION util.is_valid_retrosheet_record_type(p_record_type TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_record_type IN (
        'id',
        'version',
        'info',
        'start',
        'sub',
        'play',
        'com',
        'data',
        'badj',
        'padj',
        'ladj',
        'radj',
        'presadj'
    );
$$;

CREATE OR REPLACE FUNCTION util.normalize_retrosheet_record_type(p_record_type TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT lower(trim(p_record_type));
$$;

CREATE OR REPLACE FUNCTION util.register_retrosheet_record_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_game_id TEXT,
    p_record_sequence INT,
    p_raw_line TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_natural_key TEXT;
    v_payload_hash BYTEA;
BEGIN
    v_natural_key := concat_ws(':', p_game_id, p_record_sequence::TEXT);
    v_payload_hash := util.sha256_text(p_raw_line);

    PERFORM util.register_payload_hash(
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        v_natural_key,
        v_payload_hash
    );
END;
$$;

CREATE OR REPLACE FUNCTION util.validate_retrosheet_record_sequences(
    p_event_file_id UUID
)
RETURNS TABLE(
    game_id TEXT,
    first_sequence INT,
    last_sequence INT,
    record_count BIGINT
)
LANGUAGE sql
AS $$
    SELECT
        r.game_id,
        MIN(r.record_sequence) AS first_sequence,
        MAX(r.record_sequence) AS last_sequence,
        COUNT(*) AS record_count
    FROM raw_retrosheet.record r
    WHERE r.event_file_id = p_event_file_id
    GROUP BY r.game_id;
$$;

COMMIT;