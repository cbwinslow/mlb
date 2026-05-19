BEGIN;

CREATE TABLE IF NOT EXISTS raw_statcast.search_file (
    statcast_search_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    query_start_date DATE,
    query_end_date DATE,
    query_params JSONB,
    export_source TEXT NOT NULL DEFAULT 'statcast_search_csv',
    tool_name TEXT,
    tool_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_statcast.search_file IS
    'Metadata for a Statcast search extraction, whether via direct CSV export or pybaseball.';

CREATE TABLE IF NOT EXISTS raw_statcast.pitch (
    raw_statcast_pitch_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID NOT NULL
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    -- Core identifiers
    pitch_type TEXT,
    game_date DATE,
    game_year INT,
    game_pk BIGINT,
    game_id TEXT,                          -- Retrosheet-style cross-source join key e.g. TEX202304060
    at_bat_number INT,
    pitch_number INT,

    -- Player identifiers
    player_name TEXT,
    batter BIGINT,
    pitcher BIGINT,
    fielder_2 BIGINT,
    umpire BIGINT,
    pitcher_1 BIGINT,
    fielder_2_1 BIGINT,
    fielder_3 BIGINT,
    fielder_4 BIGINT,
    fielder_5 BIGINT,
    fielder_6 BIGINT,
    fielder_7 BIGINT,
    fielder_8 BIGINT,
    fielder_9 BIGINT,

    -- Pitch outcome
    events TEXT,
    description TEXT,
    des TEXT,
    type TEXT,
    pitch_name TEXT,

    -- Game context
    game_type TEXT,
    stand TEXT,
    p_throws TEXT,
    home_team TEXT,
    away_team TEXT,
    hit_location SMALLINT,
    bb_type TEXT,
    balls SMALLINT,
    strikes SMALLINT,
    on_3b BIGINT,
    on_2b BIGINT,
    on_1b BIGINT,
    outs_when_up SMALLINT,
    inning SMALLINT,
    inning_topbot TEXT,
    zone SMALLINT,
    if_fielding_alignment TEXT,
    of_fielding_alignment TEXT,

    -- Score at time of pitch and post-PA
    home_score INT,
    away_score INT,
    bat_score INT,
    fld_score INT,
    post_away_score INT,
    post_home_score INT,
    post_bat_score INT,
    post_fld_score INT,
    home_score_ct INT,                     -- home score at moment of pitch (not post-PA)
    away_score_ct INT,                     -- away score at moment of pitch (not post-PA)

    -- Release point and velocity
    release_speed NUMERIC(8,3),
    release_pos_x NUMERIC(10,5),
    release_pos_z NUMERIC(10,5),
    release_pos_y NUMERIC(10,5),
    release_extension NUMERIC(10,5),
    release_spin_rate NUMERIC(10,5),
    effective_speed NUMERIC(8,3),
    arm_angle NUMERIC(8,3),               -- pitcher arm slot angle at release

    -- Trajectory physics
    vx0 NUMERIC(12,6),
    vy0 NUMERIC(12,6),
    vz0 NUMERIC(12,6),
    ax NUMERIC(12,6),
    ay NUMERIC(12,6),
    az NUMERIC(12,6),
    pfx_x NUMERIC(10,5),
    pfx_z NUMERIC(10,5),
    plate_x NUMERIC(10,5),
    plate_z NUMERIC(10,5),
    sz_top NUMERIC(10,5),
    sz_bot NUMERIC(10,5),
    spin_axis NUMERIC(8,3),

    -- Break metrics (API-derived)
    api_break_z_with_gravity NUMERIC(10,5),  -- vertical break including gravity effect
    api_break_x_arm NUMERIC(10,5),            -- horizontal break from arm-side perspective
    api_break_x_batter_in NUMERIC(10,5),      -- horizontal break from batter perspective

    -- Deprecated / legacy fields retained for historical completeness
    spin_dir NUMERIC(10,5),
    spin_rate_deprecated NUMERIC(10,5),
    break_angle_deprecated NUMERIC(10,5),
    break_length_deprecated NUMERIC(10,5),
    sv_id TEXT,
    tfs_deprecated TEXT,
    tfs_zulu_deprecated TIMESTAMPTZ,

    -- Batted ball outcome
    hc_x NUMERIC(10,5),
    hc_y NUMERIC(10,5),
    hit_distance_sc INT,
    launch_speed NUMERIC(8,3),
    launch_angle NUMERIC(8,3),
    launch_speed_angle SMALLINT,

    -- Bat tracking (2024+)
    bat_speed NUMERIC(8,3),               -- bat speed at contact in mph
    swing_length NUMERIC(8,3),            -- swing path length in feet

    -- Sprint / Outs Above Average context
    hyper_speed NUMERIC(8,3),             -- baserunner sprint speed on batted ball events

    -- Expected outcome metrics
    estimated_ba_using_speedangle NUMERIC(8,5),
    estimated_woba_using_speedangle NUMERIC(8,5),
    estimated_slg_using_speedangle NUMERIC(8,5),   -- xSLG
    woba_value NUMERIC(8,5),
    woba_denom NUMERIC(8,5),
    babip_value NUMERIC(8,5),
    iso_value NUMERIC(8,5),

    -- Win/run expectancy
    delta_home_win_exp NUMERIC(10,5),
    delta_run_exp NUMERIC(10,5),
    delta_pitcher_run_exp NUMERIC(10,5),   -- pitcher-perspective run expectancy delta

    -- Pitcher context / fatigue
    n_thruorder_pitcher INT,               -- how many times pitcher has been through the lineup
    n_priorpa_thisgame_pitcher INT,        -- prior PAs this batter has seen this pitcher today
    pitcher_days_since_prev_game INT,      -- rest days for pitcher
    batter_days_since_prev_game INT,       -- rest days for batter

    -- Audit / load metadata
    row_hash BYTEA,
    raw_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT raw_statcast_pitch_business_key_unique
        UNIQUE (statcast_search_file_id, game_pk, at_bat_number, pitch_number)
);

COMMENT ON TABLE raw_statcast.pitch IS
    'Raw Statcast pitch-level rows modeled from Baseball Savant CSV documentation and pybaseball extraction behavior. '
    'Captures all available columns including 2024+ bat tracking fields (bat_speed, swing_length), '
    'API-derived break metrics, expected outcome stats, and pitcher/batter context columns.';

COMMENT ON COLUMN raw_statcast.pitch.game_id IS
    'Retrosheet-style game identifier (e.g. TEX202304060) for cross-source joining with raw_retrosheet and raw_chadwick.';
COMMENT ON COLUMN raw_statcast.pitch.bat_speed IS
    'Bat speed at contact in mph. Available from Baseball Savant 2024 season onward.';
COMMENT ON COLUMN raw_statcast.pitch.swing_length IS
    'Swing path length in feet. Available from Baseball Savant 2024 season onward.';
COMMENT ON COLUMN raw_statcast.pitch.arm_angle IS
    'Pitcher arm slot angle at release point in degrees.';
COMMENT ON COLUMN raw_statcast.pitch.hyper_speed IS
    'Baserunner sprint speed on batted ball events (Statcast Hyper Speed metric).';
COMMENT ON COLUMN raw_statcast.pitch.home_score_ct IS
    'Home team score at the moment the pitch is thrown, as opposed to post_home_score which reflects the PA outcome.';
COMMENT ON COLUMN raw_statcast.pitch.away_score_ct IS
    'Away team score at the moment the pitch is thrown.';
COMMENT ON COLUMN raw_statcast.pitch.delta_pitcher_run_exp IS
    'Pitcher-side run expectancy delta for the pitch event.';
COMMENT ON COLUMN raw_statcast.pitch.estimated_slg_using_speedangle IS
    'Expected SLG (xSLG) derived from launch speed and launch angle.';
COMMENT ON COLUMN raw_statcast.pitch.n_thruorder_pitcher IS
    'Number of times the pitcher has worked through the batting order in this game at this point.';
COMMENT ON COLUMN raw_statcast.pitch.n_priorpa_thisgame_pitcher IS
    'Number of prior plate appearances this batter has had against this pitcher in the current game.';
COMMENT ON COLUMN raw_statcast.pitch.pitcher_days_since_prev_game IS
    'Number of days since the pitcher last appeared in a game.';
COMMENT ON COLUMN raw_statcast.pitch.batter_days_since_prev_game IS
    'Number of days since the batter last appeared in a game.';
COMMENT ON COLUMN raw_statcast.pitch.api_break_z_with_gravity IS
    'Vertical pitch break in inches including gravity effect, as reported by the Statcast API.';
COMMENT ON COLUMN raw_statcast.pitch.api_break_x_arm IS
    'Horizontal pitch break in inches from the arm-side perspective.';
COMMENT ON COLUMN raw_statcast.pitch.api_break_x_batter_in IS
    'Horizontal pitch break in inches from the batter-in perspective.';

CREATE TABLE IF NOT EXISTS raw_statcast.lookup_observation (
    raw_statcast_lookup_observation_id BIGSERIAL PRIMARY KEY,
    statcast_search_file_id UUID NOT NULL
        REFERENCES raw_statcast.search_file(statcast_search_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    lookup_type TEXT NOT NULL,
    lookup_code TEXT NOT NULL,
    lookup_value TEXT,
    observed_count BIGINT NOT NULL DEFAULT 1,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_statcast_lookup_unique
        UNIQUE (statcast_search_file_id, lookup_type, lookup_code, lookup_value)
);

COMMENT ON TABLE raw_statcast.lookup_observation IS
    'Observed lookup-like codes from Statcast rows, useful for downstream reference table generation and validation.';

COMMIT;
