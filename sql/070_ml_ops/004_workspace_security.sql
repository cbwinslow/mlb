BEGIN;

ALTER TABLE ml.feature_set
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.model_definition
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.dataset_definition
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.training_run
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.backtest_run
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.prediction_run
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.prediction_output
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.simulation_run
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ops.live_game_poller
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ops.scheduled_job
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ops.job_run
    ADD COLUMN IF NOT EXISTS workspace_id UUID
        REFERENCES auth.workspace(workspace_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE;

ALTER TABLE ml.feature_set
    ADD COLUMN IF NOT EXISTS created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL;

ALTER TABLE ml.model_definition
    ADD COLUMN IF NOT EXISTS created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL;

ALTER TABLE ml.dataset_definition
    ADD COLUMN IF NOT EXISTS created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL;

ALTER TABLE ops.scheduled_job
    ADD COLUMN IF NOT EXISTS created_by_user_id UUID
        REFERENCES auth.app_user(app_user_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL;

COMMIT;