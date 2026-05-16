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
    'Raw Lahman People table.';

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
    'Raw Lahman Batting table.';

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
    'Raw Lahman Pitching table.';

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
    'Raw Lahman Fielding table.';

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
    'Raw Lahman Teams table.';

COMMIT;