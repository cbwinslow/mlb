BEGIN;

-- =============================================================================
-- Lahman Database Raw Tables
-- =============================================================================
-- All columns match CSV headers directly after snake_case conversion

-- ---------------------------------------------------------------------------
-- People (player registry)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.people (
    raw_lahman_people_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    id TEXT,
    player_id TEXT,
    birth_year TEXT,
    birth_month TEXT,
    birth_day TEXT,
    birth_city TEXT,
    birth_country TEXT,
    birth_state TEXT,
    death_year TEXT,
    death_month TEXT,
    death_day TEXT,
    death_country TEXT,
    death_state TEXT,
    death_city TEXT,
    name_first TEXT,
    name_last TEXT,
    name_given TEXT,
    weight TEXT,
    height TEXT,
    bats TEXT,
    throws TEXT,
    debut TEXT,
    bbref_id TEXT,
    final_game TEXT,
    retro_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_people_unique
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
    player_id TEXT,
    year_id TEXT,
    stint TEXT,
    team_id TEXT,
    lg_id TEXT,
    g TEXT,
    ab TEXT,
    r TEXT,
    h TEXT,
    x2b TEXT,
    x3b TEXT,
    hr TEXT,
    rbi TEXT,
    sb TEXT,
    cs TEXT,
    bb TEXT,
    so TEXT,
    ibb TEXT,
    hbp TEXT,
    sh TEXT,
    sf TEXT,
    gidp TEXT,
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
    player_id TEXT,
    year_id TEXT,
    stint TEXT,
    team_id TEXT,
    lg_id TEXT,
    w TEXT,
    l TEXT,
    g TEXT,
    gs TEXT,
    cg TEXT,
    sho TEXT,
    sv TEXT,
    ip_outs TEXT,
    h TEXT,
    er TEXT,
    hr TEXT,
    bb TEXT,
    so TEXT,
    ba_opp TEXT,
    era TEXT,
    ibb TEXT,
    wp TEXT,
    hbp TEXT,
    bk TEXT,
    bfp TEXT,
    gf TEXT,
    r TEXT,
    sh TEXT,
    sf TEXT,
    gidp TEXT,
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
    player_id TEXT,
    year_id TEXT,
    stint TEXT,
    team_id TEXT,
    lg_id TEXT,
    pos TEXT,
    g TEXT,
    gs TEXT,
    inn_outs TEXT,
    po TEXT,
    a TEXT,
    e TEXT,
    dp TEXT,
    pb TEXT,
    wp TEXT,
    sb TEXT,
    cs TEXT,
    zr TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_fielding_unique
        UNIQUE (source_file_id, player_id, year_id, stint, team_id, pos)
);

COMMENT ON TABLE raw_lahman.fielding IS
    'Raw Lahman Fielding table. Regular-season fielding statistics by player, year, stint, and position.';

-- ---------------------------------------------------------------------------
-- Fielding OF (outfield totals)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.fielding_of (
    raw_lahman_fielding_of_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT,
    year_id TEXT,
    stint TEXT,
    glf TEXT,
    gcf TEXT,
    grf TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_fielding_of_unique
        UNIQUE (source_file_id, player_id, year_id, stint)
);

COMMENT ON TABLE raw_lahman.fielding_of IS
    'Raw Lahman FieldingOF table. Outfield games split by position (LF/CF/RF).';

