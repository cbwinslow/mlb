BEGIN;

CREATE OR REPLACE FUNCTION util.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION util.sha256_text(p_input TEXT)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT digest(COALESCE(p_input, ''), 'sha256');
$$;

CREATE OR REPLACE FUNCTION util.register_payload_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_natural_key TEXT,
    p_payload_hash BYTEA
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO meta.raw_payload_registry (
        source_system_id,
        source_endpoint_id,
        ingest_run_id,
        natural_key,
        payload_hash
    )
    VALUES (
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        p_natural_key,
        p_payload_hash
    )
    ON CONFLICT (source_system_id, source_endpoint_id, payload_hash)
    DO UPDATE
    SET
        last_seen_at = NOW(),
        seen_count = meta.raw_payload_registry.seen_count + 1,
        ingest_run_id = EXCLUDED.ingest_run_id,
        natural_key = COALESCE(EXCLUDED.natural_key, meta.raw_payload_registry.natural_key);
END;
$$;

CREATE OR REPLACE FUNCTION util.start_ingest_run(
    p_source_code TEXT,
    p_endpoint_code TEXT DEFAULT NULL,
    p_triggered_by TEXT DEFAULT 'system',
    p_request_params JSONB DEFAULT NULL,
    p_request_url TEXT DEFAULT NULL,
    p_window_start_date DATE DEFAULT NULL,
    p_window_end_date DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_system_id SMALLINT;
    v_source_endpoint_id BIGINT;
    v_ingest_run_id UUID;
BEGIN
    SELECT ss.source_system_id
    INTO v_source_system_id
    FROM meta.source_system ss
    WHERE ss.source_code = lower(p_source_code);

    IF v_source_system_id IS NULL THEN
        RAISE EXCEPTION 'Unknown source_code: %', p_source_code;
    END IF;

    IF p_endpoint_code IS NOT NULL THEN
        SELECT se.source_endpoint_id
        INTO v_source_endpoint_id
        FROM meta.source_endpoint se
        WHERE se.source_system_id = v_source_system_id
          AND se.endpoint_code = lower(p_endpoint_code);

        IF v_source_endpoint_id IS NULL THEN
            RAISE EXCEPTION 'Unknown endpoint_code % for source_code %', p_endpoint_code, p_source_code;
        END IF;
    END IF;

    INSERT INTO meta.ingest_run (
        source_system_id,
        source_endpoint_id,
        run_status,
        triggered_by,
        request_params,
        request_url,
        window_start_date,
        window_end_date
    )
    VALUES (
        v_source_system_id,
        v_source_endpoint_id,
        'running',
        p_triggered_by,
        p_request_params,
        p_request_url,
        p_window_start_date,
        p_window_end_date
    )
    RETURNING ingest_run_id INTO v_ingest_run_id;

    RETURN v_ingest_run_id;
END;
$$;

CREATE OR REPLACE PROCEDURE util.finish_ingest_run(
    p_ingest_run_id UUID,
    p_run_status TEXT,
    p_records_seen BIGINT DEFAULT NULL,
    p_records_inserted BIGINT DEFAULT NULL,
    p_records_updated BIGINT DEFAULT NULL,
    p_records_unchanged BIGINT DEFAULT NULL,
    p_records_rejected BIGINT DEFAULT NULL,
    p_error_count BIGINT DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE meta.ingest_run
    SET
        run_status = p_run_status,
        finished_at = NOW(),
        records_seen = COALESCE(p_records_seen, records_seen),
        records_inserted = COALESCE(p_records_inserted, records_inserted),
        records_updated = COALESCE(p_records_updated, records_updated),
        records_unchanged = COALESCE(p_records_unchanged, records_unchanged),
        records_rejected = COALESCE(p_records_rejected, records_rejected),
        error_count = COALESCE(p_error_count, error_count),
        error_message = COALESCE(p_error_message, error_message)
    WHERE ingest_run_id = p_ingest_run_id;
END;
$$;

DROP TRIGGER IF EXISTS trg_source_system_updated_at ON meta.source_system;
CREATE TRIGGER trg_source_system_updated_at
BEFORE UPDATE ON meta.source_system
FOR EACH ROW
EXECUTE FUNCTION util.touch_updated_at();

DROP TRIGGER IF EXISTS trg_source_endpoint_updated_at ON meta.source_endpoint;
CREATE TRIGGER trg_source_endpoint_updated_at
BEFORE UPDATE ON meta.source_endpoint
FOR EACH ROW
EXECUTE FUNCTION util.touch_updated_at();

COMMIT;