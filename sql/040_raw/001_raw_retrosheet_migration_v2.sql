BEGIN;

-- ===========================================================================
-- Batting stats from Retrosheet CSV package
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.batting (
    batting_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    team_id CHAR(3),
    stat_type TEXT,
    pa INTEGER,
    ab INTEGER,
    r INTEGER,
    h INTEGER,
    d INTEGER,
    t INTEGER,
    hr INTEGER,
    rbi INTEGER,
    sh INTEGER,
    sf INTEGER,
    hbp INTEGER,
    bb INTEGER,
    iw INTEGER,
    k INTEGER,
    sb INTEGER,
    cs INTEGER,
    gdp INTEGER,
    xi INTEGER,
    roe INTEGER,
    dh_fl BOOLEAN,
    ph_fl BOOLEAN,
    pr_fl BOOLEAN,
    game_date DATE,
    game_num SMALLINT,
    site TEXT,
    vishome TEXT,
    opp TEXT,
    win INTEGER,
    loss INTEGER,
    tie INTEGER,
    gametype TEXT,
    raw_batting_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.batting IS
    'Batting statistics from Retrosheet CSV package (batting.csv).';

-- ===========================================================================
-- Pitching stats from Retrosheet CSV package
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.pitching (
    pitching_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    team_id CHAR(3),
    stat_type TEXT,
    ipouts INTEGER,
    noout INTEGER,
    bfp INTEGER,
    h INTEGER,
    d INTEGER,
    t INTEGER,
    hr INTEGER,
    r INTEGER,
    er INTEGER,
    w INTEGER,
    iw INTEGER,
    k INTEGER,
    hbp INTEGER,
    wp INTEGER,
    bk INTEGER,
    sh INTEGER,
    sf INTEGER,
    sb INTEGER,
    cs INTEGER,
    pb INTEGER,
    gs INTEGER,
    gf INTEGER,
    cg INTEGER,
    game_date DATE,
    game_num SMALLINT,
    site TEXT,
    vishome TEXT,
    opp TEXT,
    win INTEGER,
    loss INTEGER,
    tie INTEGER,
    gametype TEXT,
    raw_pitching_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.pitching IS
    'Pitching statistics from Retrosheet CSV package (pitching.csv).';

-- ===========================================================================
-- Fielding stats from Retrosheet CSV package
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.fielding (
    fielding_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    team_id CHAR(3),
    stat_type TEXT,
    seq INTEGER,
    pos TEXT,
    ifouts INTEGER,
    po INTEGER,
    a INTEGER,
    e INTEGER,
    dp INTEGER,
    tp INTEGER,
    pb INTEGER,
    wp INTEGER,
    sb INTEGER,
    cs INTEGER,
    gs INTEGER,
    game_date DATE,
    game_num SMALLINT,
    site TEXT,
    vishome TEXT,
    opp TEXT,
    win INTEGER,
    loss INTEGER,
    tie INTEGER,
    gametype TEXT,
    raw_fielding_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.fielding IS
    'Fielding statistics from Retrosheet CSV package (fielding.csv).';

-- ===========================================================================
-- Team stats from Retrosheet CSV package
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.teamstats (
    teamstat_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    team_id CHAR(3),
    stat_type TEXT,
    pa INTEGER,
    ab INTEGER,
    r INTEGER,
    h INTEGER,
    d INTEGER,
    t INTEGER,
    hr INTEGER,
    rbi INTEGER,
    sh INTEGER,
    sf INTEGER,
    hbp INTEGER,
    bb INTEGER,
    k INTEGER,
    sb INTEGER,
    cs INTEGER,
    dp INTEGER,
    tp INTEGER,
    raw_teamstat_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.teamstats IS
    'Team statistics from Retrosheet CSV package (teamstats.csv).';

-- ===========================================================================
-- Ejections from Retrosheet CSV package
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.ejections (
    ejection_id BIGSERIAL PRIMARY KEY,
    game_id TEXT,
    date DATE,
    team TEXT,
    player_id TEXT,
    player_name TEXT,
    umpire_id TEXT,
    umpire_name TEXT,
    eject_time TEXT,
    reason TEXT,
    raw_ejection_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.ejections IS
    'Ejection records from Retrosheet CSV package (ejections.csv).';

-- ===========================================================================
-- Discrepancies from Retrosheet CSV package
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.discreps (
    discrep_id BIGSERIAL PRIMARY KEY,
    player_id TEXT,
    year INTEGER,
    team TEXT,
    type TEXT,
    pos TEXT,
    cat TEXT,
    game TEXT,
    retro TEXT,
    official TEXT,
    cross TEXT,
    code TEXT,
    x TEXT,
    notes TEXT,
    accepted TEXT,
    raw_discrep_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.discreps IS
    'Discrepancy records from Retrosheet CSV package (discreps.csv).';

COMMIT;