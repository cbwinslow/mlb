BEGIN;

CREATE TABLE IF NOT EXISTS raw_lahman.people (
    raw_lahman_people_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    birth_year INT,
    birth_month INT,
    birth_day INT,
    birth_country TEXT,
    birth_state TEXT,
    birth_city TEXT,
    death_year INT,
    death_month INT,
    death_day INT,
    death_country TEXT,
    death_state TEXT,
    death_city TEXT,
    name_first TEXT,
    name_last TEXT,
    name_given TEXT,
    weight INT,
    height INT,
    bats TEXT,
    throws TEXT,
    debut DATE,
    final_game DATE,
    retro_id TEXT,
    bbref_id TEXT,
    birth_date DATE,
    death_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_people_player_unique
        UNIQUE (source_file_id, player_id)
);

COMMENT ON TABLE raw_lahman.people IS
    'Raw Lahman People table. One row per player across all of professional baseball history.';

-- ---------------------------------------------------------------------------
-- Batting (regular season)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.batting (
    raw_lahman_batting_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    stint INT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    g INT,
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
    ibb INT,
    hbp INT,
    sh INT,
    sf INT,
    gidp INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_batting_unique
        UNIQUE (source_file_id, player_id, year_id, stint, team_id)
);

COMMENT ON TABLE raw_lahman.batting IS
    'Raw Lahman Batting table. Regular-season batting statistics by player, year, and stint.';

-- ---------------------------------------------------------------------------
-- Pitching (regular season)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.pitching (
    raw_lahman_pitching_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    stint INT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    w INT,
    l INT,
    g INT,
    gs INT,
    cg INT,
    sho INT,
    sv INT,
    ip_outs INT,
    h INT,
    er INT,
    hr INT,
    bb INT,
    so INT,
    ba_opp NUMERIC(8,5),
    era NUMERIC(8,3),
    ibb INT,
    wp INT,
    hbp INT,
    bk INT,
    bfp INT,
    gf INT,
    r INT,
    sh INT,
    sf INT,
    gidp INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_pitching_unique
        UNIQUE (source_file_id, player_id, year_id, stint, team_id)
);

COMMENT ON TABLE raw_lahman.pitching IS
    'Raw Lahman Pitching table. Regular-season pitching statistics by player, year, and stint.';

