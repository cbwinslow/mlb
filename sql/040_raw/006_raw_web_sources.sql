BEGIN;

-- ===========================================================================
-- raw_fangraphs — FanGraphs leaderboard data via pybaseball / direct scrape
-- ===========================================================================

-- Request metadata (preserved from original)
CREATE TABLE IF NOT EXISTS raw_fangraphs.request (
    raw_fangraphs_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

COMMENT ON TABLE raw_fangraphs.request IS
    'Metadata for each FanGraphs HTTP request or pybaseball call. Parent record for all typed stat rows.';

-- Raw blob payload (preserved from original)
CREATE TABLE IF NOT EXISTS raw_fangraphs.payload (
    raw_fangraphs_payload_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID NOT NULL
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    leaderboard_name TEXT,
    stat_group TEXT,
    season INT,
    split_code TEXT,
    page_number INT,
    payload_json JSONB,
    payload_html TEXT,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_fangraphs.payload IS
    'Raw FanGraphs leaderboard or split payloads, usually driven by pybaseball-style parameterization. '
    'Blob store — typed stat tables below hold the parsed/columnar form.';

-- ---------------------------------------------------------------------------
-- FanGraphs Batting — Standard (slash line, counting stats)
-- Mirrors pybaseball batting_stats() / batting_stats_range() output
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.batting_standard (
    raw_fg_batting_standard_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,           -- FanGraphs player ID
    name TEXT,
    team TEXT,
    age INT,
    g INT,
    ab INT,
    pa INT,
    h INT,
    x1b INT,
    x2b INT,
    x3b INT,
    hr INT,
    r INT,
    rbi INT,
    bb INT,
    ibb INT,
    so INT,
    hbp INT,
    sf INT,
    sh INT,
    gdp INT,
    sb INT,
    cs INT,
    avg NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_batting_standard_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.batting_standard IS
    'Raw FanGraphs standard batting leaderboard. Counting stats and slash line by player-season-team.';

-- ---------------------------------------------------------------------------
-- FanGraphs Batting — Advanced (plate discipline, contact rates, value)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.batting_advanced (
    raw_fg_batting_advanced_id BIGSERIAL PRIMARY KEY,
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
    bb_pct NUMERIC(8,5),              -- walk rate
    k_pct NUMERIC(8,5),               -- strikeout rate
    bb_k NUMERIC(8,5),                -- BB/K ratio
    obp NUMERIC(8,5),
    iso NUMERIC(8,5),
    babip NUMERIC(8,5),
    woba NUMERIC(8,5),
    wrc_plus INT,
    wraa NUMERIC(10,3),
    wrc NUMERIC(10,3),
    war NUMERIC(8,2),
    off NUMERIC(8,2),                 -- offensive WAR component
    def NUMERIC(8,2),                 -- defensive WAR component
    spd NUMERIC(8,2),                 -- speed score
    ubr NUMERIC(8,2),                 -- ultimate base running
    wgdp NUMERIC(8,2),                -- GIDP runs above average
    wsbr NUMERIC(8,2),               -- stolen base runs above average
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_batting_advanced_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.batting_advanced IS
    'Raw FanGraphs advanced batting leaderboard. Plate discipline, contact rates, wOBA, wRC+, and WAR components.';

-- ---------------------------------------------------------------------------
-- FanGraphs Batting — Statcast (expected stats, bat tracking, sprint speed)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.batting_statcast (
    raw_fg_batting_statcast_id BIGSERIAL PRIMARY KEY,
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
    avg_exit_velo NUMERIC(8,3),
    max_exit_velo NUMERIC(8,3),
    avg_launch_angle NUMERIC(8,3),
    barrel_pct NUMERIC(8,5),
    hard_hit_pct NUMERIC(8,5),
    xba NUMERIC(8,5),
    xobp NUMERIC(8,5),
    xslg NUMERIC(8,5),
    xwoba NUMERIC(8,5),
    xwobacon NUMERIC(8,5),
    sprint_speed NUMERIC(8,3),        -- Statcast sprint speed ft/s
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_batting_statcast_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.batting_statcast IS
    'Raw FanGraphs Statcast batting leaderboard. Exit velocity, barrel rate, expected stats, and sprint speed.';

-- ---------------------------------------------------------------------------
-- FanGraphs Pitching — Standard
-- Mirrors pybaseball pitching_stats() output
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.pitching_standard (
    raw_fg_pitching_standard_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    age INT,
    w INT,
    l INT,
    era NUMERIC(8,3),
    g INT,
    gs INT,
    cg INT,
    sho INT,
    sv INT,
    hld INT,
    bs INT,
    ip NUMERIC(8,1),
    tbf INT,
    h INT,
    r INT,
    er INT,
    hr INT,
    bb INT,
    ibb INT,
    hbp INT,
    wp INT,
    bk INT,
    so INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_pitching_standard_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.pitching_standard IS
    'Raw FanGraphs standard pitching leaderboard. Counting stats and ERA by pitcher-season-team.';

-- ---------------------------------------------------------------------------
-- FanGraphs Pitching — Advanced (peripheral stats, value metrics)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.pitching_advanced (
    raw_fg_pitching_advanced_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    age INT,
    ip NUMERIC(8,1),
    k_per_9 NUMERIC(8,3),
    bb_per_9 NUMERIC(8,3),
    k_bb NUMERIC(8,3),
    h_per_9 NUMERIC(8,3),
    hr_per_9 NUMERIC(8,3),
    k_pct NUMERIC(8,5),
    bb_pct NUMERIC(8,5),
    k_bb_pct NUMERIC(8,5),
    hr_fb NUMERIC(8,5),               -- HR/FB ratio
    lob_pct NUMERIC(8,5),             -- left on base %
    gb_pct NUMERIC(8,5),              -- ground ball %
    fb_pct NUMERIC(8,5),              -- fly ball %
    ld_pct NUMERIC(8,5),              -- line drive %
    iffb_pct NUMERIC(8,5),            -- infield fly ball %
    babip NUMERIC(8,5),
    era_minus INT,                    -- ERA- (park/league adjusted)
    fip NUMERIC(8,3),
    xfip NUMERIC(8,3),
    siera NUMERIC(8,3),
    war NUMERIC(8,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_pitching_advanced_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.pitching_advanced IS
    'Raw FanGraphs advanced pitching leaderboard. Peripheral rates, FIP, xFIP, SIERA, and WAR.';

-- ---------------------------------------------------------------------------
-- FanGraphs Pitching — Statcast (velocity, movement, expected stats)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.pitching_statcast (
    raw_fg_pitching_statcast_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    age INT,
    ip NUMERIC(8,1),
    avg_fastball_velo NUMERIC(8,3),
    avg_exit_velo_against NUMERIC(8,3),
    barrel_pct_against NUMERIC(8,5),
    hard_hit_pct_against NUMERIC(8,5),
    xera NUMERIC(8,3),
    xfip_minus INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_pitching_statcast_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.pitching_statcast IS
    'Raw FanGraphs Statcast pitching leaderboard. Velocity, barrel rate against, and expected ERA metrics.';

-- ---------------------------------------------------------------------------
-- FanGraphs Fielding — Standard (UZR, OAA, DRS components)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.fielding_standard (
    raw_fg_fielding_standard_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    pos TEXT NOT NULL,
    age INT,
    g INT,
    gs INT,
    inn NUMERIC(10,1),
    po INT,
    a INT,
    e INT,
    dp INT,
    fpct NUMERIC(8,5),
    uzr NUMERIC(8,2),                 -- ultimate zone rating
    uzr_150 NUMERIC(8,2),             -- UZR per 150 games
    oaa INT,                          -- outs above average (Statcast)
    drs INT,                          -- defensive runs saved
    rngr NUMERIC(8,2),                -- range runs (UZR component)
    errr NUMERIC(8,2),                -- error runs (UZR component)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_fielding_standard_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team, pos)
);

COMMENT ON TABLE raw_fangraphs.fielding_standard IS
    'Raw FanGraphs fielding leaderboard. UZR, OAA, DRS, and fielding percentage by player-position-season.';

-- ---------------------------------------------------------------------------
-- FanGraphs Sprint Speed (Statcast-sourced via FanGraphs leaderboard)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.sprint_speed (
    raw_fg_sprint_speed_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    playerid TEXT NOT NULL,
    name TEXT,
    team TEXT,
    age INT,
    sprint_speed NUMERIC(8,3),        -- ft/s
    hp_to_1b NUMERIC(8,3),            -- home to first time (seconds)
    competitive_runs INT,             -- number of competitive sprints sampled
    percentile INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_sprint_speed_unique
        UNIQUE (raw_fangraphs_request_id, season, playerid, team)
);

COMMENT ON TABLE raw_fangraphs.sprint_speed IS
    'Raw FanGraphs sprint speed leaderboard sourced from Statcast. Speed in ft/s, home-to-first, and percentile.';

-- ---------------------------------------------------------------------------
-- FanGraphs Park Factors
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_fangraphs.park_factors (
    raw_fg_park_factors_id BIGSERIAL PRIMARY KEY,
    raw_fangraphs_request_id UUID
        REFERENCES raw_fangraphs.request(raw_fangraphs_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    team TEXT NOT NULL,
    basic_5yr INT,                    -- 5-year basic park factor (100 = neutral)
    single_factor INT,
    double_factor INT,
    triple_factor INT,
    hr_factor INT,
    so_factor INT,
    ubbhbp_factor INT,
    gb_factor INT,
    fb_factor INT,
    ld_factor INT,
    rhb_basic INT,                    -- right-hand batter park factor
    lhb_basic INT,                    -- left-hand batter park factor
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_fg_park_factors_unique
        UNIQUE (raw_fangraphs_request_id, season, team)
);

COMMENT ON TABLE raw_fangraphs.park_factors IS
    'Raw FanGraphs park factors by team and season. 100 = perfectly neutral park.';


-- ===========================================================================
-- raw_bref — Baseball Reference data via pybaseball / direct HTML scrape
-- ===========================================================================

-- Request metadata (preserved from original)
CREATE TABLE IF NOT EXISTS raw_bref.request (
    raw_bref_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

COMMENT ON TABLE raw_bref.request IS
    'Metadata for each Baseball Reference HTTP request. Parent record for all typed stat rows.';

-- Raw blob page (preserved from original)
CREATE TABLE IF NOT EXISTS raw_bref.page (
    raw_bref_page_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID NOT NULL
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    page_type TEXT NOT NULL,
    entity_key TEXT,
    season INT,
    table_id TEXT,
    payload_html TEXT,
    payload_json JSONB,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_bref.page IS
    'Raw Baseball Reference page captures; useful because page/table structures can vary by entity type. '
    'Blob store — typed stat tables below hold the parsed/columnar form.';

-- ---------------------------------------------------------------------------
-- BBRef Batting — Standard
-- Mirrors pybaseball bref_team_batting_summaries() / player pages
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bref.batting_standard (
    raw_bref_batting_standard_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    bbref_id TEXT NOT NULL,           -- Baseball Reference player ID
    name TEXT,
    team TEXT,
    lg TEXT,
    age INT,
    g INT,
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
    ops_plus INT,                     -- OPS+ (park/league adjusted, 100 = average)
    tb INT,
    gdp INT,
    hbp INT,
    sh INT,
    sf INT,
    ibb INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_batting_standard_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, team)
);

COMMENT ON TABLE raw_bref.batting_standard IS
    'Raw Baseball Reference standard batting table. Full counting stats, slash line, and OPS+ by player-season-team.';

-- ---------------------------------------------------------------------------
-- BBRef Batting — Value (WAR components)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bref.batting_value (
    raw_bref_batting_value_id BIGSERIAL PRIMARY KEY,
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
    pa INT,
    rbat NUMERIC(8,2),                -- runs batting
    rbaser NUMERIC(8,2),              -- runs baserunning
    rdp NUMERIC(8,2),                 -- runs double plays
    rfield NUMERIC(8,2),              -- runs fielding
    rpos NUMERIC(8,2),                -- runs positional adjustment
    rlev NUMERIC(8,2),                -- runs leverage index
    rwaa NUMERIC(8,2),                -- runs wins above average
    off NUMERIC(8,2),                 -- offensive WAR
    def NUMERIC(8,2),                 -- defensive WAR
    war NUMERIC(8,2),                 -- total rWAR
    war162 NUMERIC(8,2),              -- WAR per 162 games
    owar NUMERIC(8,2),                -- offensive WAR
    dwar NUMERIC(8,2),                -- defensive WAR
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_batting_value_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, team)
);

COMMENT ON TABLE raw_bref.batting_value IS
    'Raw Baseball Reference batting value/WAR table. rWAR components including rbat, rfield, rpos, and total WAR.';

-- ---------------------------------------------------------------------------
-- BBRef Pitching — Standard
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bref.pitching_standard (
    raw_bref_pitching_standard_id BIGSERIAL PRIMARY KEY,
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
    w INT,
    l INT,
    win_loss_pct NUMERIC(8,5),
    era NUMERIC(8,3),
    era_plus INT,                     -- ERA+ (park/league adjusted, 100 = average)
    g INT,
    gs INT,
    gf INT,
    cg INT,
    sho INT,
    sv INT,
    ip NUMERIC(8,1),
    h INT,
    r INT,
    er INT,
    hr INT,
    bb INT,
    ibb INT,
    so INT,
    hbp INT,
    bk INT,
    wp INT,
    bf INT,
    fip NUMERIC(8,3),
    whip NUMERIC(8,3),
    h9 NUMERIC(8,3),
    hr9 NUMERIC(8,3),
    bb9 NUMERIC(8,3),
    so9 NUMERIC(8,3),
    so_bb NUMERIC(8,3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_pitching_standard_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, team)
);

COMMENT ON TABLE raw_bref.pitching_standard IS
    'Raw Baseball Reference standard pitching table. Counting stats, ERA+, FIP, and rate stats by pitcher-season-team.';

-- ---------------------------------------------------------------------------
-- BBRef Pitching — Value (WAR components)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bref.pitching_value (
    raw_bref_pitching_value_id BIGSERIAL PRIMARY KEY,
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
    ip NUMERIC(8,1),
    rpitch NUMERIC(8,2),              -- runs allowed component
    rdef NUMERIC(8,2),                -- runs defense
    rpos NUMERIC(8,2),                -- positional adjustment
    rgdp NUMERIC(8,2),                -- GIDP component
    rpct NUMERIC(8,2),                -- holds/saves component
    rlev NUMERIC(8,2),                -- leverage component
    rwaa NUMERIC(8,2),                -- runs WAA
    waa NUMERIC(8,2),                 -- wins above average
    war NUMERIC(8,2),                 -- total rWAR (pitching)
    war162 NUMERIC(8,2),              -- WAR per 162 team games
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_pitching_value_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, team)
);

COMMENT ON TABLE raw_bref.pitching_value IS
    'Raw Baseball Reference pitching value/WAR table. rWAR components for pitchers including leverage and holds.';

-- ---------------------------------------------------------------------------
-- BBRef Fielding — Standard
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bref.fielding_standard (
    raw_bref_fielding_standard_id BIGSERIAL PRIMARY KEY,
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
    pos TEXT NOT NULL,
    g INT,
    gs INT,
    inn NUMERIC(10,1),
    po INT,
    a INT,
    e INT,
    dp INT,
    pb INT,                           -- passed balls (catchers only)
    wp INT,                           -- wild pitches (catchers only)
    sb_against INT,                   -- SB allowed (catchers only)
    cs_against INT,                   -- CS (catchers only)
    cs_pct NUMERIC(8,5),              -- caught stealing % (catchers only)
    fpct NUMERIC(8,5),
    rf_g NUMERIC(8,3),                -- range factor per game
    rf_9 NUMERIC(8,3),                -- range factor per 9 innings
    drs INT,                          -- defensive runs saved (if available)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_fielding_standard_unique
        UNIQUE (raw_bref_request_id, season, bbref_id, team, pos)
);

COMMENT ON TABLE raw_bref.fielding_standard IS
    'Raw Baseball Reference fielding table. Traditional fielding stats, range factor, and DRS by player-position-season.';

-- ---------------------------------------------------------------------------
-- BBRef Team Standard (season-level team stats)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bref.team_standard (
    raw_bref_team_standard_id BIGSERIAL PRIMARY KEY,
    raw_bref_request_id UUID
        REFERENCES raw_bref.request(raw_bref_request_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT NOT NULL,
    team TEXT NOT NULL,
    lg TEXT,
    g INT,
    w INT,
    l INT,
    win_loss_pct NUMERIC(8,5),
    rank INT,
    gb NUMERIC(8,1),                  -- games behind division leader
    r INT,
    ra INT,
    rd INT,                           -- run differential
    avg_age NUMERIC(5,2),
    ba NUMERIC(8,5),
    obp NUMERIC(8,5),
    slg NUMERIC(8,5),
    ops NUMERIC(8,5),
    era NUMERIC(8,3),
    era_plus INT,
    fip NUMERIC(8,3),
    whip NUMERIC(8,3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_bref_team_standard_unique
        UNIQUE (raw_bref_request_id, season, team)
);

COMMENT ON TABLE raw_bref.team_standard IS
    'Raw Baseball Reference team season summary. Standings, run differential, and aggregate batting/pitching rates.';


-- ===========================================================================
-- raw_espn — ESPN page/API captures (preserved from original)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_espn.request (
    raw_espn_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

COMMENT ON TABLE raw_espn.request IS
    'Metadata for each ESPN HTTP request.';

CREATE TABLE IF NOT EXISTS raw_espn.page (
    raw_espn_page_id BIGSERIAL PRIMARY KEY,
    raw_espn_request_id UUID NOT NULL
        REFERENCES raw_espn.request(raw_espn_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    page_type TEXT NOT NULL,
    entity_key TEXT,
    season INT,
    payload_html TEXT,
    payload_json JSONB,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_espn.page IS
    'Raw ESPN page/API captures for standings, schedules, injuries, and matchup context when needed.';


-- ===========================================================================
-- raw_odds — Odds provider payloads (preserved from original)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_odds.provider_request (
    raw_odds_provider_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    provider_code TEXT NOT NULL,
    request_url TEXT NOT NULL,
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_hash BYTEA,
    payload_size_bytes BIGINT
);

COMMENT ON TABLE raw_odds.provider_request IS
    'Metadata for each odds provider HTTP request.';

CREATE TABLE IF NOT EXISTS raw_odds.provider_payload (
    raw_odds_provider_payload_id BIGSERIAL PRIMARY KEY,
    raw_odds_provider_request_id UUID NOT NULL
        REFERENCES raw_odds.provider_request(raw_odds_provider_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    provider_code TEXT NOT NULL,
    endpoint_code TEXT NOT NULL,
    sport_key TEXT,
    event_key TEXT,
    market_key TEXT,
    bookmaker_key TEXT,
    payload_json JSONB NOT NULL,
    natural_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_odds.provider_payload IS
    'Raw odds-provider payloads; keep provider-specific structures intact before conformance.';

COMMIT;
