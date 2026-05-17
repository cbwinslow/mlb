BEGIN;

CREATE TABLE IF NOT EXISTS api.client_application (
    client_application_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    application_code TEXT NOT NULL UNIQUE,
    application_name TEXT NOT NULL,
    application_type TEXT NOT NULL DEFAULT 'internal',
    application_status TEXT NOT NULL DEFAULT 'active',
    owner_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api.plan_definition (
    plan_definition_id BIGSERIAL PRIMARY KEY,
    plan_code TEXT NOT NULL UNIQUE,
    plan_name TEXT NOT NULL,
    monthly_request_limit BIGINT,
    burst_request_limit INT,
    max_concurrent_jobs INT,
    max_saved_models INT,
    max_workspaces INT,
    can_use_live_data BOOLEAN NOT NULL DEFAULT FALSE,
    can_use_automation BOOLEAN NOT NULL DEFAULT FALSE,
    can_use_webhooks BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api.workspace_plan (
    workspace_plan_id BIGSERIAL PRIMARY KEY,
    workspace_id UUID NOT NULL
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    plan_definition_id BIGINT NOT NULL
        REFERENCES api.plan_definition(plan_definition_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to TIMESTAMPTZ,
    billing_status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api.rate_limit_policy (
    rate_limit_policy_id BIGSERIAL PRIMARY KEY,
    policy_code TEXT NOT NULL UNIQUE,
    policy_name TEXT NOT NULL,
    scope_type TEXT NOT NULL,
    window_seconds INT NOT NULL,
    request_limit BIGINT NOT NULL,
    burst_limit INT,
    applies_to_route_pattern TEXT,
    active_flag BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api.api_key_policy (
    api_key_policy_id BIGSERIAL PRIMARY KEY,
    api_key_id UUID NOT NULL
        REFERENCES auth.api_key(api_key_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    rate_limit_policy_id BIGINT NOT NULL
        REFERENCES api.rate_limit_policy(rate_limit_policy_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT api_api_key_policy_unique
        UNIQUE (api_key_id, rate_limit_policy_id, effective_from)
);

CREATE TABLE IF NOT EXISTS api.request_idempotency (
    request_idempotency_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    api_key_id UUID
        REFERENCES auth.api_key(api_key_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    idempotency_key TEXT NOT NULL,
    request_method TEXT NOT NULL,
    request_path TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    response_status INT,
    response_body_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    CONSTRAINT api_request_idempotency_unique
        UNIQUE (workspace_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS api.request_log (
    request_log_id BIGSERIAL PRIMARY KEY,
    request_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    api_key_id UUID
        REFERENCES auth.api_key(api_key_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    client_application_id UUID
        REFERENCES api.client_application(client_application_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    app_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_method TEXT NOT NULL,
    request_path TEXT NOT NULL,
    route_pattern TEXT,
    response_status INT,
    latency_ms INT,
    request_bytes BIGINT,
    response_bytes BIGINT,
    source_ip INET,
    user_agent TEXT,
    request_id TEXT,
    trace_id TEXT,
    idempotency_key TEXT,
    created_job_queue_id UUID
        REFERENCES ops.job_queue(job_queue_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_prediction_run_id UUID
        REFERENCES ml.prediction_run(prediction_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS api.usage_rollup_hourly (
    usage_rollup_hourly_id BIGSERIAL PRIMARY KEY,
    usage_hour TIMESTAMPTZ NOT NULL,
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    api_key_id UUID
        REFERENCES auth.api_key(api_key_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    route_pattern TEXT,
    request_count BIGINT NOT NULL DEFAULT 0,
    success_count BIGINT NOT NULL DEFAULT 0,
    error_count BIGINT NOT NULL DEFAULT 0,
    total_latency_ms BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT api_usage_rollup_hourly_unique
        UNIQUE (usage_hour, workspace_id, api_key_id, route_pattern)
);

CREATE TABLE IF NOT EXISTS api.webhook_endpoint (
    webhook_endpoint_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    endpoint_code TEXT NOT NULL UNIQUE,
    endpoint_url TEXT NOT NULL,
    signing_secret_hash TEXT,
    endpoint_status TEXT NOT NULL DEFAULT 'active',
    subscribed_event_types TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    last_delivery_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api.webhook_delivery (
    webhook_delivery_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_endpoint_id UUID NOT NULL
        REFERENCES api.webhook_endpoint(webhook_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    event_key TEXT NOT NULL,
    delivery_status TEXT NOT NULL DEFAULT 'pending',
    attempt_count INT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ,
    last_attempt_at TIMESTAMPTZ,
    response_status INT,
    response_body_json JSONB,
    payload_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT api_webhook_delivery_unique
        UNIQUE (webhook_endpoint_id, event_type, event_key)
);

COMMIT;