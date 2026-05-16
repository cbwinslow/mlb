BEGIN;

CREATE OR REPLACE FUNCTION util.ml_ops_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION util.should_stop_live_polling(
    p_abstract_game_state TEXT,
    p_coded_game_state TEXT,
    p_detailed_state TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        lower(COALESCE(p_abstract_game_state, '')) IN ('final', 'completed')
        OR lower(COALESCE(p_detailed_state, '')) IN ('final', 'completed', 'game over')
        OR upper(COALESCE(p_coded_game_state, '')) IN ('F', 'O');
$$;

CREATE OR REPLACE FUNCTION util.build_feature_entity_key(
    p_entity_grain TEXT,
    p_game_id BIGINT DEFAULT NULL,
    p_team_id BIGINT DEFAULT NULL,
    p_player_id BIGINT DEFAULT NULL,
    p_plate_appearance_id BIGINT DEFAULT NULL,
    p_pitch_id BIGINT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE lower(trim(COALESCE(p_entity_grain, '')))
            WHEN 'game' THEN concat_ws(':', 'game', p_game_id::TEXT)
            WHEN 'team_game' THEN concat_ws(':', 'team_game', p_team_id::TEXT, p_game_id::TEXT)
            WHEN 'player_game' THEN concat_ws(':', 'player_game', p_player_id::TEXT, p_game_id::TEXT)
            WHEN 'plate_appearance' THEN concat_ws(':', 'plate_appearance', p_plate_appearance_id::TEXT)
            WHEN 'pitch' THEN concat_ws(':', 'pitch', p_pitch_id::TEXT)
            ELSE concat_ws(
                ':',
                lower(trim(COALESCE(p_entity_grain, 'unknown'))),
                COALESCE(p_game_id::TEXT, 'na'),
                COALESCE(p_team_id::TEXT, 'na'),
                COALESCE(p_player_id::TEXT, 'na'),
                COALESCE(p_plate_appearance_id::TEXT, 'na'),
                COALESCE(p_pitch_id::TEXT, 'na')
            )
        END;
$$;

CREATE OR REPLACE FUNCTION util.safe_prediction_rank_score(
    p_prediction_probability NUMERIC,
    p_edge NUMERIC DEFAULT NULL,
    p_confidence NUMERIC DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(p_edge, 0) * 0.7
         + COALESCE(p_prediction_probability, 0) * 0.2
         + COALESCE(p_confidence, 0) * 0.1;
$$;

DROP TRIGGER IF EXISTS trg_ml_problem_definition_updated_at ON ml.problem_definition;
CREATE TRIGGER trg_ml_problem_definition_updated_at
BEFORE UPDATE ON ml.problem_definition
FOR EACH ROW
EXECUTE FUNCTION util.ml_ops_touch_updated_at();

DROP TRIGGER IF EXISTS trg_ml_feature_set_updated_at ON ml.feature_set;
CREATE TRIGGER trg_ml_feature_set_updated_at
BEFORE UPDATE ON ml.feature_set
FOR EACH ROW
EXECUTE FUNCTION util.ml_ops_touch_updated_at();

DROP TRIGGER IF EXISTS trg_ml_feature_definition_updated_at ON ml.feature_definition;
CREATE TRIGGER trg_ml_feature_definition_updated_at
BEFORE UPDATE ON ml.feature_definition
FOR EACH ROW
EXECUTE FUNCTION util.ml_ops_touch_updated_at();

DROP TRIGGER IF EXISTS trg_ml_model_definition_updated_at ON ml.model_definition;
CREATE TRIGGER trg_ml_model_definition_updated_at
BEFORE UPDATE ON ml.model_definition
FOR EACH ROW
EXECUTE FUNCTION util.ml_ops_touch_updated_at();

DROP TRIGGER IF EXISTS trg_ops_live_game_poller_updated_at ON ops.live_game_poller;
CREATE TRIGGER trg_ops_live_game_poller_updated_at
BEFORE UPDATE ON ops.live_game_poller
FOR EACH ROW
EXECUTE FUNCTION util.ml_ops_touch_updated_at();

DROP TRIGGER IF EXISTS trg_ops_scheduled_job_updated_at ON ops.scheduled_job;
CREATE TRIGGER trg_ops_scheduled_job_updated_at
BEFORE UPDATE ON ops.scheduled_job
FOR EACH ROW
EXECUTE FUNCTION util.ml_ops_touch_updated_at();

COMMIT;