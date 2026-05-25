BEGIN;

CREATE OR REPLACE FUNCTION util.register_statcast_row_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_game_pk BIGINT,
    p_at_bat_number INT,
    p_pitch_number INT,
    p_row_payload TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_natural_key TEXT;
    v_payload_hash BYTEA;
BEGIN
    v_natural_key := concat_ws(
        ':',
        p_game_pk::TEXT,
        p_at_bat_number::TEXT,
        p_pitch_number::TEXT
    );

    v_payload_hash := util.sha256_text(p_row_payload);

    PERFORM util.register_payload_hash(
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        v_natural_key,
        v_payload_hash
    );
END;
$$;

CREATE OR REPLACE FUNCTION util.register_mlbapi_payload_hash(
    p_source_system_id SMALLINT,
    p_source_endpoint_id BIGINT,
    p_ingest_run_id UUID,
    p_natural_key TEXT,
    p_payload_json JSONB
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_payload_hash BYTEA;
BEGIN
    v_payload_hash := digest(COALESCE(p_payload_json::TEXT, ''), 'sha256');

    PERFORM util.register_payload_hash(
        p_source_system_id,
        p_source_endpoint_id,
        p_ingest_run_id,
        p_natural_key,
        v_payload_hash
    );
END;
$$;

CREATE OR REPLACE FUNCTION util.validate_statcast_pitch_business_key(
    p_game_pk BIGINT,
    p_at_bat_number INT,
    p_pitch_number INT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        p_game_pk IS NOT NULL
        AND p_at_bat_number IS NOT NULL
        AND p_pitch_number IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION util.validate_mlbapi_request_method(
    p_request_method TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT upper(trim(p_request_method)) IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE');
$$;

-- Statcast ingestion function to insert into core.plate_appearances and core.pitches
-- Following blueprint section 5.1: write to core.plate_appearances, capture UUID, use for core.pitches
CREATE OR REPLACE FUNCTION util.ingest_statcast_play(
    p_game_pk            BIGINT,
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
    -- Venue/team IDs are required to satisfy core.games FKs
    p_venue_id           BIGINT,
    p_home_team_id       BIGINT,
    p_away_team_id       BIGINT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_canonical_game_id   UUID;
    v_plate_appearance_id UUID;
    v_pitch_id            UUID;
BEGIN
    -- ── Step 1: Resolve or create the canonical game identity ──────────────
    WITH bridge AS (
        INSERT INTO stg.game_identity_bridge (
            source_system, source_game_key, season,
            game_date, home_team_code, away_team_code
        )
        VALUES (
            'statcast',
            p_game_pk::VARCHAR(50),
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
            -- canonical_game_id and created_at are never overwritten
        RETURNING canonical_game_id
    )
    SELECT canonical_game_id INTO v_canonical_game_id FROM bridge;

    -- ── Step 2: Upsert core.games row (FK required before plate_appearances) ─
    -- ON CONFLICT DO NOTHING preserves any game-level fields already set
    -- (scores, official_status) by a dedicated game-loader process.
    INSERT INTO core.games (
        game_id, venue_id, home_team_id, away_team_id,
        game_date, season, official_status
    )
    VALUES (
        v_canonical_game_id,
        p_venue_id,
        p_home_team_id,
        p_away_team_id,
        p_game_date,
        EXTRACT(YEAR FROM p_game_date)::INT,
        'final'  -- statcast rows only exist for completed games
    )
    ON CONFLICT (game_id) DO NOTHING;

    -- ── Step 3: Upsert core.plate_appearances (one row per PA, not per pitch) ─
    -- Statcast delivers one CSV row per pitch; multiple pitches share the same
    -- at-bat (p_at_bat_number). We identify a PA by (game_id, pa_sequence_order)
    -- and only insert if it does not already exist.
    INSERT INTO core.plate_appearances (
        game_id, batter_id, pitcher_id, inning, half_inning,
        outs_before, pa_sequence_order, event_result_code,
        data_source_lineage, workspace_id
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
        p_workspace_id
    )
    ON CONFLICT (game_id, pa_sequence_order) DO NOTHING
    RETURNING plate_appearance_id INTO v_plate_appearance_id;

    -- If the PA row already existed, look it up
    IF v_plate_appearance_id IS NULL THEN
        SELECT plate_appearance_id
          INTO v_plate_appearance_id
          FROM core.plate_appearances
         WHERE game_id = v_canonical_game_id
           AND pa_sequence_order = p_pa_sequence_order;
    END IF;

    -- ── Step 4: Insert pitch telemetry (unique per PA + sequence number) ────
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

COMMIT;