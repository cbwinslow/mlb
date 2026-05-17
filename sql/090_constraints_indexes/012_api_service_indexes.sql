BEGIN;

CREATE INDEX IF NOT EXISTS idx_api_client_application_workspace
    ON api.client_application (workspace_id, application_status);

CREATE INDEX IF NOT EXISTS idx_api_workspace_plan_workspace
    ON api.workspace_plan (workspace_id, effective_from DESC);

CREATE INDEX IF NOT EXISTS idx_api_api_key_policy_api_key
    ON api.api_key_policy (api_key_id, effective_from DESC);

CREATE INDEX IF NOT EXISTS idx_api_request_idempotency_lookup
    ON api.request_idempotency (workspace_id, idempotency_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_request_log_workspace_ts
    ON api.request_log (workspace_id, request_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_api_request_log_api_key_ts
    ON api.request_log (api_key_id, request_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_api_request_log_route_ts
    ON api.request_log (route_pattern, request_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_api_request_log_request_id
    ON api.request_log (request_id)
    WHERE request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_api_usage_rollup_hourly_workspace_hour
    ON api.usage_rollup_hourly (workspace_id, usage_hour DESC);

CREATE INDEX IF NOT EXISTS idx_api_webhook_endpoint_workspace
    ON api.webhook_endpoint (workspace_id, endpoint_status);

CREATE INDEX IF NOT EXISTS idx_api_webhook_delivery_status_attempt
    ON api.webhook_delivery (delivery_status, next_attempt_at, created_at);

COMMIT;