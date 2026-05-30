-- ===========================================================================
-- Statcast Advanced Metrics (Player-level Aggregations)
--
-- Adds tables for Statcast player-level aggregations from pybaseball functions:
-- statcast_batter, statcast_pitcher, statcast_pitcher_arsenal_stats,
-- statcast_batter_pitch_arsenal, statcast_sprint_speed, player percentiles
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- raw_statcast.batter_season_stats - Season-level batter stats from statcast_batter()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.batter_season_stats (
    batter_season_stat_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id BIGINT NOT NULL,
    season INTEGER NOT NULL,
    -- Counting stats
    pa INTEGER,
    ab INTEGER,
    h INTEGER,
    x2b INTEGER,
    x3b INTEGER,
    hr INTEGER,
    r INTEGER,
    rbi INTEGER,
    sb INTEGER,
    cs INTEGER,
    bb INTEGER,
    so INTEGER,
    hbp INTEGER,
    sh INTEGER,
    sf INTEGER,
    gidp INTEGER,
    -- Rate stats
    avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    woba NUMERIC(8,5),
    wrc_plus INTEGER,
    -- Expected stats
    xba NUMERIC(8,5),
    xslg NUMERIC(8,5),
    xwoba NUMERIC(8,5),
    xiso NUMERIC(8,5),
    -- Quality of contact
    barrels INTEGER,
    barrel_pct NUMERIC(8,5),
    exit_velocity_avg NUMERIC(8,3),
    launch_angle_avg NUMERIC(8,3),
    sweet_spot_pct NUMERIC(8,5),
    -- Batted ball profile
    ld_pct NUMERIC(8,5),
    gb_pct NUMERIC(8,5),
    fb_pct NUMERIC(8,5),
    pop_up_pct NUMERIC(8,5),
    -- Advanced metrics
    hard_hit_pct NUMERIC(8,5),
    k_pct NUMERIC(8,5),
    bb_pct NUMERIC(8,5),
    choke_up_pct NUMERIC(8,5),
    raw_statcast_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_batter_season_unique
        UNIQUE (statcast_search_file_id, player_id, season)
);

COMMENT ON TABLE raw_statcast.batter_season_stats IS
    'Season-level batter statistics from statcast_batter() - aggregates for player analysis.';

COMMENT ON COLUMN raw_statcast.batter_season_stats.xba IS
    'Expected batting average based on exit velocity and launch angle.';

COMMENT ON COLUMN raw_statcast.batter_season_stats.barrels IS
    'Number of batted balls with exit velocity >= 98 mph and launch angle 10-50 degrees.';


-- ---------------------------------------------------------------------------
-- raw_statcast.pitcher_season_stats - Season-level pitcher stats from statcast_pitcher()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.pitcher_season_stats (
    pitcher_season_stat_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id BIGINT NOT NULL,
    season INTEGER NOT NULL,
    -- Counting stats
    ip NUMERIC(8,1),
    bf INTEGER,
    h INTEGER,
    r INTEGER,
    er INTEGER,
    hr INTEGER,
    bb INTEGER,
    so INTEGER,
    hbp INTEGER,
    wp INTEGER,
    bk INTEGER,
    -- Derived stats
    era NUMERIC(8,3),
    fip NUMERIC(8,3),
    xfip NUMERIC(8,3),
    -- Expected stats allowed
    xba_against NUMERIC(8,5),
    xslg_against NUMERIC(8,5),
    xwoba_against NUMERIC(8,5),
    -- Quality of contact allowed
    barrels_allowed INTEGER,
    barrel_pct_against NUMERIC(8,5),
    exit_velocity_avg_against NUMERIC(8,3),
    launch_angle_avg_against NUMERIC(8,3),
    hard_hit_pct_against NUMERIC(8,5),
    -- Advanced metrics
    k_pct NUMERIC(8,5),
    bb_pct NUMERIC(8,5),
    zone_pct NUMERIC(8,5),
    whiff_pct NUMERIC(8,5),
    raw_statcast_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_pitcher_season_unique
        UNIQUE (statcast_search_file_id, player_id, season)
);

COMMENT ON TABLE raw_statcast.pitcher_season_stats IS
    'Season-level pitcher statistics from statcast_pitcher() - aggregates for player analysis.';

COMMENT ON COLUMN raw_statcast.pitcher_season_stats.xba_against IS
    'Expected batting average against for the pitcher.';


-- ---------------------------------------------------------------------------
-- raw_statcast.pitcher_arsenal - Pitch arsenals from statcast_pitcher_arsenal_stats()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.pitcher_arsenal (
    pitcher_arsenal_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id BIGINT NOT NULL,
    season INTEGER NOT NULL,
    pitch_type CHAR(2) NOT NULL,
    pitch_name TEXT,
    n_pitches INTEGER NOT NULL,
    usage_pct NUMERIC(8,5) NOT NULL,
    -- Velocity / movement
    release_velocity_avg NUMERIC(8,3),
    spin_rate_avg NUMERIC(8,3),
    induced_vertical_break_avg NUMERIC(8,3),
    horizontal_break_avg NUMERIC(8,3),
    plate_x_avg NUMERIC(8,3),
    plate_z_avg NUMERIC(8,3),
    -- Effectiveness
    ba_against NUMERIC(8,5),
    slg_against NUMERIC(8,5),
    woba_against NUMERIC(8,5),
    xba_against NUMERIC(8,5),
    whiff_pct NUMERIC(8,5),
    chase_pct NUMERIC(8,5),
    raw_arsenal_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_pitcher_arsenal_unique
        UNIQUE (statcast_search_file_id, player_id, season, pitch_type)
);

