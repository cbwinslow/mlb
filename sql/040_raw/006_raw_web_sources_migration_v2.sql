BEGIN;

-- ===========================================================================
-- FanGraphs Split Tables (batter_splits, pitcher_splits)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_fangraphs.batter_splits (
    raw_fg_batter_splits_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    split_code TEXT NOT NULL,
    split_name TEXT,
    pa INT,
    ab INT,
    h INT,
    x2b INT,
    x3b INT,
    hr INT,
    r INT,
    rbi INT,
    bb INT,
    so INT,
    avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    woba NUMERIC(8,5),
    wrc_plus INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_batter_splits_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, split_code)
);

COMMENT ON TABLE raw_fangraphs.batter_splits IS
    'Raw FanGraphs batter splits data by situation (vs LHP, vs RHP, Home, Away, etc.).';

CREATE TABLE IF NOT EXISTS raw_fangraphs.pitcher_splits (
    raw_fg_pitcher_splits_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    split_code TEXT NOT NULL,
    split_name TEXT,
    ip NUMERIC(8,1),
    tbf INT,
    h INT,
    r INT,
    er INT,
    hr INT,
    bb INT,
    so INT,
    era NUMERIC(8,3),
    fip NUMERIC(8,3),
    woba NUMERIC(8,5),
    xwoba NUMERIC(8,5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_pitcher_splits_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, split_code)
);

COMMENT ON TABLE raw_fangraphs.pitcher_splits IS
    'Raw FanGraphs pitcher splits data by situation (vs LHB, vs RHB, Home, Away, etc.).';


-- ===========================================================================
-- FanGraphs Baserunning and Plate Discipline
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_fangraphs.baserunning (
    raw_fg_baserunning_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    age INT,
    sb INT,
    cs INT,
    sb_pct NUMERIC(8,5),
    ubr NUMERIC(8,2),
    wsb NUMERIC(8,2),
    baserunning_runs NUMERIC(8,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_baserunning_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid)
);

COMMENT ON TABLE raw_fangraphs.baserunning IS
    'Raw FanGraphs baserunning leaderboard. Stolen base success rate, UBR, and baserunning runs.';

CREATE TABLE IF NOT EXISTS raw_fangraphs.plate_discipline (
    raw_fg_plate_discipline_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    age INT,
    pa INT,
    swing_pct NUMERIC(8,5),
    chase_pct NUMERIC(8,5),
    contact_pct NUMERIC(8,5),
    zone_pct NUMERIC(8,5),
    first_pitch_swings INT,
    first_pitch_strikes INT,
    swstr_pct NUMERIC(8,5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_plate_discipline_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid)
);

COMMENT ON TABLE raw_fangraphs.plate_discipline IS
    'Raw FanGraphs plate discipline leaderboard. Swing rates, chase rate, contact rate by count.';


-- ===========================================================================
-- Baseball Reference Split Tables (batter_splits, pitcher_splits)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_bref.batter_splits (
    raw_bref_batter_splits_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    bbref_id TEXT NOT NULL,
    name TEXT,
    team TEXT,
    lg TEXT,
    split_code TEXT NOT NULL,
    split_name TEXT,
    pa INT,
    ab INT,
    r INT,
    h INT,
    x2b INT,
    x3b INT,
    hr INT,
    rbi INT,
    sb INT,
    cs INT,
    bb INT,
    so INT,
    batting_avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_batter_splits_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, split_code)
);

COMMENT ON TABLE raw_bref.batter_splits IS
    'Raw Baseball Reference batter splits by situation (Home, Away, vs LHP, vs RHP).';

CREATE TABLE IF NOT EXISTS raw_bref.pitcher_splits (
    raw_bref_pitcher_splits_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    bbref_id TEXT NOT NULL,
    name TEXT,
    team TEXT,
    lg TEXT,
    split_code TEXT NOT NULL,
    split_name TEXT,
    ip NUMERIC(8,1),
    w INT,
    l INT,
    era NUMERIC(8,3),
    bf INT,
    h INT,
    r INT,
    er INT,
    hr INT,
    bb INT,
    so INT,
    whip NUMERIC(8,3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_pitcher_splits_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, split_code)
);

