BEGIN;

CREATE OR REPLACE FUNCTION util.stg_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION util.normalize_team_code(
    p_team_code TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(upper(trim(p_team_code)), '');
$$;

CREATE OR REPLACE FUNCTION util.normalize_player_code(
    p_player_code TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(lower(trim(p_player_code)), '');
$$;

CREATE OR REPLACE FUNCTION util.build_retrosheet_game_id(
    p_home_team_code TEXT,
    p_game_date DATE,
    p_game_number SMALLINT DEFAULT 0
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE
            WHEN p_home_team_code IS NULL OR p_game_date IS NULL THEN NULL
            ELSE upper(trim(p_home_team_code))
                 || to_char(p_game_date, 'YYYYMMDD')
                 || COALESCE(p_game_number::TEXT, '0')
        END;
$$;

CREATE OR REPLACE FUNCTION util.identity_match_score(
    p_exact_id_match BOOLEAN,
    p_name_match BOOLEAN,
    p_birth_date_match BOOLEAN
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE
            WHEN p_exact_id_match THEN 1.000
            WHEN p_name_match AND p_birth_date_match THEN 0.950
            WHEN p_name_match THEN 0.700
            ELSE 0.000
        END;
$$;

DROP TRIGGER IF EXISTS trg_stg_player_identity_updated_at ON stg.player_identity;
CREATE TRIGGER trg_stg_player_identity_updated_at
BEFORE UPDATE ON stg.player_identity
FOR EACH ROW
EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_team_identity_updated_at ON stg.team_identity;
CREATE TRIGGER trg_stg_team_identity_updated_at
BEFORE UPDATE ON stg.team_identity
FOR EACH ROW
EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_venue_identity_updated_at ON stg.venue_identity;
CREATE TRIGGER trg_stg_venue_identity_updated_at
BEFORE UPDATE ON stg.venue_identity
FOR EACH ROW
EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_game_identity_updated_at ON stg.game_identity;
CREATE TRIGGER trg_stg_game_identity_updated_at
BEFORE UPDATE ON stg.game_identity
FOR EACH ROW
EXECUTE FUNCTION util.stg_touch_updated_at();

COMMIT;