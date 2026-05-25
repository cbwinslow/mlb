BEGIN;

CREATE OR REPLACE FUNCTION util.core_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION util.normalize_inning_half(
    p_inning_half TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE
            WHEN lower(trim(COALESCE(p_inning_half, ''))) IN ('top', 't', 'away') THEN 'top'
            WHEN lower(trim(COALESCE(p_inning_half, ''))) IN ('bottom', 'bot', 'b', 'home') THEN 'bottom'
            ELSE NULL
        END;
$$;

CREATE OR REPLACE FUNCTION util.build_pa_key(
    p_game_id BIGINT,
    p_inning SMALLINT,
    p_inning_half TEXT,
    p_plate_appearance_number INT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT concat_ws(
        ':',
        p_game_id::TEXT,
        p_inning::TEXT,
        util.normalize_inning_half(p_inning_half),
        p_plate_appearance_number::TEXT
    );
$$;

CREATE OR REPLACE FUNCTION util.build_pitch_key(
    p_game_id BIGINT,
    p_inning SMALLINT,
    p_inning_half TEXT,
    p_plate_appearance_number INT,
    p_pitch_number INT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT concat_ws(
        ':',
        p_game_id::TEXT,
        p_inning::TEXT,
        util.normalize_inning_half(p_inning_half),
        p_plate_appearance_number::TEXT,
        p_pitch_number::TEXT
    );
$$;

DROP TRIGGER IF EXISTS trg_core_player_updated_at ON core.player;
CREATE TRIGGER trg_core_player_updated_at
BEFORE UPDATE ON core.player
FOR EACH ROW
EXECUTE FUNCTION util.core_touch_updated_at();

DROP TRIGGER IF EXISTS trg_core_team_updated_at ON core.team;
CREATE TRIGGER trg_core_team_updated_at
BEFORE UPDATE ON core.team
FOR EACH ROW
EXECUTE FUNCTION util.core_touch_updated_at();

DROP TRIGGER IF EXISTS trg_core_venue_updated_at ON core.venue;
CREATE TRIGGER trg_core_venue_updated_at
BEFORE UPDATE ON core.venue
FOR EACH ROW
EXECUTE FUNCTION util.core_touch_updated_at();

COMMIT;