-- ---------------------------------------------------------------------------
-- Fielding OF Split (outfield by position)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.fielding_of_split (
    raw_lahman_fielding_of_split_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT,
    year_id TEXT,
    stint TEXT,
    team_id TEXT,
    lg_id TEXT,
    pos TEXT,
    g TEXT,
    gs TEXT,
    inn_outs TEXT,
    po TEXT,
    a TEXT,
    e TEXT,
    dp TEXT,
    pb TEXT,
    wp TEXT,
    sb TEXT,
    cs TEXT,
    zr TEXT,
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
    year_id TEXT,
    lg_id TEXT,
    team_id TEXT,
    franch_id TEXT,
    div_id TEXT,
    rank TEXT,
    g TEXT,
    g_home TEXT,
    w TEXT,
    l TEXT,
    div_win TEXT,
    wc_win TEXT,
    lg_win TEXT,
    ws_win TEXT,
    r TEXT,
    ab TEXT,
    h TEXT,
    x2b TEXT,
    x3b TEXT,
    hr TEXT,
    bb TEXT,
    so TEXT,
    sb TEXT,
    cs TEXT,
    hbp TEXT,
    sf TEXT,
    ra TEXT,
    er TEXT,
    era TEXT,
    cg TEXT,
    sho TEXT,
    sv TEXT,
    ip_outs TEXT,
    ha TEXT,
    hra TEXT,
    bba TEXT,
    soa TEXT,
    e TEXT,
    dp TEXT,
    fp TEXT,
    name TEXT,
    park TEXT,
    attendance TEXT,
    bpf TEXT,
    ppf TEXT,
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
-- Teams Franchises
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.teams_franchises (
    raw_lahman_teams_franchises_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    franch_id TEXT,
    franch_name TEXT,
    active TEXT,
    n_aassoc TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_teams_franchises_unique
        UNIQUE (source_file_id, franch_id)
);

COMMENT ON TABLE raw_lahman.teams_franchises IS
    'Raw Lahman TeamsFranchises table. Franchise reference with names and activity status.';

-- ---------------------------------------------------------------------------
-- Teams Half (split-season records)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.teams_half (
    raw_lahman_teams_half_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id TEXT,
    lg_id TEXT,
    team_id TEXT,
    half TEXT,
    div_id TEXT,
    div_win TEXT,
    rank TEXT,
    g TEXT,
    w TEXT,
    l TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_teams_half_unique
        UNIQUE (source_file_id, year_id, team_id, half)
);

COMMENT ON TABLE raw_lahman.teams_half IS
    'Raw Lahman TeamsHalf table. Split-season (first/second half) records for teams. Primarily 1981 and 1994.';

-- ---------------------------------------------------------------------------
-- Salaries
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.salaries (
    raw_lahman_salaries_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    year_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    player_id TEXT,
    salary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_salaries_unique
        UNIQUE (source_file_id, year_id, team_id, player_id)
);

COMMENT ON TABLE raw_lahman.salaries IS
    'Raw Lahman Salaries table. Player salary by season and team. Coverage begins 1985.';

-- ---------------------------------------------------------------------------
-- Awards Players
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_players (
    raw_lahman_awards_players_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT,
    award_id TEXT,
    year_id TEXT,
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
-- Awards Managers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_managers (
    raw_lahman_awards_managers_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT,
    award_id TEXT,
    year_id TEXT,
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
-- Awards Share Players
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_share_players (
    raw_lahman_awards_share_players_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    award_id TEXT,
    year_id TEXT,
    lg_id TEXT,
    player_id TEXT,
    points_won TEXT,
    points_max TEXT,
    votes_first TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_awards_share_players_unique
        UNIQUE (source_file_id, award_id, year_id, lg_id, player_id)
);

COMMENT ON TABLE raw_lahman.awards_share_players IS
    'Raw Lahman AwardsSharePlayers table. Award voting totals and first-place votes by player per award year.';

-- ---------------------------------------------------------------------------
-- Awards Share Managers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.awards_share_managers (
    raw_lahman_awards_share_managers_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    award_id TEXT,
    year_id TEXT,
    lg_id TEXT,
    player_id TEXT,
    points_won TEXT,
    points_max TEXT,
    votes_first TEXT,
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
    player_id TEXT,
    yearid TEXT,
    voted_by TEXT,
    ballots TEXT,
    needed TEXT,
    votes TEXT,
    inducted TEXT,
    category TEXT,
    needed_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_hall_of_fame_unique
        UNIQUE (source_file_id, player_id, yearid, voted_by)
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
    school_id TEXT,
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
    player_id TEXT,
    school_id TEXT,
    year_id TEXT,
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
    year_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    player_id TEXT,
    g_all TEXT,
    gs TEXT,
    g_batting TEXT,
    g_defense TEXT,
    g_p TEXT,
    g_c TEXT,
    g_1b TEXT,
    g_2b TEXT,
    g_3b TEXT,
    g_ss TEXT,
    g_lf TEXT,
    g_cf TEXT,
    g_rf TEXT,
    g_of TEXT,
    g_dh TEXT,
    g_ph TEXT,
    g_pr TEXT,
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
    player_id TEXT,
    year_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    inseason TEXT,
    g TEXT,
    w TEXT,
    l TEXT,
    rank TEXT,
    plyr_mgr TEXT,
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
    player_id TEXT,
    year_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    inseason TEXT,
    half TEXT,
    g TEXT,
    w TEXT,
    l TEXT,
    rank TEXT,
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
    year_id TEXT,
    round TEXT,
    player_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    g TEXT,
    ab TEXT,
    r TEXT,
    h TEXT,
    x2b TEXT,
    x3b TEXT,
    hr TEXT,
    rbi TEXT,
    sb TEXT,
    cs TEXT,
    bb TEXT,
    so TEXT,
    ibb TEXT,
    hbp TEXT,
    sh TEXT,
    sf TEXT,
    gidp TEXT,
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
    player_id TEXT,
    year_id TEXT,
    round TEXT,
    team_id TEXT,
    lg_id TEXT,
    w TEXT,
    l TEXT,
    g TEXT,
    gs TEXT,
    cg TEXT,
    sho TEXT,
    sv TEXT,
    ip_outs TEXT,
    h TEXT,
    er TEXT,
    hr TEXT,
    bb TEXT,
    so TEXT,
    ba_opp TEXT,
    era TEXT,
    ibb TEXT,
    wp TEXT,
    hbp TEXT,
    bk TEXT,
    bfp TEXT,
    gf TEXT,
    r TEXT,
    sh TEXT,
    sf TEXT,
    gidp TEXT,
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
    player_id TEXT,
    year_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    round TEXT,
    pos TEXT,
    g TEXT,
    gs TEXT,
    inn_outs TEXT,
    po TEXT,
    a TEXT,
    e TEXT,
    dp TEXT,
    tp TEXT,
    pb TEXT,
    sb TEXT,
    cs TEXT,
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
    year_id TEXT,
    round TEXT,
    team_i_dwinner TEXT,
    lg_i_dwinner TEXT,
    team_i_dloser TEXT,
    lg_i_dloser TEXT,
    wins TEXT,
    losses TEXT,
    ties TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_series_post_unique
        UNIQUE (source_file_id, year_id, round, team_i_dwinner, team_i_dloser)
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
    year_key TEXT,
    league_key TEXT,
    team_key TEXT,
    park_key TEXT,
    span_first TEXT,
    span_last TEXT,
    games TEXT,
    openings TEXT,
    attendance TEXT,
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
    park_alias TEXT,
    park_key TEXT,
    park_name TEXT,
    city TEXT,
    state TEXT,
    country TEXT,
    id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_parks_unique
        UNIQUE (source_file_id, park_key)
);

COMMENT ON TABLE raw_lahman.parks IS
    'Raw Lahman Parks table. Ballpark reference with name, alias, and location.';

-- ---------------------------------------------------------------------------
-- All-Star Selections
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_lahman.allstar_full (
    raw_lahman_allstar_full_id BIGSERIAL PRIMARY KEY,
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    player_id TEXT,
    year_id TEXT,
    game_num TEXT,
    game_id TEXT,
    team_id TEXT,
    lg_id TEXT,
    gp TEXT,
    starting_pos TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_lahman_allstar_full_unique
        UNIQUE (source_file_id, player_id, year_id, game_num, game_id, team_id)
);

COMMENT ON TABLE raw_lahman.allstar_full IS
    'Raw Lahman AllstarFull table. All-Star game selections with game numbers and starting positions.';

COMMIT;