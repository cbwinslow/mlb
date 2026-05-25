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

-- Chadwick/Rettrosheet ingestion function to insert into core.plate_appearances and core.pitches
-- Following blueprint section 5.1: write to core.plate_appearances, capture UUID, use for core.pitches
CREATE OR REPLACE FUNCTION util.ingest_chadwick_play(
    p_game_id_text TEXT,  -- Retrosheet game ID or Chadwick equivalent
    p_at_bat_number INT,
    p_pitch_number INT,
    p_batter_id UUID,
    p_pitcher_id UUID,
    p_inning SMALLINT,
    p_half_inning CHAR(1),
    p_outs_before SMALLINT,
    p_pa_sequence_order SMALLINT,
    p_event_result_code VARCHAR(30),
    p_data_source_lineage VARCHAR(30),
    p_workspace_id UUID,
    p_balls_before SMALLINT,
    p_strikes_before SMALLINT,
    p_pitch_type CHAR(2),
    p_pitch_call CHAR(1),
    p_release_velocity NUMERIC(4,1),
    p_spin_rate SMALLINT,
    p_induced_vertical_break NUMERIC(4,2),
    p_horizontal_break NUMERIC(4,2),
    p_plate_x NUMERIC(4,2),
    p_plate_z NUMERIC(4,2),
    -- Game identity context: pass actual game date and team codes from source record
    p_game_date DATE,
    p_home_team_code CHAR(3),
    p_away_team_code CHAR(3)
)
RETURNS UUID  -- Returns the pitch_id
LANGUAGE plpgsql
AS $$
DECLARE
    v_plate_appearance_id UUID;
    v_canonical_game_id UUID;
BEGIN
    -- First, resolve or create the game identity using the bridge
    -- This follows blueprint section 4.1 for stg.game_identity_bridge
    WITH game_bridge AS (
        INSERT INTO stg.game_identity_bridge (
            source_system,
            source_game_key,
            season,
            game_date,
            home_team_code,
            away_team_code
        )
        SELECT 
            CASE 
                WHEN p_game_id_text ~ '^[A-Z]{3}[0-9]{8}[0-9]$' THEN 'retrosheet'  -- Retrosheet pattern
                ELSE 'chadwick'  -- Chadwick pattern
            END AS source_system,
            p_game_id_text                      AS source_game_key,
            EXTRACT(YEAR FROM p_game_date)::INT AS season,
            p_game_date                         AS game_date,
            p_home_team_code                    AS home_team_code,
            p_away_team_code                    AS away_team_code
        ON CONFLICT (source_system, source_game_key)
        DO UPDATE SET
            -- Never overwrite canonical_game_id — the first-inserted UUID is authoritative
            season         = EXCLUDED.season,
            game_date      = EXCLUDED.game_date,
            home_team_code = EXCLUDED.home_team_code,
            away_team_code = EXCLUDED.away_team_code
            -- created_at intentionally not updated to preserve first-seen timestamp
        RETURNING canonical_game_id
    )
    SELECT canonical_game_id INTO v_canonical_game_id FROM game_bridge;

    -- Insert into core.plate_appearances and capture the UUID
    INSERT INTO core.plate_appearances (
        game_id,
        batter_id,
        pitcher_id,
        inning,
        half_inning,
        outs_before,
        pa_sequence_order,
        event_result_code,
        data_source_lineage,
        workspace_id,
        created_at
    )
    VALUES (
        v_canonical_game_id,
        p_batter_id,
        p_pitcher_id,
        p_inning,
        p_half_inning,
        p_outs_before,
        p_pa_sequence_order,
        p_event_result_code,
        p_data_source_lineage,
        p_workspace_id,
        NOW()
    )
    RETURNING plate_appearance_id INTO v_plate_appearance_id;

    -- Insert into core.pitches using the captured plate_appearance_id
    INSERT INTO core.pitches (
        plate_appearance_id,
        pitch_sequence_num,
        balls_before,
        strikes_before,
        pitch_type,
        pitch_call,
        release_velocity,
        spin_rate,
        induced_vertical_break,
        horizontal_break,
        plate_x,
        plate_z,
        created_at
    )
    VALUES (
        v_plate_appearance_id,
        p_pitch_number,  -- Assuming p_pitch_number is the sequence number
        p_balls_before,
        p_strikes_before,
        p_pitch_type,
        p_pitch_call,
        p_release_velocity,
        p_spin_rate,
        p_induced_vertical_break,
        p_horizontal_break,
        p_plate_x,
        p_plate_z,
        NOW()
    )
    RETURNING pitch_id;

EXCEPTION
    WHEN OTHERS THEN
        -- In a real implementation, we'd want better error handling
        -- For now, we'll raise the exception to be handled by callers
        RAISE;
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