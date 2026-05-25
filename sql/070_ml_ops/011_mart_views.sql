BEGIN;

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