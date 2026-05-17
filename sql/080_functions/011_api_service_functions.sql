BEGIN;

CREATE OR REPLACE FUNCTION util.api_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION util.register_request_idempotency(
    p_workspace_id UUID,
    p_api_key_id UUID,
    p_idempotency_key TEXT,
    p_request_method TEXT,
    p_request_path TEXT,
    p_request_hash TEXT,
    p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_request_idempotency_id UUID;
BEGIN
    INSERT INTO api.request_idempotency (
        workspace_id,
        api_key_id,
        idempotency_key,
        request_method,
        request_path,
        request_hash,
        expires_at
    )
    VALUES (
        p_workspace_id,
        p_api_key_id,
        p_idempotency_key,
        p_request_method,
        p_request_path,
        p_request_hash,
        p_expires_at
    )
    ON CONFLICT (workspace_id, idempotency_key)
    DO UPDATE
    SET request_hash = api.request_idempotency.request_hash
    RETURNING request_idempotency_id INTO v_request_idempotency_id;

    RETURN v_request_idempotency_id;
END;
$$;

CREATE OR REPLACE FUNCTION util.log_api_request(
    p_workspace_id UUID,
    p_api_key_id UUID,
    p_client_application_id UUID,
    p_app_user_id UUID,
    p_request_method TEXT,
    p_request_path TEXT,
    p_route_pattern TEXT,
    p_response_status INT,
    p_latency_ms INT,
    p_request_bytes BIGINT,
    p_response_bytes BIGINT,
    p_source_ip INET,
    p_user_agent TEXT,
    p_request_id TEXT,
    p_trace_id TEXT,
    p_idempotency_key TEXT,
    p_created_job_queue_id UUID DEFAULT NULL,
    p_created_prediction_run_id UUID DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_request_log_id BIGINT;
BEGIN
    INSERT INTO api.request_log (
        workspace_id,
        api_key_id,
        client_application_id,
        app_user_id,
        request_method,
        request_path,
        route_pattern,
        response_status,
        latency_ms,
        request_bytes,
        response_bytes,
        source_ip,
        user_agent,
        request_id,
        trace_id,
        idempotency_key,
        created_job_queue_id,
        created_prediction_run_id
    )
    VALUES (
        p_workspace_id,
        p_api_key_id,
        p_client_application_id,
        p_app_user_id,
        p_request_method,
        p_request_path,
        p_route_pattern,
        p_response_status,
        p_latency_ms,
        p_request_bytes,
        p_response_bytes,
        p_source_ip,
        p_user_agent,
        p_request_id,
        p_trace_id,
        p_idempotency_key,
        p_created_job_queue_id,
        p_created_prediction_run_id
    )
    RETURNING request_log_id INTO v_request_log_id;

    RETURN v_request_log_id;
END;
$$;

CREATE OR REPLACE FUNCTION util.rollup_api_usage_hourly(
    p_usage_hour TIMESTAMPTZ DEFAULT date_trunc('hour', NOW())
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO api.usage_rollup_hourly (
        usage_hour,
        workspace_id,
        api_key_id,
        route_pattern,
        request_count,
        success_count,
        error_count,
        total_latency_ms
    )
    SELECT
        date_trunc('hour', request_timestamp) AS usage_hour,
        workspace_id,
        api_key_id,
        route_pattern,
        COUNT(*) AS request_count,
        COUNT(*) FILTER (WHERE response_status BETWEEN 200 AND 299) AS success_count,
        COUNT(*) FILTER (WHERE response_status >= 400) AS error_count,
        COALESCE(SUM(latency_ms), 0) AS total_latency_ms
    FROM api.request_log
    WHERE request_timestamp >= p_usage_hour
      AND request_timestamp < p_usage_hour + INTERVAL '1 hour'
    GROUP BY 1, 2, 3, 4
    ON CONFLICT (usage_hour, workspace_id, api_key_id, route_pattern)
    DO UPDATE
    SET request_count = EXCLUDED.request_count,
        success_count = EXCLUDED.success_count,
        error_count = EXCLUDED.error_count,
        total_latency_ms = EXCLUDED.total_latency_ms;
END;
$$;

COMMIT;