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

-- Chadwick/Retrosheet ingestion function to insert into core.plate_appearances and core.pitches
-- Following blueprint section 5.1: write to core.plate_appearances, capture UUID, use for core.pitches
-- Issue #36 fix: resolves MLBAM IDs through stg.player_identity -> core.player bridge
CREATE OR REPLACE FUNCTION util.ingest_chadwick_play(
    p_game_id_text       TEXT,       -- Retrosheet/Chadwick game ID string
    p_at_bat_number      INT,
    p_pitch_number       INT,
    p_batter_id          BIGINT,
    p_pitcher_id         BIGINT,
    p_inning             SMALLINT,
    p_half_inning        CHAR(1),
    p_outs_before        SMALLINT,
    p_pa_sequence_order  SMALLINT,
    p_event_result_code  VARCHAR(30),
    p_data_source_lineage VARCHAR(30),
    p_workspace_id       UUID,
    p_balls_before       SMALLINT,
    p_strikes_before     SMALLINT,
    p_pitch_type         CHAR(2),
    p_pitch_call         CHAR(1),
    p_release_velocity   NUMERIC(4,1),
    p_spin_rate          SMALLINT,
    p_induced_vertical_break NUMERIC(4,2),
    p_horizontal_break   NUMERIC(4,2),
    p_plate_x            NUMERIC(4,2),
    p_plate_z            NUMERIC(4,2),
    p_game_date          DATE,
    p_home_team_code     CHAR(3),
    p_away_team_code     CHAR(3),
    p_venue_id           BIGINT,
    p_home_team_id       BIGINT,     -- MLBAM team ID, will be resolved via stg.team_identity
    p_away_team_id       BIGINT,
    p_batter_name        TEXT,       -- Player name for identity resolution
    p_pitcher_name       TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_system       TEXT;
    v_canonical_game_id   UUID;
    v_plate_appearance_id UUID;
    v_pitch_id            UUID;
    v_resolved_batter_id  BIGINT;
    v_resolved_pitcher_id BIGINT;
    v_resolved_home_team  BIGINT;
    v_resolved_away_team  BIGINT;
BEGIN
    -- Detect source system from game ID format
    v_source_system := CASE
        WHEN p_game_id_text ~ '^[A-Z]{3}[0-9]{8}[0-9]$' THEN 'retrosheet'
        ELSE 'chadwick'
    END;

    -- ── Step 1: Resolve or create the canonical game identity ──────────────
    WITH bridge AS (
        INSERT INTO stg.game_identity_bridge (
            source_system, source_game_key, season,
            game_date, home_team_code, away_team_code
        )
        VALUES (
            v_source_system,
            p_game_id_text,
            EXTRACT(YEAR FROM p_game_date)::INT,
            p_game_date,
            p_home_team_code,
            p_away_team_code
        )
        ON CONFLICT (source_system, source_game_key)
        DO UPDATE SET
            season         = EXCLUDED.season,
            game_date      = EXCLUDED.game_date,
            home_team_code = EXCLUDED.home_team_code,
            away_team_code = EXCLUDED.away_team_code
        RETURNING canonical_game_id
    )
    SELECT canonical_game_id INTO v_canonical_game_id FROM bridge;

    -- ── Step 2: Resolve team IDs through stg.team_identity bridge ───────────
    -- This ensures teams exist in core.team before game insert
    v_resolved_home_team := util.resolve_team_id(p_home_team_id, NULL);
    v_resolved_away_team := util.resolve_team_id(p_away_team_id, NULL);

    -- ── Step 3: Upsert core.games row (FK required before plate_appearances) ─
    INSERT INTO core.games (
        game_id, venue_id, home_team_id, away_team_id,
        game_date, season, official_status
    )
    VALUES (
        v_canonical_game_id,
        p_venue_id,
        v_resolved_home_team,
        v_resolved_away_team,
        p_game_date,
        EXTRACT(YEAR FROM p_game_date)::INT,
        'final'
    )
    ON CONFLICT (game_id) DO UPDATE
        SET venue_id = EXCLUDED.venue_id,
            home_team_id = EXCLUDED.home_team_id,
            away_team_id = EXCLUDED.away_team_id,
            game_date = EXCLUDED.game_date,
            season = EXCLUDED.season;

    -- ── Step 4: Resolve player IDs through stg.player_identity bridge ───────
    -- This ensures players exist in core.player before PA insert
    v_resolved_batter_id := util.resolve_player_id(p_batter_id, p_batter_name);
    v_resolved_pitcher_id := util.resolve_player_id(p_pitcher_id, p_pitcher_name);

    -- ── Step 5: Upsert core.plate_appearances (one row per PA, not per pitch) ─
    INSERT INTO core.plate_appearances (
        game_id, batter_id, pitcher_id, inning, half_inning,
        outs_before, pa_sequence_order, event_result_code,
        data_source_lineage, workspace_id
    )
    VALUES (
        v_canonical_game_id,
        v_resolved_batter_id,
        v_resolved_pitcher_id,
        p_inning,
        p_half_inning,
        p_outs_before,
        p_pa_sequence_order,
        p_event_result_code,
        p_data_source_lineage,
        p_workspace_id
    )
    ON CONFLICT (game_id, pa_sequence_order) DO UPDATE
        SET batter_id = EXCLUDED.batter_id,
            pitcher_id = EXCLUDED.pitcher_id,
            inning = EXCLUDED.inning,
            half_inning = EXCLUDED.half_inning,
            outs_before = EXCLUDED.outs_before,
            event_result_code = EXCLUDED.event_result_code
    RETURNING plate_appearance_id INTO v_plate_appearance_id;

    IF v_plate_appearance_id IS NULL THEN
        SELECT plate_appearance_id
          INTO v_plate_appearance_id
          FROM core.plate_appearances
         WHERE game_id = v_canonical_game_id
           AND pa_sequence_order = p_pa_sequence_order;
    END IF;

    -- ── Step 6: Insert pitch telemetry ──────────────────────────────────────
    INSERT INTO core.pitches (
        plate_appearance_id, pitch_sequence_num, balls_before, strikes_before,
        pitch_type, pitch_call, release_velocity, spin_rate,
        induced_vertical_break, horizontal_break, plate_x, plate_z
    )
    VALUES (
        v_plate_appearance_id,
        p_pitch_number,
        p_balls_before,
        p_strikes_before,
        p_pitch_type,
        p_pitch_call,
        p_release_velocity,
        p_spin_rate,
        p_induced_vertical_break,
        p_horizontal_break,
        p_plate_x,
        p_plate_z
    )
    ON CONFLICT (plate_appearance_id, pitch_sequence_num) DO NOTHING
    RETURNING pitch_id INTO v_pitch_id;

    RETURN v_pitch_id;

EXCEPTION
    WHEN OTHERS THEN
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

-- Unified ingestion entry point (delegates to source-specific logic)
-- This single function reduces duplication between ingest_statcast_play and ingest_chadwick_play.
-- Issue #36 fix: resolves MLBAM IDs through stg.player_identity -> core.player bridge
CREATE OR REPLACE FUNCTION util.ingest_play_event(
    p_source_system       VARCHAR(30),  -- 'statcast', 'retrosheet', 'chadwick', 'mlb_api'
    p_source_game_key     VARCHAR(50),  -- game_pk (statcast) or retrosheet game ID
    p_at_bat_number       INT,
    p_pitch_number        INT,
    p_batter_id           BIGINT,
    p_pitcher_id          BIGINT,
    p_inning              SMALLINT,
    p_half_inning         CHAR(1),
    p_outs_before         SMALLINT,
    p_pa_sequence_order   SMALLINT,
    p_event_result_code   VARCHAR(30),
    p_data_source_lineage VARCHAR(30),
    p_workspace_id        UUID,
    p_balls_before        SMALLINT,
    p_strikes_before      SMALLINT,
    p_pitch_type          CHAR(2),
    p_pitch_call          CHAR(1),
    p_release_velocity    NUMERIC(4,1),
    p_spin_rate           SMALLINT,
    p_induced_vertical_break NUMERIC(4,2),
    p_horizontal_break    NUMERIC(4,2),
    p_plate_x             NUMERIC(4,2),
    p_plate_z             NUMERIC(4,2),
    p_game_date           DATE,
    p_home_team_code      CHAR(3),
    p_away_team_code      CHAR(3),
    p_home_team_id        BIGINT,     -- MLBAM team ID, will be resolved via stg.team_identity
    p_away_team_id        BIGINT,
    p_batter_name         TEXT,       -- Player name for identity resolution
    p_pitcher_name        TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_plate_appearance_id UUID;
    v_canonical_game_id   UUID;
    v_pitch_id            UUID;
    v_resolved_batter_id  BIGINT;
    v_resolved_pitcher_id BIGINT;
BEGIN
    -- Resolve or create canonical game identity
    WITH game_bridge AS (
        INSERT INTO stg.game_identity_bridge (
            source_system, source_game_key, season,
            game_date, home_team_code, away_team_code
        )
        VALUES (
            p_source_system,
            p_source_game_key,
            EXTRACT(YEAR FROM p_game_date)::INT,
            p_game_date,
            p_home_team_code,
            p_away_team_code
        )
        ON CONFLICT (source_system, source_game_key)
        DO UPDATE SET
            -- Never overwrite canonical_game_id; only refresh metadata if changed
            season         = EXCLUDED.season,
            game_date      = EXCLUDED.game_date,
            home_team_code = EXCLUDED.home_team_code,
            away_team_code = EXCLUDED.away_team_code
        RETURNING canonical_game_id
    )
    SELECT canonical_game_id INTO v_canonical_game_id FROM game_bridge;

    -- Resolve player IDs through stg.player_identity bridge
    -- This ensures players exist in core.player before PA insert
    v_resolved_batter_id := util.resolve_player_id(p_batter_id, p_batter_name);
    v_resolved_pitcher_id := util.resolve_player_id(p_pitcher_id, p_pitcher_name);

    -- Insert plate appearance (idempotent with ON CONFLICT DO UPDATE)
    INSERT INTO core.plate_appearances (
        game_id, batter_id, pitcher_id, inning, half_inning,
        outs_before, pa_sequence_order, event_result_code,
        data_source_lineage, workspace_id, created_at
    )
    VALUES (
        v_canonical_game_id, v_resolved_batter_id, v_resolved_pitcher_id,
        p_inning, p_half_inning, p_outs_before, p_pa_sequence_order,
        p_event_result_code, p_data_source_lineage, p_workspace_id, NOW()
    )
    ON CONFLICT (game_id, pa_sequence_order) DO UPDATE
        SET batter_id = EXCLUDED.batter_id,
            pitcher_id = EXCLUDED.pitcher_id
    RETURNING plate_appearance_id INTO v_plate_appearance_id;

    -- If no row returned (shouldn't happen with DO UPDATE), fetch existing
    IF v_plate_appearance_id IS NULL THEN
        SELECT plate_appearance_id
          INTO v_plate_appearance_id
          FROM core.plate_appearances
         WHERE game_id = v_canonical_game_id
           AND pa_sequence_order = p_pa_sequence_order;
    END IF;

    -- Insert pitch telemetry
    INSERT INTO core.pitches (
        plate_appearance_id, pitch_sequence_num, balls_before, strikes_before,
        pitch_type, pitch_call, release_velocity, spin_rate,
        induced_vertical_break, horizontal_break, plate_x, plate_z, created_at
    )
    VALUES (
        v_plate_appearance_id, p_pitch_number, p_balls_before, p_strikes_before,
        p_pitch_type, p_pitch_call, p_release_velocity, p_spin_rate,
        p_induced_vertical_break, p_horizontal_break, p_plate_x, p_plate_z, NOW()
    )
    ON CONFLICT (plate_appearance_id, pitch_sequence_num) DO NOTHING
    RETURNING pitch_id INTO v_pitch_id;

    RETURN v_pitch_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;

COMMENT ON FUNCTION util.ingest_play_event IS
    'Unified play-event ingestion entry point for all source systems.
     Resolves MLBAM IDs through stg.player_identity -> core.player bridge.
     Source-specific functions (ingest_statcast_play, ingest_chadwick_play) now delegate here.';

-- ---------------------------------------------------------------------------
-- Triggers for mlbapi staging tables (moved from 007_mlbapi_extraction.sql)
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_stg_mlbapi_game_updated_at ON stg.mlbapi_game;
CREATE TRIGGER trg_stg_mlbapi_game_updated_at
    BEFORE UPDATE ON stg.mlbapi_game
    FOR EACH ROW
    EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_mlbapi_person_updated_at ON stg.mlbapi_person;
CREATE TRIGGER trg_stg_mlbapi_person_updated_at
    BEFORE UPDATE ON stg.mlbapi_person
    FOR EACH ROW
    EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_mlbapi_team_updated_at ON stg.mlbapi_team;
CREATE TRIGGER trg_stg_mlbapi_team_updated_at
    BEFORE UPDATE ON stg.mlbapi_team
    FOR EACH ROW
    EXECUTE FUNCTION util.stg_touch_updated_at();

COMMIT;