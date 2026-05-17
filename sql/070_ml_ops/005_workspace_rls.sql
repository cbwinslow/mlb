BEGIN;

ALTER TABLE ml.feature_set ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.model_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.dataset_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.training_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.backtest_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.prediction_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.prediction_output ENABLE ROW LEVEL SECURITY;
ALTER TABLE ml.simulation_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.live_game_poller ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.scheduled_job ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.job_run ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ml_feature_set_workspace_policy ON ml.feature_set;
CREATE POLICY ml_feature_set_workspace_policy
ON ml.feature_set
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_model_definition_workspace_policy ON ml.model_definition;
CREATE POLICY ml_model_definition_workspace_policy
ON ml.model_definition
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_dataset_definition_workspace_policy ON ml.dataset_definition;
CREATE POLICY ml_dataset_definition_workspace_policy
ON ml.dataset_definition
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_training_run_workspace_policy ON ml.training_run;
CREATE POLICY ml_training_run_workspace_policy
ON ml.training_run
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_backtest_run_workspace_policy ON ml.backtest_run;
CREATE POLICY ml_backtest_run_workspace_policy
ON ml.backtest_run
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_prediction_run_workspace_policy ON ml.prediction_run;
CREATE POLICY ml_prediction_run_workspace_policy
ON ml.prediction_run
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_prediction_output_workspace_policy ON ml.prediction_output;
CREATE POLICY ml_prediction_output_workspace_policy
ON ml.prediction_output
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ml_simulation_run_workspace_policy ON ml.simulation_run;
CREATE POLICY ml_simulation_run_workspace_policy
ON ml.simulation_run
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ops_live_game_poller_workspace_policy ON ops.live_game_poller;
CREATE POLICY ops_live_game_poller_workspace_policy
ON ops.live_game_poller
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ops_scheduled_job_workspace_policy ON ops.scheduled_job;
CREATE POLICY ops_scheduled_job_workspace_policy
ON ops.scheduled_job
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

DROP POLICY IF EXISTS ops_job_run_workspace_policy ON ops.job_run;
CREATE POLICY ops_job_run_workspace_policy
ON ops.job_run
FOR ALL
TO mlb_app_user, mlb_worker, mlb_api, mlb_readonly
USING (
    util.current_is_platform_admin()
    OR workspace_id IS NULL
    OR workspace_id = util.current_workspace_id()
)
WITH CHECK (
    util.current_is_platform_admin()
    OR workspace_id = util.current_workspace_id()
);

COMMIT;