COMMENT ON TABLE raw_statcast.pitcher_arsenal IS
    'Pitch arsenal composition per pitcher per season from statcast_pitcher_arsenal_stats().';

COMMENT ON COLUMN raw_statcast.pitcher_arsenal.usage_pct IS
    'Usage percentage of this pitch type for the pitcher in the season.';


-- ---------------------------------------------------------------------------
-- raw_statcast.batter_arsenal - How batter performs vs pitch types
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.batter_arsenal (
    batter_arsenal_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id BIGINT NOT NULL,
    season INTEGER NOT NULL,
    pitch_type CHAR(2) NOT NULL,
    n_pitches INTEGER NOT NULL,
    usage_pct NUMERIC(8,5),
    ba NUMERIC(8,5),
    slg NUMERIC(8,5),
    woba NUMERIC(8,5),
    xba NUMERIC(8,5),
    run_exp NUMERIC(8,3),
    raw_arsenal_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_batter_arsenal_unique
        UNIQUE (statcast_search_file_id, player_id, season, pitch_type)
);

COMMENT ON TABLE raw_statcast.batter_arsenal IS
    'Batter performance vs pitch types from statcast_batter_pitch_arsenal().';


-- ---------------------------------------------------------------------------
-- raw_statcast.sprint_speed - Sprint speed leaderboard from statcast_sprint_speed()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.sprint_speed (
    sprint_speed_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INTEGER NOT NULL,
    player_id BIGINT NOT NULL,
    player_name TEXT,
    team TEXT,
    position TEXT,
    sprint_speed NUMERIC(8,3),
    ovr_rank INTEGER,
    lg_rank INTEGER,
    raw_sprint_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_sprint_speed_unique
        UNIQUE (statcast_search_file_id, player_id, season)
);

COMMENT ON TABLE raw_statcast.sprint_speed IS
    'Player sprint speed leaderboard from statcast_sprint_speed() - one row per player per season.';

COMMENT ON COLUMN raw_statcast.sprint_speed.sprint_speed IS
    'Maximum sprint speed in seconds (seconds per 90 ft).';


-- ---------------------------------------------------------------------------
-- raw_statcast.player_percentiles - Percentile ranks for Statcast metrics
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.player_percentiles (
    player_percentile_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id BIGINT NOT NULL,
    season INTEGER NOT NULL,
    player_type TEXT NOT NULL CHECK (player_type IN ('batter', 'pitcher')),
    -- Percentile columns (key Statcast metrics)
    exit_velocity_pct NUMERIC(8,5),
    exit_velocity_diff_pct NUMERIC(8,5),
    launch_angle_pct NUMERIC(8,5),
    launch_angle_diff_pct NUMERIC(8,5),
    sprint_speed_pct NUMERIC(8,5),
    barrel_pct_pct NUMERIC(8,5),
    hard_hit_pct_pct NUMERIC(8,5),
    whiff_pct_pct NUMERIC(8,5),
    chase_pct_pct NUMERIC(8,5),
    k_pct_pct NUMERIC(8,5),
    bb_pct_pct NUMERIC(8,5),
    -- More percentiles
    xba_pct NUMERIC(8,5),
    xslg_pct NUMERIC(8,5),
    xwoba_pct NUMERIC(8,5),
    -- Raw values for reference
    exit_velocity NUMERIC(8,3),
    launch_angle NUMERIC(8,3),
    -- Composite rank
    ranked_ovr INTEGER,
    raw_percentile_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_player_percentiles_unique
        UNIQUE (statcast_search_file_id, player_id, season, player_type)
);

COMMENT ON TABLE raw_statcast.player_percentiles IS
    'Percentile ranks for Statcast player metrics from statcast_*_percentile_ranks().';


-- ---------------------------------------------------------------------------
-- raw_statcast.fielding_oaa - Outs Above Average from statcast_outs_above_average()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_statcast.fielding_oaa (
    fielding_oaa_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INTEGER NOT NULL,
    player_id BIGINT NOT NULL,
    player_name TEXT,
    team TEXT,
    position TEXT,
    pos_group TEXT CHECK (pos_group IN ('OF', 'IF', 'C', 'P')),
    n_attempts INTEGER,
    n_success INTEGER,
    oaa_runs NUMERIC(8,2),
    oaa_per_600 NUMERIC(8,3),
    raw_oaa_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_fielding_oaa_unique
        UNIQUE (statcast_search_file_id, player_id, season, position)
);

COMMENT ON TABLE raw_statcast.fielding_oaa IS
    'Outs Above Average fielding metrics from statcast_outs_above_average().';


COMMIT;