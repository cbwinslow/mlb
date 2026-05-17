BEGIN;

CREATE OR REPLACE FUNCTION util.build_file_manifest_path(
    p_source_code TEXT,
    p_season INT,
    p_file_kind TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT lower(p_source_code) || '/' || p_season::TEXT || '/' || lower(replace(p_file_kind, ' ', '_'))
$$;

CREATE OR REPLACE FUNCTION util.next_statcast_chunk_start(
    p_last_end_date DATE,
    p_chunk_days INT DEFAULT 3
)
RETURNS DATE
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_last_end_date + INTERVAL '1 day'
$$;

CREATE OR REPLACE FUNCTION util.next_statcast_chunk_end(
    p_start_date DATE,
    p_chunk_days INT DEFAULT 3
)
RETURNS DATE
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT (p_start_date + ((p_chunk_days - 1) * INTERVAL '1 day'))::DATE
$$;

CREATE OR REPLACE FUNCTION util.mlbapi_live_poll_mode(
    p_has_diff_patch BOOLEAN,
    p_has_timestamps BOOLEAN
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_has_diff_patch THEN 'diff_patch'
        WHEN p_has_timestamps THEN 'timestamps'
        ELSE 'full_live_feed'
    END
$$;

CREATE OR REPLACE FUNCTION util.default_live_poll_interval_seconds(
    p_detailed_state TEXT
)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_detailed_state IN ('In Progress', 'Manager Challenge', 'Review') THEN 10
        WHEN p_detailed_state IN ('Warmup', 'Pre-Game') THEN 30
        ELSE 20
    END
$$;

CREATE OR REPLACE FUNCTION util.upsert_file_acquisition_manifest(
    p_source_loader_spec_id BIGINT,
    p_season INT,
    p_remote_uri TEXT,
    p_file_kind TEXT,
    p_compression_type TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_file_acquisition_manifest_id BIGINT;
BEGIN
    INSERT INTO ops.file_acquisition_manifest (
        source_loader_spec_id,
        season,
        remote_uri,
        local_relative_path,
        file_kind,
        compression_type
    )
    VALUES (
        p_source_loader_spec_id,
        p_season,
        p_remote_uri,
        util.build_file_manifest_path(
            (SELECT ss.source_code
             FROM ops.source_loader_spec sls
             JOIN meta.source_system ss
               ON ss.source_system_id = sls.source_system_id
             WHERE sls.source_loader_spec_id = p_source_loader_spec_id),
            p_season,
            p_file_kind
        ),
        p_file_kind,
        p_compression_type
    )
    ON CONFLICT (source_loader_spec_id, remote_uri)
    DO UPDATE
    SET updated_at = NOW()
    RETURNING file_acquisition_manifest_id INTO v_file_acquisition_manifest_id;

    RETURN v_file_acquisition_manifest_id;
END;
$$;

COMMIT;