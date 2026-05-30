-- ===========================================================================
-- MLB API Team and League Stats (standings, team_stats, league_stats)
--
-- Adds tables for MLB API team statistics from pybaseball functions:
-- standings(), team_batting(), team_pitching(), league_batting_stats(),
-- league_pitching_stats(), team_results()
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- raw_mlbapi.standings - Division/League standings
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_mlbapi.standings (
    raw_mlbapi_standings_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INTEGER NOT NULL,
    league_id INTEGER,
    league_name TEXT,
    division_id TEXT,
    division_name TEXT,
    team_id BIGINT NOT NULL,
    team_abbr TEXT,
    team_name TEXT,
    wins INTEGER,
    losses INTEGER,
    pct DECIMAL(5,3),
    gb DECIMAL(5,1),
    elim_num INTEGER,
    wild_card_rank INTEGER,
    div_ranking INTEGER,
    magic_num INTEGER,
    -- Streak info
    streak_label TEXT,
    streak_count INTEGER,
    -- Home/Away splits
    home_w INTEGER,
    home_l INTEGER,
    away_w INTEGER,
    away_l INTEGER,
    -- Last 10 games
    last_10_w INTEGER,
    last_10_l INTEGER,
    raw_standings_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_standings_unique
        UNIQUE (mlbapi_payload_id, season, team_id)
);

COMMENT ON TABLE raw_mlbapi.standings IS
    'Division and league standings from standings() endpoint.';

COMMENT ON COLUMN raw_mlbapi.standings.gb IS
    'Games behind the division leader.';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.team_batting_stats - Team batting aggregate stats
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_mlbapi.team_batting_stats (
    raw_mlbapi_team_batting_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INTEGER NOT NULL,
    team_id BIGINT NOT NULL,
    team_abbr TEXT,
    team_name TEXT,
    -- Counting stats
    g INTEGER,
    ab INTEGER,
    r INTEGER,
    h INTEGER,
    x2b INTEGER,
    x3b INTEGER,
    hr INTEGER,
    rbi INTEGER,
    sb INTEGER,
    cs INTEGER,
    bb INTEGER,
    so INTEGER,
    hbp INTEGER,
    sf INTEGER,
    sh INTEGER,
    gidp INTEGER,
    -- Rate stats
    avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    -- Team-level advanced
    woba NUMERIC(8,5),
    wrc_plus INTEGER,
    -- Situational
    home_ab INTEGER,
    home_r INTEGER,
    away_ab INTEGER,
    away_r INTEGER,
    raw_stats_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_team_batting_unique
        UNIQUE (mlbapi_payload_id, season, team_id)
);

COMMENT ON TABLE raw_mlbapi.team_batting_stats IS
    'Team batting statistics aggregate from team_batting() - one row per team per season.';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.team_pitching_stats - Team pitching aggregate stats
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_mlbapi.team_pitching_stats (
    raw_mlbapi_team_pitching_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INTEGER NOT NULL,
    team_id BIGINT NOT NULL,
    team_abbr TEXT,
    team_name TEXT,
    -- Counting stats
    g INTEGER,
    gs INTEGER,
    gf INTEGER,
    cg INTEGER,
    sho INTEGER,
    sv INTEGER,
    ip_outs INTEGER,
    h INTEGER,
    r INTEGER,
    er INTEGER,
    x2b INTEGER,
    x3b INTEGER,
    hr INTEGER,
    bb INTEGER,
    so INTEGER,
    hbp INTEGER,
    wp INTEGER,
    bk INTEGER,
    -- Rate stats
    era NUMERIC(8,3),
    fip NUMERIC(8,3),
    whip NUMERIC(8,3),
    -- Team-level advanced
    fip_minus INTEGER,
    xera NUMERIC(8,3),
    -- Quality of contact allowed
    hard_hit_pct NUMERIC(8,5),
    barrel_pct NUMERIC(8,5),
    raw_stats_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_team_pitching_unique
        UNIQUE (mlbapi_payload_id, season, team_id)
);

COMMENT ON TABLE raw_mlbapi.team_pitching_stats IS
    'Team pitching statistics aggregate from team_pitching() - one row per team per season.';

COMMENT ON COLUMN raw_mlbapi.team_pitching_stats.fip_minus IS
    'FIP adjusted to league context (100 is average).';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.league_stats - League aggregate stats
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_mlbapi.league_stats (
    raw_mlbapi_league_stats_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INTEGER NOT NULL,
    stat_type TEXT NOT NULL CHECK (stat_type IN ('batting', 'pitching', 'fielding')),
    league TEXT,
    -- Counting stats (batting)
    ab INTEGER,
    r INTEGER,
    h INTEGER,
    x2b INTEGER,
    x3b INTEGER,
    hr INTEGER,
    bb INTEGER,
    so INTEGER,
    sb INTEGER,
    cs INTEGER,
    hbp INTEGER,
    sf INTEGER,
    -- Rate stats (batting)
    avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    -- Pitching stats
    ip_outs INTEGER,
    er INTEGER,
    wp INTEGER,
    bk INTEGER,
    era NUMERIC(8,3),
    -- Context
    park_factor NUMERIC(8,3),
    raw_stats_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_league_stats_unique
        UNIQUE (mlbapi_payload_id, season, stat_type, league)
);

COMMENT ON TABLE raw_mlbapi.league_stats IS
    'League-wide aggregate statistics from league_batting_stats() and league_pitching_stats().';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.team_results - Seasonal team results from team_results()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_mlbapi.team_results (
    raw_mlbapi_team_results_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INTEGER NOT NULL,
    team_id BIGINT NOT NULL,
    team_abbr TEXT,
    team_name TEXT,
    w INTEGER,
    l INTEGER,
    pct DECIMAL(5,3),
    division_winner BOOLEAN,
    wild_card BOOLEAN,
    league_champ BOOLEAN,
    world_series_champ BOOLEAN,
    -- Playoff details
    playoff_seed INTEGER,
    playoff_round TEXT,
    raw_results_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_team_results_unique
        UNIQUE (mlbapi_payload_id, season, team_id)
);

COMMENT ON TABLE raw_mlbapi.team_results IS
    'Team seasonal results and playoff outcomes from team_results().';


-- ---------------------------------------------------------------------------
-- raw_mlbapi.amateur_draft - Draft results from amateur_draft()
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw_mlbapi.amateur_draft (
    raw_mlbapi_draft_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    draft_year INTEGER NOT NULL,
    round_number INTEGER,
    pick_number INTEGER,
    overall_pick INTEGER,
    team_id BIGINT,
    team_abbr TEXT,
    team_name TEXT,
    player_id BIGINT,
    player_full_name TEXT,
    player_first_name TEXT,
    player_last_name TEXT,
    primary_position TEXT,
    bats TEXT,
    throws TEXT,
    -- Draft details
    bonus_money BIGINT,
    signing_status TEXT,
    -- College/school
    school_name TEXT,
    school_type TEXT,
    state_province TEXT,
    country TEXT,
    raw_draft_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_mlbapi_amateur_draft_unique
        UNIQUE (mlbapi_payload_id, draft_year, overall_pick, team_id)
);

COMMENT ON TABLE raw_mlbapi.amateur_draft IS
    'Amateur draft results from amateur_draft() - includes bonus, signing info, and school details.';

COMMENT ON COLUMN raw_mlbapi.amateur_draft.signing_status IS
    'Signing status: Signed, Unsigned, Unsigned-Pick, etc.';


COMMIT;