-- ---------------------------------------------------------------------------
-- Fielding (regular season)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.fielding (
    raw_lahman_fielding_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    stint INT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    pos TEXT,
    g INT,
    gs INT,
    inn_outs INT,
    po INT,
    a INT,
    e INT,
    dp INT,
    pb INT,
    wp INT,
    sb INT,
    cs INT,
    zr NUMERIC(8,3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_fielding_unique
        UNIQUE (source_file_id, player_id, year_id, stint, team_id, pos)
);

COMMENT ON TABLE raw_lahman.fielding IS
    'Raw Lahman Fielding table. Regular-season fielding statistics by player, year, stint, and position.';

-- ---------------------------------------------------------------------------
-- Fielding by outfield position split (LF / CF / RF)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.fielding_of_split (
    raw_lahman_fielding_of_split_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    stint INT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    pos TEXT,                  -- LF, CF, or RF
    g INT,
    gs INT,
    inn_outs INT,
    po INT,
    a INT,
    e INT,
    dp INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_fielding_of_split_unique
        UNIQUE (source_file_id, player_id, year_id, stint, team_id, pos)
);

COMMENT ON TABLE raw_lahman.fielding_of_split IS
    'Raw Lahman FieldingOFsplit table. Outfield fielding statistics split by position (LF/CF/RF).';

-- ---------------------------------------------------------------------------
-- Teams
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.teams (
    raw_lahman_teams_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id INT NOT NULL,
    lg_id TEXT,
    team_id TEXT NOT NULL,
    franch_id TEXT,
    div_id TEXT,
    rank INT,
    g INT,
    g_home INT,
    w INT,
    l INT,
    div_win TEXT,
    wc_win TEXT,
    lg_win TEXT,
    ws_win TEXT,
    r INT,
    ab INT,
    h INT,
    x2b INT,
    x3b INT,
    hr INT,
    bb INT,
    so INT,
    sb INT,
    cs INT,
    hbp INT,
    sf INT,
    ra INT,
    er INT,
    era NUMERIC(8,3),
    cg INT,
    sho INT,
    sv INT,
    ip_outs INT,
    ha INT,
    hra INT,
    bba INT,
    soa INT,
    e INT,
    dp INT,
    fp NUMERIC(8,5),
    name TEXT,
    park TEXT,
    attendance BIGINT,
    bpf INT,
    ppf INT,
    team_id_br TEXT,
    team_id_lahman45 TEXT,
    team_id_retro TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_teams_unique
        UNIQUE (source_file_id, year_id, team_id)
);

COMMENT ON TABLE raw_lahman.teams IS
    'Raw Lahman Teams table. Season-level team statistics and identifiers.';

-- ---------------------------------------------------------------------------
-- Salaries
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.salaries (
    raw_lahman_salaries_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id INT NOT NULL,
    team_id TEXT NOT NULL,
    lg_id TEXT,
    player_id TEXT NOT NULL,
    salary NUMERIC(14,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_salaries_unique
        UNIQUE (source_file_id, year_id, team_id, player_id)
);

COMMENT ON TABLE raw_lahman.salaries IS
    'Raw Lahman Salaries table. Player salary by season and team. Coverage begins 1985.';

-- ---------------------------------------------------------------------------
-- Player Awards
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_players (
    raw_lahman_awards_players_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    award_id TEXT NOT NULL,
    year_id INT NOT NULL,
    lg_id TEXT,
    tie TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_awards_players_unique
        UNIQUE (source_file_id, player_id, award_id, year_id, lg_id)
);

COMMENT ON TABLE raw_lahman.awards_players IS
    'Raw Lahman AwardsPlayers table. Awards won by players (MVP, Cy Young, Gold Glove, etc.).';

-- ---------------------------------------------------------------------------
-- Manager Awards
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_managers (
    raw_lahman_awards_managers_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    award_id TEXT NOT NULL,
    year_id INT NOT NULL,
    lg_id TEXT,
    tie TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_awards_managers_unique
        UNIQUE (source_file_id, player_id, award_id, year_id, lg_id)
);

COMMENT ON TABLE raw_lahman.awards_managers IS
    'Raw Lahman AwardsManagers table. Awards won by managers (Manager of the Year, etc.).';

-- ---------------------------------------------------------------------------
-- Player Award Voting Share
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_share_players (
    raw_lahman_awards_share_players_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    award_id TEXT NOT NULL,
    year_id INT NOT NULL,
    lg_id TEXT,
    player_id TEXT NOT NULL,
    points_won NUMERIC(10,2),
    points_max NUMERIC(10,2),
    votes_first NUMERIC(10,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_awards_share_players_unique
        UNIQUE (source_file_id, award_id, year_id, lg_id, player_id)
);

COMMENT ON TABLE raw_lahman.awards_share_players IS
    'Raw Lahman AwardsSharePlayers table. Award voting totals and first-place votes by player per award year.';

-- ---------------------------------------------------------------------------
-- Manager Award Voting Share
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_share_managers (
    raw_lahman_awards_share_managers_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    award_id TEXT NOT NULL,
    year_id INT NOT NULL,
    lg_id TEXT,
    player_id TEXT NOT NULL,
    points_won NUMERIC(10,2),
    points_max NUMERIC(10,2),
    votes_first NUMERIC(10,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_awards_share_managers_unique
        UNIQUE (source_file_id, award_id, year_id, lg_id, player_id)
);

COMMENT ON TABLE raw_lahman.awards_share_managers IS
    'Raw Lahman AwardsShareManagers table. Award voting totals for managers per award year.';

-- ---------------------------------------------------------------------------
-- Hall of Fame
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.hall_of_fame (
    raw_lahman_hall_of_fame_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    voted_by TEXT NOT NULL,       -- BBWAA, Veterans, RunOff, etc.
    ballots INT,
    needed INT,
    votes INT,
    inducted TEXT,                -- Y or N
    category TEXT,                -- Player, Manager, Pioneer/Executive, Umpire
    needed_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_hall_of_fame_unique
        UNIQUE (source_file_id, player_id, year_id, voted_by)
);

COMMENT ON TABLE raw_lahman.hall_of_fame IS
    'Raw Lahman HallOfFame table. Hall of Fame ballot results by player, year, and voting body.';

-- ---------------------------------------------------------------------------
-- Schools
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.schools (
    raw_lahman_schools_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    school_id TEXT NOT NULL,
    name_full TEXT,
    city TEXT,
    state TEXT,
    country TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_schools_unique
        UNIQUE (source_file_id, school_id)
);

COMMENT ON TABLE raw_lahman.schools IS
    'Raw Lahman Schools table. College and university reference data for player college appearances.';

-- ---------------------------------------------------------------------------
-- College Playing
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.college_playing (
    raw_lahman_college_playing_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    school_id TEXT NOT NULL,
    year_id INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_college_playing_unique
        UNIQUE (source_file_id, player_id, school_id, year_id)
);

COMMENT ON TABLE raw_lahman.college_playing IS
    'Raw Lahman CollegePlaying table. Links players to their college/university by year.';

-- ---------------------------------------------------------------------------
-- Appearances (games played by position)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.appearances (
    raw_lahman_appearances_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id INT NOT NULL,
    team_id TEXT NOT NULL,
    lg_id TEXT,
    player_id TEXT NOT NULL,
    g_all INT,
    gs INT,
    g_batting INT,
    g_defense INT,
    g_p INT,
    g_c INT,
    g_1b INT,
    g_2b INT,
    g_3b INT,
    g_ss INT,
    g_lf INT,
    g_cf INT,
    g_rf INT,
    g_of INT,
    g_dh INT,
    g_ph INT,
    g_pr INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_appearances_unique
        UNIQUE (source_file_id, year_id, team_id, player_id)
);

COMMENT ON TABLE raw_lahman.appearances IS
    'Raw Lahman Appearances table. Games played by position for each player-team-season.';

-- ---------------------------------------------------------------------------
-- Managers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.managers (
    raw_lahman_managers_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    team_id TEXT NOT NULL,
    lg_id TEXT,
    inseason INT NOT NULL DEFAULT 1,    -- order of managers within a season for a team
    g INT,
    w INT,
    l INT,
    rank INT,
    plyr_mgr TEXT,                      -- Y if player-manager
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_managers_unique
        UNIQUE (source_file_id, player_id, year_id, team_id, inseason)
);

COMMENT ON TABLE raw_lahman.managers IS
    'Raw Lahman Managers table. Season win-loss records and team rank for each manager stint.';

-- ---------------------------------------------------------------------------
-- Managers Half (split-season records)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.managers_half (
    raw_lahman_managers_half_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    team_id TEXT NOT NULL,
    lg_id TEXT,
    inseason INT NOT NULL DEFAULT 1,
    half INT NOT NULL,                  -- 1 or 2
    g INT,
    w INT,
    l INT,
    rank INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_managers_half_unique
        UNIQUE (source_file_id, player_id, year_id, team_id, inseason, half)
);

COMMENT ON TABLE raw_lahman.managers_half IS
    'Raw Lahman ManagersHalf table. Split-season (first/second half) records for managers. Primarily 1981 and 1994.';

-- ---------------------------------------------------------------------------
-- Batting Postseason
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.batting_post (
    raw_lahman_batting_post_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id INT NOT NULL,
    round TEXT NOT NULL,            -- WS, ALCS, NLCS, ALDS, NLDS, ALWC, NLWC
    player_id TEXT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    g INT,
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
    ibb INT,
    hbp INT,
    sh INT,
    sf INT,
    gidp INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_batting_post_unique
        UNIQUE (source_file_id, year_id, round, player_id, team_id)
);

COMMENT ON TABLE raw_lahman.batting_post IS
    'Raw Lahman BattingPost table. Postseason batting statistics by player, year, and series round.';

-- ---------------------------------------------------------------------------
-- Pitching Postseason
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.pitching_post (
    raw_lahman_pitching_post_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    round TEXT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    w INT,
    l INT,
    g INT,
    gs INT,
    cg INT,
    sho INT,
    sv INT,
    ip_outs INT,
    h INT,
    er INT,
    hr INT,
    bb INT,
    so INT,
    ba_opp NUMERIC(8,5),
    era NUMERIC(8,3),
    ibb INT,
    wp INT,
    hbp INT,
    bk INT,
    bfp INT,
    gf INT,
    r INT,
    sh INT,
    sf INT,
    gidp INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_pitching_post_unique
        UNIQUE (source_file_id, player_id, year_id, round, team_id)
);

COMMENT ON TABLE raw_lahman.pitching_post IS
    'Raw Lahman PitchingPost table. Postseason pitching statistics by player, year, and series round.';

-- ---------------------------------------------------------------------------
-- Fielding Postseason
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.fielding_post (
    raw_lahman_fielding_post_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT NOT NULL,
    year_id INT NOT NULL,
    team_id TEXT,
    lg_id TEXT,
    round TEXT NOT NULL,
    pos TEXT NOT NULL,
    g INT,
    gs INT,
    inn_outs INT,
    po INT,
    a INT,
    e INT,
    dp INT,
    tp INT,
    pb INT,
    sb INT,
    cs INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_fielding_post_unique
        UNIQUE (source_file_id, player_id, year_id, round, team_id, pos)
);

COMMENT ON TABLE raw_lahman.fielding_post IS
    'Raw Lahman FieldingPost table. Postseason fielding statistics by player, year, round, and position.';

-- ---------------------------------------------------------------------------
-- Postseason Series Results
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.series_post (
    raw_lahman_series_post_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id INT NOT NULL,
    round TEXT NOT NULL,
    team_id_winner TEXT,
    lg_id_winner TEXT,
    team_id_loser TEXT,
    lg_id_loser TEXT,
    wins INT,
    losses INT,
    ties INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_series_post_unique
        UNIQUE (source_file_id, year_id, round, team_id_winner, team_id_loser)
);

COMMENT ON TABLE raw_lahman.series_post IS
    'Raw Lahman SeriesPost table. Postseason series results including wins, losses, and ties by round.';

-- ---------------------------------------------------------------------------
-- Home Games (park-level home game counts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.home_games (
    raw_lahman_home_games_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_key INT NOT NULL,
    league_key TEXT,
    team_key TEXT NOT NULL,
    park_key TEXT NOT NULL,
    span_first DATE,
    span_last DATE,
    games INT,
    openings INT,
    attendance BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_home_games_unique
        UNIQUE (source_file_id, year_key, team_key, park_key)
);

COMMENT ON TABLE raw_lahman.home_games IS
    'Raw Lahman HomeGames table. Games, openings, and attendance by team-park-season combination.';

-- ---------------------------------------------------------------------------
-- Parks (ballpark reference)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.parks (
    raw_lahman_parks_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    park_key TEXT NOT NULL,
    park_name TEXT,
    park_alias TEXT,
    city TEXT,
    state TEXT,
    country TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_parks_unique
        UNIQUE (source_file_id, park_key)
);

COMMENT ON TABLE raw_lahman.parks IS
    'Raw Lahman Parks table. Ballpark reference with name, alias, and location.';

COMMIT;
