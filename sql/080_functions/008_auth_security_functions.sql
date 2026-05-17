BEGIN;

CREATE OR REPLACE FUNCTION util.auth_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION util.current_workspace_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_workspace', true), '')::UUID
$$;

CREATE OR REPLACE FUNCTION util.current_app_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_app_user', true), '')::UUID
$$;

CREATE OR REPLACE FUNCTION util.current_is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(NULLIF(current_setting('app.current_is_platform_admin', true), '')::BOOLEAN, FALSE)
$$;

CREATE OR REPLACE FUNCTION util.source_is_enabled_for_ingest(p_source_system_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT
            enabled_for_ingest
            AND NOT legal_hold
            AND NOT quality_hold
            AND (effective_to IS NULL OR effective_to > NOW())
        FROM auth.data_source_control
        WHERE source_system_id = p_source_system_id
    ), TRUE)
$$;

CREATE OR REPLACE FUNCTION util.source_is_enabled_for_serving(p_source_system_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT
            enabled_for_serving
            AND NOT legal_hold
            AND NOT quality_hold
            AND (effective_to IS NULL OR effective_to > NOW())
        FROM auth.data_source_control
        WHERE source_system_id = p_source_system_id
    ), TRUE)
$$;

CREATE OR REPLACE FUNCTION util.workspace_can_use_source(
    p_workspace_id UUID,
    p_source_system_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT
            can_use_for_modeling
        FROM auth.workspace_source_entitlement
        WHERE workspace_id = p_workspace_id
          AND source_system_id = p_source_system_id
    ), TRUE)
$$;

CREATE OR REPLACE FUNCTION util.workspace_can_view_source(
    p_workspace_id UUID,
    p_source_system_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT
            can_view_source_data
        FROM auth.workspace_source_entitlement
        WHERE workspace_id = p_workspace_id
          AND source_system_id = p_source_system_id
    ), TRUE)
$$;

CREATE OR REPLACE FUNCTION util.workspace_can_trigger_ingest(
    p_workspace_id UUID,
    p_source_system_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT
            can_trigger_ingest
        FROM auth.workspace_source_entitlement
        WHERE workspace_id = p_workspace_id
          AND source_system_id = p_source_system_id
    ), FALSE)
$$;

COMMIT;