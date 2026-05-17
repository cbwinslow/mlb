BEGIN;

CREATE OR REPLACE VIEW mart.v_source_system_status
WITH (security_barrier = true)
AS
SELECT
    ss.source_system_id,
    ss.source_code,
    ss.source_name,
    COALESCE(dsc.enabled_for_ingest, TRUE) AS enabled_for_ingest,
    COALESCE(dsc.enabled_for_serving, TRUE) AS enabled_for_serving,
    COALESCE(dsc.legal_hold, FALSE) AS legal_hold,
    COALESCE(dsc.quality_hold, FALSE) AS quality_hold,
    dsc.kill_switch_reason,
    dsc.effective_from,
    dsc.effective_to,
    dsc.updated_at
FROM meta.source_system ss
LEFT JOIN auth.data_source_control dsc
    ON dsc.source_system_id = ss.source_system_id;

CREATE OR REPLACE VIEW mart.v_workspace_source_access
WITH (security_barrier = true)
AS
SELECT
    w.workspace_id,
    w.workspace_code,
    ss.source_system_id,
    ss.source_code,
    util.source_is_enabled_for_serving(ss.source_system_id) AS source_globally_enabled_for_serving,
    util.workspace_can_view_source(w.workspace_id, ss.source_system_id) AS workspace_can_view_source_data,
    util.workspace_can_use_source(w.workspace_id, ss.source_system_id) AS workspace_can_use_for_modeling,
    util.workspace_can_trigger_ingest(w.workspace_id, ss.source_system_id) AS workspace_can_trigger_ingest
FROM auth.workspace w
CROSS JOIN meta.source_system ss;

CREATE OR REPLACE VIEW mart.v_workspace_model_catalog
WITH (security_barrier = true)
AS
SELECT
    md.model_definition_id,
    md.workspace_id,
    w.workspace_code,
    md.model_code,
    md.model_name,
    md.model_version,
    mf.model_family_code,
    mf.model_family_name,
    pd.problem_code,
    pd.problem_name,
    fs.feature_set_code,
    fs.feature_set_name,
    md.training_framework,
    md.is_ensemble,
    md.ensemble_method,
    md.status_code,
    md.created_at,
    md.updated_at
FROM ml.model_definition md
JOIN ml.model_family mf
    ON mf.model_family_id = md.model_family_id
JOIN ml.problem_definition pd
    ON pd.problem_definition_id = md.problem_definition_id
LEFT JOIN ml.feature_set fs
    ON fs.feature_set_id = md.feature_set_id
LEFT JOIN auth.workspace w
    ON w.workspace_id = md.workspace_id;

COMMIT;