COMMENT ON TABLE raw_bref.pitcher_splits IS
    'Raw Baseball Reference pitcher splits by situation (Home, Away, vs LHB, vs RHB).';


-- ===========================================================================
-- Baseball Reference Baserunning and Win Probability
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_bref.baserunning (
    raw_bref_baserunning_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    bbref_id TEXT NOT NULL,
    name TEXT,
    team TEXT,
    lg TEXT,
    age INT,
    g INT,
    sb INT,
    cs INT,
    sb_pct NUMERIC(8,5),
    pb INT,
    wp INT,
    zr INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_baserunning_unique
        UNIQUE (raw_bref_request_id, season, bbref_id)
);

COMMENT ON TABLE raw_bref.baserunning IS
    'Raw Baseball Reference baserunning stats. Stolen bases, caught stealing, and defensive indifference.';

CREATE TABLE IF NOT EXISTS raw_bref.win_probability (
    raw_bref_win_probability_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    bbref_id TEXT NOT NULL,
    name TEXT,
    team TEXT,
    lg TEXT,
    age INT,
    wpa NUMERIC(8,3),
    wpa_minus NUMERIC(8,3),
    wpa_plus NUMERIC(8,3),
    re24 NUMERIC(8,3),
    clutch NUMERIC(8,3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_win_probability_unique
        UNIQUE (raw_bref_request_id, season, bbref_id)
);

COMMENT ON TABLE raw_bref.win_probability IS
    'Raw Baseball Reference win probability stats. WPA, RE24, and leverage index measures.';


-- ===========================================================================
-- ESPN Typed Tables (schedule, scores)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_espn.schedule (
    raw_espn_schedule_id BIGSERIAL PRIMARY KEY,
    raw_espn_request_id UUID NOT NULL
        REFERENCES raw_espn.request(raw_espn_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INT NOT NULL,
    game_date DATE NOT NULL,
    game_pk BIGINT,
    home_team_id BIGINT,
    away_team_id BIGINT,
    venue_id BIGINT,
    game_type TEXT,
    status TEXT,
    raw_schedule_json JSONB,
    CONSTRAINT raw_espn_schedule_unique
        UNIQUE (raw_espn_request_id, game_date, home_team_id, away_team_id)
);

COMMENT ON TABLE raw_espn.schedule IS
    'Raw ESPN schedule entries extracted from schedule pages or API responses.';

CREATE TABLE IF NOT EXISTS raw_espn.scores (
    raw_espn_scores_id BIGSERIAL PRIMARY KEY,
    raw_espn_request_id UUID NOT NULL
        REFERENCES raw_espn.request(raw_espn_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_date DATE NOT NULL,
    game_pk BIGINT,
    home_team_id BIGINT,
    away_team_id BIGINT,
    home_score INT,
    away_score INT,
    status TEXT,
    quarter_scores JSONB,
    raw_scores_json JSONB,
    CONSTRAINT raw_espn_scores_unique
        UNIQUE (raw_espn_request_id, game_pk)
);

COMMENT ON TABLE raw_espn.scores IS
    'Raw ESPN scoreboard entries for completed and in-progress games.';


-- ===========================================================================
-- Odds Typed Tables (market_lines)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_odds.market_lines (
    raw_odds_market_lines_id BIGSERIAL PRIMARY KEY,
    raw_odds_provider_payload_id BIGINT NOT NULL
        REFERENCES raw_odds.provider_payload(raw_odds_provider_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    sport_key TEXT NOT NULL,
    event_key TEXT,
    market_key TEXT NOT NULL,
    bookmaker_key TEXT NOT NULL,
    outcome_key TEXT,
    outcome_name TEXT,
    outcome_price NUMERIC(12,3),
    outcome_point NUMERIC(12,3),
    market_started BOOLEAN,
    market_completed BOOLEAN,
    raw_markets_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_odds_market_lines_unique
        UNIQUE (raw_odds_provider_payload_id, market_key, bookmaker_key, outcome_key)
);

COMMENT ON TABLE raw_odds.market_lines IS
    'Typed odds market lines extracted from provider payloads for odds convergence.';

COMMIT;