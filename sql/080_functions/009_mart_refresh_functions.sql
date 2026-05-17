BEGIN;

CREATE TABLE IF NOT EXISTS ops.materialized_view_refresh_log (
    materialized_view_refresh_log_id BIGSERIAL PRIMARY KEY,
    view_schema TEXT NOT NULL,
    view_name TEXT NOT NULL,
    refresh_mode TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    refresh_status TEXT NOT NULL DEFAULT 'running',
    error_message TEXT
);

CREATE OR REPLACE FUNCTION util.refresh_materialized_view(
    p_view_schema TEXT,
    p_view_name TEXT,
    p_concurrently BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
    v_log_id BIGINT;
BEGIN
    INSERT INTO ops.materialized_view_refresh_log (
        view_schema,
        view_name,
        refresh_mode,
        refresh_status
    )
    VALUES (
        p_view_schema,
        p_view_name,
        CASE WHEN p_concurrently THEN 'concurrently' ELSE 'standard' END,
        'running'
    )
    RETURNING materialized_view_refresh_log_id INTO v_log_id;

    v_sql := CASE
        WHEN p_concurrently
        THEN format('REFRESH MATERIALIZED VIEW CONCURRENTLY %I.%I', p_view_schema, p_view_name)
        ELSE format('REFRESH MATERIALIZED VIEW %I.%I', p_view_schema, p_view_name)
    END;

    EXECUTE v_sql;

    UPDATE ops.materialized_view_refresh_log
    SET finished_at = NOW(),
        refresh_status = 'success'
    WHERE materialized_view_refresh_log_id = v_log_id;

EXCEPTION
    WHEN OTHERS THEN
        UPDATE ops.materialized_view_refresh_log
        SET finished_at = NOW(),
            refresh_status = 'failed',
            error_message = SQLERRM
        WHERE materialized_view_refresh_log_id = v_log_id;
        RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION util.refresh_workspace_marts(p_concurrently BOOLEAN DEFAULT TRUE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM util.refresh_materialized_view('mart', 'mv_workspace_model_summary', p_concurrently);
    PERFORM util.refresh_materialized_view('mart', 'mv_workspace_recent_predictions', p_concurrently);
    PERFORM util.refresh_materialized_view('mart', 'mv_workspace_backtest_summary', p_concurrently);
END;
$$;

COMMIT;