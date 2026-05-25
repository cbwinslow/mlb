BEGIN;

CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.app_user (
    app_user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_user_key TEXT UNIQUE,
    email CITEXT,
    display_name TEXT NOT NULL,
    user_status TEXT NOT NULL DEFAULT 'active',
    is_platform_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth.organization (
    organization_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_code TEXT NOT NULL UNIQUE,
    organization_name TEXT NOT NULL,
    organization_status TEXT NOT NULL DEFAULT 'active',
    created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth.workspace (
    workspace_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID
        REFERENCES auth.organization(organization_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    workspace_code TEXT NOT NULL UNIQUE,
    workspace_name TEXT NOT NULL,
    workspace_status TEXT NOT NULL DEFAULT 'active',
    is_personal_workspace BOOLEAN NOT NULL DEFAULT FALSE,
    created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth.workspace_membership (
    workspace_membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    app_user_id UUID NOT NULL
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    membership_role TEXT NOT NULL,
    membership_status TEXT NOT NULL DEFAULT 'active',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT auth_workspace_membership_unique
        UNIQUE (workspace_id, app_user_id)
);

CREATE TABLE IF NOT EXISTS auth.service_account (
    service_account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    service_account_code TEXT NOT NULL UNIQUE,
    service_account_name TEXT NOT NULL,
    service_account_status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth.api_key (
    api_key_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    app_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    service_account_id UUID
        REFERENCES auth.service_account(service_account_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    key_prefix TEXT NOT NULL UNIQUE,
    key_hash TEXT NOT NULL UNIQUE,
    key_status TEXT NOT NULL DEFAULT 'active',
    expires_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT auth_api_key_owner_check CHECK (
        (app_user_id IS NOT NULL)::INT + (service_account_id IS NOT NULL)::INT = 1
    )
);

CREATE TABLE IF NOT EXISTS auth.data_source_control (
    data_source_control_id BIGSERIAL PRIMARY KEY,
    source_system_id BIGINT NOT NULL,
    enabled_for_ingest BOOLEAN NOT NULL DEFAULT TRUE,
    enabled_for_serving BOOLEAN NOT NULL DEFAULT TRUE,
    legal_hold BOOLEAN NOT NULL DEFAULT FALSE,
    quality_hold BOOLEAN NOT NULL DEFAULT FALSE,
    kill_switch_reason TEXT,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to TIMESTAMPTZ,
    created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT auth_data_source_control_unique
        UNIQUE (source_system_id)
);

CREATE TABLE IF NOT EXISTS auth.workspace_source_entitlement (
    workspace_source_entitlement_id BIGSERIAL PRIMARY KEY,
    workspace_id UUID NOT NULL
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_id BIGINT NOT NULL,
    can_view_source_data BOOLEAN NOT NULL DEFAULT TRUE,
    can_trigger_ingest BOOLEAN NOT NULL DEFAULT FALSE,
    can_use_for_modeling BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT auth_workspace_source_entitlement_unique
        UNIQUE (workspace_id, source_system_id)
);

COMMIT;