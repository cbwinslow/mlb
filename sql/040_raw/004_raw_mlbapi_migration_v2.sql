-- ===========================================================================
-- Issue #10: MLB API Typed Extraction Tables (Boxscore and Venue)
--
-- Adds typed tables for boxscore data and venue information to complement
-- the existing JSONB ingest tables in 004_raw_mlbapi.sql.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- raw_mlbapi.boxscore_batting_line - Expanded batting stats from boxscore endpoint
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_mlbapi.boxscore_batting_line (
    raw_boxscore_batting_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_pk BIGINT NOT NULL,
    team_id BIGINT,
    team_abbr TEXT,
    team_name TEXT,
    jersey_number TEXT,
    player_id BIGINT NOT NULL,
    player_full_name TEXT,
    batting_order INT,
    position_code TEXT,
    position_name TEXT,
    -- Counting stats
    ab INT,
    r INT,
    h INT,
    x2b INT,
    x3b INT,
    hr INT,
    rbi INT,
    bb INT,
    so INT,
    hbp INT,
    sf INT,
    sh INT,
    tb INT,
    gidp INT,
    cs INT,
    po INT,
    a INT,
    e INT,
    ch INT,
    dp INT,
    tp INT,
    -- Rate stats
    avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    -- Advanced metrics
    woba NUMERIC(8,5),
    wrc_plus INT,
    -- Game-specific flags
    started_game BOOLEAN,
    substituted BOOLEAN,
    raw_batting_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_boxscore_batting_unique
        UNIQUE (mlbapi_payload_id, game_pk, team_id, player_id)
);

COMMENT ON TABLE raw_mlbapi.boxscore_batting_line IS
    'Expanded batting stats from MLB StatsAPI boxscore endpoint. One row per batter per game.';

COMMENT ON COLUMN raw_mlbapi.boxscore_batting_line.game_pk IS
    'MLBAM game primary key, links to schedule_game.game_pk.';

COMMENT ON COLUMN raw_mlbapi.boxscore_batting_line.player_id IS
    'MLBAM person ID for the batter.';

COMMENT ON COLUMN raw_mlbapi.boxscore_batting_line.batting_order IS
    'Batting order position (1-9), NULL for substitutes.';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.boxscore_pitching_line - Expanded pitching stats from boxscore endpoint
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_mlbapi.boxscore_pitching_line (
    raw_boxscore_pitching_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_pk BIGINT NOT NULL,
    team_id BIGINT,
    team_abbr TEXT,
    team_name TEXT,
    jersey_number TEXT,
    player_id BIGINT NOT NULL,
    player_full_name TEXT,
    -- Game log stats
    win BOOLEAN,
    loss BOOLEAN,
    save BOOLEAN,
    hold BOOLEAN,
    blown_save BOOLEAN,
    -- Counting stats
    ip_str TEXT,
    ip_outs INT,
    bf INT,
    p INT,
    s INT,
    h INT,
    r INT,
    er INT,
    x2b INT,
    x3b INT,
    hr INT,
    bb INT,
    so INT,
    hbp INT,
    bk INT,
    wp INT,
    cg INT,
    sho INT,
    -- Rate stats
    era NUMERIC(8,3),
    fip NUMERIC(8,3),
    -- Advanced metrics
    xera NUMERIC(8,3),
    fip_minus INT,
    -- Game-specific flags
    started_game BOOLEAN,
    substituted BOOLEAN,
    raw_pitching_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_boxscore_pitching_unique
        UNIQUE (mlbapi_payload_id, game_pk, team_id, player_id)
);

COMMENT ON TABLE raw_mlbapi.boxscore_pitching_line IS
    'Expanded pitching stats from MLB StatsAPI boxscore endpoint. One row per pitcher per game.';

COMMENT ON COLUMN raw_mlbapi.boxscore_pitching_line.ip_outs IS
    'Innings pitched in outs (1/3 increments) for numeric calculations.';

COMMENT ON COLUMN raw_mlbapi.boxscore_pitching_line.player_id IS
    'MLBAM person ID for the pitcher.';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.venue - Expanded venue/park information
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_mlbapi.venue (
    raw_venue_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    venue_id BIGINT NOT NULL,
    venue_name TEXT,
    venue_city TEXT,
    venue_state TEXT,
    venue_country TEXT,
    venue_zip TEXT,
    venue_timezone TEXT,
    venue_latitude NUMERIC(12,8),
    venue_longitude NUMERIC(12,8),
    venue_arena_name TEXT,
    venue_field_surface TEXT,
    venue_capacity INT,
    venue_opened DATE,
    venue_closed DATE,
    active BOOLEAN,
    raw_venue_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_venue_unique
        UNIQUE (mlbapi_payload_id, venue_id)
);

COMMENT ON TABLE raw_mlbapi.venue IS
    'Expanded venue/park information from MLB StatsAPI venues endpoint.';

COMMENT ON COLUMN raw_mlbapi.venue.venue_id IS
    'MLBAM venue ID, links to core.venue.mlbam_venue_id.';

COMMENT ON COLUMN raw_mlbapi.venue.venue_capacity IS
    'Seating capacity of the venue.';

COMMENT ON COLUMN raw_mlbapi.venue.venue_field_surface IS
    'Playing surface type (grass, artificial, etc.).';

COMMIT;