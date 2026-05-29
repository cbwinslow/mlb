BEGIN;

CREATE TABLE IF NOT EXISTS raw_retrosheet.event_file (
    event_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID NOT NULL
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INT,
    team_code TEXT,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL DEFAULT 'event',
    file_version TEXT,
    source_zip_name TEXT,
    file_encoding TEXT,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_event_file_unique
        UNIQUE (source_file_id)
);

COMMENT ON TABLE raw_retrosheet.event_file IS
    'One row per Retrosheet event file loaded into the system.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.game (
    retrosheet_game_row_id BIGSERIAL PRIMARY KEY,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    game_type_code TEXT,
    game_date DATE,
    home_team_code TEXT,
    away_team_code TEXT,
    game_number SMALLINT,
    file_version TEXT,
    record_sequence_start INT,
    record_sequence_end INT,
    raw_header JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_game_unique
        UNIQUE (event_file_id, game_id)
);

COMMENT ON TABLE raw_retrosheet.game IS
    'Logical game wrapper derived from Retrosheet id/version/info record groupings.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.record (
    retrosheet_record_id BIGSERIAL PRIMARY KEY,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    record_sequence INT NOT NULL,
    record_type TEXT NOT NULL,
    raw_line TEXT NOT NULL,
    raw_fields TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_record_type_chk
        CHECK (
            record_type IN (
                'id',
                'version',
                'info',
                'start',
                'sub',
                'play',
                'com',
                'data',
                'badj',
                'padj',
                'ladj',
                'radj',
                'presadj'
            )
        ),
    CONSTRAINT raw_retrosheet_record_unique
        UNIQUE (event_file_id, game_id, record_sequence)
);

COMMENT ON TABLE raw_retrosheet.record IS
    'Every raw line from a Retrosheet event file, preserved in source order.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.info (
    retrosheet_info_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    info_key TEXT NOT NULL,
    info_value TEXT,
    CONSTRAINT raw_retrosheet_info_unique
        UNIQUE (retrosheet_record_id),
    CONSTRAINT raw_retrosheet_info_key_game_unique
        UNIQUE (event_file_id, game_id, info_key, retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.info IS
    'Parsed Retrosheet info records such as date, number, starttime, daynight, weather, and teams.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.start (
    retrosheet_start_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    player_name TEXT NOT NULL,
    team_side SMALLINT NOT NULL,
    batting_order SMALLINT NOT NULL,
    field_position SMALLINT NOT NULL,
    CONSTRAINT raw_retrosheet_start_team_side_chk
        CHECK (team_side IN (0, 1)),
    CONSTRAINT raw_retrosheet_start_unique
        UNIQUE (retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.start IS
    'Parsed start records; Retrosheet documents five fields for start/sub rows.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.sub (
    retrosheet_sub_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    player_name TEXT NOT NULL,
    team_side SMALLINT NOT NULL,
    batting_order SMALLINT NOT NULL,
    field_position SMALLINT NOT NULL,
    CONSTRAINT raw_retrosheet_sub_team_side_chk
        CHECK (team_side IN (0, 1)),
    CONSTRAINT raw_retrosheet_sub_unique
        UNIQUE (retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.sub IS
    'Parsed substitution rows from Retrosheet event files.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.play (
    retrosheet_play_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    inning SMALLINT NOT NULL,
    batting_team_side SMALLINT NOT NULL,
    batter_id TEXT,
    ball_strike_count TEXT,
    pitch_sequence TEXT,
    event_text TEXT,
    raw_play_fields TEXT[],
    CONSTRAINT raw_retrosheet_play_team_side_chk
        CHECK (batting_team_side IN (0, 1)),
    CONSTRAINT raw_retrosheet_play_unique
        UNIQUE (retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.play IS
    'Parsed play rows preserving inning, side, batter, count, pitch sequence, and event text.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.comment (
    retrosheet_comment_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    comment_text TEXT NOT NULL,
    CONSTRAINT raw_retrosheet_comment_unique
        UNIQUE (retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.comment IS
    'Parsed com rows from Retrosheet event files.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.data (
    retrosheet_data_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    data_type TEXT NOT NULL,
    player_id TEXT,
    value_text TEXT,
    CONSTRAINT raw_retrosheet_data_unique
        UNIQUE (retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.data IS
    'Parsed data rows, including earned-run style records present after final play rows.';

CREATE TABLE IF NOT EXISTS raw_retrosheet.adjustment (
    retrosheet_adjustment_id BIGSERIAL PRIMARY KEY,
    retrosheet_record_id BIGINT NOT NULL
        REFERENCES raw_retrosheet.record(retrosheet_record_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    event_file_id UUID NOT NULL
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    adjustment_type TEXT NOT NULL,
    subject_id TEXT,
    adjustment_value TEXT,
    CONSTRAINT raw_retrosheet_adjustment_type_chk
        CHECK (
            adjustment_type IN ('badj', 'padj', 'ladj', 'radj', 'presadj')
        ),
    CONSTRAINT raw_retrosheet_adjustment_unique
        UNIQUE (retrosheet_record_id)
);

COMMENT ON TABLE raw_retrosheet.adjustment IS
    'Parsed adjustment records such as badj, padj, ladj, radj, and presadj.';

-- ===========================================================================
-- Events table - Full 96-field play-by-play from cwevent parsing
-- This is the primary table for event data, populated via pychadwick
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.events (
    event_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    event_seq INTEGER NOT NULL,
    away_team_id TEXT,
    inning SMALLINT,
    batting_team SMALLINT,  -- 0=visitor, 1=home
    outs_ct SMALLINT,
    bat_lineup_id SMALLINT,
    fld_cd SMALLINT,
    batter TEXT,
    batter_hand CHAR(1),
    pitcher TEXT,
    pitcher_hand CHAR(1),
    catcher TEXT,
    first_base TEXT,
    second_base TEXT,
    third_base TEXT,
    shortstop TEXT,
    left_field TEXT,
    center_field TEXT,
    right_field TEXT,
    res_batter TEXT,
    res_batter_hand CHAR(1),
    res_pitcher TEXT,
    res_pitcher_hand CHAR(1),
    first_runner TEXT,
    second_runner TEXT,
    third_runner TEXT,
    event_text TEXT,
    leadoff_fl BOOLEAN,
    ph_fl BOOLEAN,
    balls_ct SMALLINT,
    strikes_ct SMALLINT,
    pitch_seq_tx TEXT,
    event_cd SMALLINT,
    battedball_cd CHAR(1),
    bunt_fl BOOLEAN,
    foul_fl BOOLEAN,
    hit_val SMALLINT,
    sh_fl BOOLEAN,
    sf_fl BOOLEAN,
    hit_location_tx TEXT,
    err_ct SMALLINT,
    wp_fl BOOLEAN,
    pb_fl BOOLEAN,
    ab_fl BOOLEAN,
    h_fl BOOLEAN,
    sh_ball_fl BOOLEAN,
    ibb_fl BOOLEAN,
    gdp_fl BOOLEAN,
    xi_fl BOOLEAN,
    bball_fl BOOLEAN,
    event_runs_ct SMALLINT,
    bat_dest_id SMALLINT,
    run1_dest_id SMALLINT,
    run2_dest_id SMALLINT,
    run3_dest_id SMALLINT,
    event_outs_ct SMALLINT,
    bat_play_tx TEXT,
    run1_play_tx TEXT,
    run2_play_tx TEXT,
    run3_play_tx TEXT,
    sb1_fl BOOLEAN,
    sb2_fl BOOLEAN,
    sb3_fl BOOLEAN,
    cs1_fl BOOLEAN,
    cs2_fl BOOLEAN,
    cs3_fl BOOLEAN,
    po1_fl BOOLEAN,
    po2_fl BOOLEAN,
    po3_fl BOOLEAN,
    resp_fielder1_id TEXT,
    resp_fielder2_id TEXT,
    resp_fielder3_id TEXT,
    resp_fielder_a1_id TEXT,
    resp_fielder_a2_id TEXT,
    resp_fielder_a3_id TEXT,
    resp_fielder_a4_id TEXT,
    resp_fielder_a5_id TEXT,
    resp_fielder_e1_id TEXT,
    resp_fielder_e2_id TEXT,
    resp_fielder_e3_id TEXT,
    resp_fielder_po1_id TEXT,
    resp_fielder_po2_id TEXT,
    resp_fielder_po3_id TEXT,
    away_score_ct SMALLINT,
    home_score_ct SMALLINT,
    away_hits_ct SMALLINT,
    home_hits_ct SMALLINT,
    away_err_ct SMALLINT,
    home_err_ct SMALLINT,
    away_score_fl BOOLEAN,
    home_score_fl BOOLEAN,
    bunt_fc_fl BOOLEAN,
    pa_ball_ct SMALLINT,
    pa_strike_ct SMALLINT,
    pa_truncated_fl BOOLEAN,
    raw_event_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_events_unique UNIQUE (game_id, event_seq)
);

COMMENT ON TABLE raw_retrosheet.events IS
    'Full play-by-play events from Retrosheet event files via pychadwick/cwevent (96+ fields).';

-- ===========================================================================
-- Game summary table (from Chadwick cwgame)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.game_summary (
    game_summary_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    game_date DATE,
    game_number SMALLINT,
    weekday TEXT,
    visit_team TEXT,
    home_team TEXT,
    day_night TEXT,
    start_time TEXT,
    dh_used_fl BOOLEAN,
    tiebreakbase_fl BOOLEAN,
    attendance INT,
    park_id TEXT,
    temp INT,
    winddir TEXT,
    windspeed INT,
    fieldcond TEXT,
    precip TEXT,
    sky TEXT,
    time_of_game INT,
    raw_game_row JSONB,
    CONSTRAINT raw_retrosheet_game_summary_unique
        UNIQUE (game_id)
);

COMMENT ON TABLE raw_retrosheet.game_summary IS
    'Structured game summary rows from Retrosheet event files (cwgame equivalent).';

-- ===========================================================================
-- Substitution table (from Chadwick cwsub)
-- ===========================================================================

CREATE TABLE IF NOT EXISTS raw_retrosheet.substitution (
    substitution_id BIGSERIAL PRIMARY KEY,
    game_id TEXT NOT NULL,
    event_seq INTEGER,
    inning SMALLINT,
    batting_team_side SMALLINT,
    player_id TEXT NOT NULL,
    player_name TEXT,
    team_side SMALLINT,
    batting_order SMALLINT,
    field_position SMALLINT,
    removed_player_id TEXT,
    raw_sub_row JSONB
);

COMMENT ON TABLE raw_retrosheet.substitution IS
    'Structured substitution rows from Retrosheet event files (cwsub equivalent).';

-- ===========================================================================
-- Additional Retrosheet tables (supplementary data)
-- Game logs, biographical data, rosters, etc.
-- ===========================================================================

-- Game log table (161-column pre-summarized games)
CREATE TABLE IF NOT EXISTS raw_retrosheet.game_log (
    game_log_id BIGSERIAL PRIMARY KEY,
    game_date DATE NOT NULL,
    game_num SMALLINT DEFAULT 0,
    day_of_week CHAR(3),
    away_team CHAR(3) NOT NULL,
    away_league CHAR(1),
    away_game_num SMALLINT,
    home_team CHAR(3) NOT NULL,
    home_league CHAR(1),
    home_game_num SMALLINT,
    away_score SMALLINT,
    home_score SMALLINT,
    num_outs SMALLINT,
    day_night CHAR(1),
    completion_info VARCHAR(30),
    forfeit_info CHAR(1),
    protest_info CHAR(1),
    park_id VARCHAR(10),
    attendance INTEGER,
    game_minutes SMALLINT,
    away_line_score VARCHAR(30),
    home_line_score VARCHAR(30),
    away_ab SMALLINT,
    away_h SMALLINT,
    away_2b SMALLINT,
    away_3b SMALLINT,
    away_hr SMALLINT,
    away_rbi SMALLINT,
    away_sh SMALLINT,
    away_sf SMALLINT,
    away_hbp SMALLINT,
    away_bb SMALLINT,
    away_ibb SMALLINT,
    away_so SMALLINT,
    away_sb SMALLINT,
    away_cs SMALLINT,
    away_gdp SMALLINT,
    away_ci SMALLINT,
    away_lob SMALLINT,
    away_pitchers_used SMALLINT,
    away_er SMALLINT,
    away_ter SMALLINT,
    away_wp SMALLINT,
    away_balk SMALLINT,
    away_po SMALLINT,
    away_assists SMALLINT,
    away_errors SMALLINT,
    away_pb SMALLINT,
    away_dp SMALLINT,
    away_tp SMALLINT,
    home_ab SMALLINT,
    home_h SMALLINT,
    home_2b SMALLINT,
    home_3b SMALLINT,
    home_hr SMALLINT,
    home_rbi SMALLINT,
    home_sh SMALLINT,
    home_sf SMALLINT,
    home_hbp SMALLINT,
    home_bb SMALLINT,
    home_ibb SMALLINT,
    home_so SMALLINT,
    home_sb SMALLINT,
    home_cs SMALLINT,
    home_gdp SMALLINT,
    home_ci SMALLINT,
    home_lob SMALLINT,
    home_pitchers_used SMALLINT,
    home_er SMALLINT,
    home_ter SMALLINT,
    home_wp SMALLINT,
    home_balk SMALLINT,
    home_po SMALLINT,
    home_assists SMALLINT,
    home_errors SMALLINT,
    home_pb SMALLINT,
    home_dp SMALLINT,
    home_tp SMALLINT,
    ump_home_id VARCHAR(10),
    ump_home_name VARCHAR(40),
    ump_1b_id VARCHAR(10),
    ump_1b_name VARCHAR(40),
    ump_2b_id VARCHAR(10),
    ump_2b_name VARCHAR(40),
    ump_3b_id VARCHAR(10),
    ump_3b_name VARCHAR(40),
    ump_lf_id VARCHAR(10),
    ump_lf_name VARCHAR(40),
    ump_rf_id VARCHAR(10),
    ump_rf_name VARCHAR(40),
    away_manager_id VARCHAR(10),
    away_manager_name VARCHAR(40),
    home_manager_id VARCHAR(10),
    home_manager_name VARCHAR(40),
    winning_pitcher_id VARCHAR(10),
    winning_pitcher_name VARCHAR(40),
    losing_pitcher_id VARCHAR(10),
    losing_pitcher_name VARCHAR(40),
    saving_pitcher_id VARCHAR(10),
    saving_pitcher_name VARCHAR(40),
    gwinrbi_id VARCHAR(10),
    gwinrbi_name VARCHAR(40),
    away_lineup_1_id VARCHAR(10),
    away_lineup_1_name VARCHAR(40),
    away_lineup_1_pos SMALLINT,
    away_lineup_2_id VARCHAR(10),
    away_lineup_2_name VARCHAR(40),
    away_lineup_2_pos SMALLINT,
    away_lineup_3_id VARCHAR(10),
    away_lineup_3_name VARCHAR(40),
    away_lineup_3_pos SMALLINT,
    away_lineup_4_id VARCHAR(10),
    away_lineup_4_name VARCHAR(40),
    away_lineup_4_pos SMALLINT,
    away_lineup_5_id VARCHAR(10),
    away_lineup_5_name VARCHAR(40),
    away_lineup_5_pos SMALLINT,
    away_lineup_6_id VARCHAR(10),
    away_lineup_6_name VARCHAR(40),
    away_lineup_6_pos SMALLINT,
    away_lineup_7_id VARCHAR(10),
    away_lineup_7_name VARCHAR(40),
    away_lineup_7_pos SMALLINT,
    away_lineup_8_id VARCHAR(10),
    away_lineup_8_name VARCHAR(40),
    away_lineup_8_pos SMALLINT,
    away_lineup_9_id VARCHAR(10),
    away_lineup_9_name VARCHAR(40),
    away_lineup_9_pos SMALLINT,
    home_lineup_1_id VARCHAR(10),
    home_lineup_1_name VARCHAR(40),
    home_lineup_1_pos SMALLINT,
    home_lineup_2_id VARCHAR(10),
    home_lineup_2_name VARCHAR(40),
    home_lineup_2_pos SMALLINT,
    home_lineup_3_id VARCHAR(10),
    home_lineup_3_name VARCHAR(40),
    home_lineup_3_pos SMALLINT,
    home_lineup_4_id VARCHAR(10),
    home_lineup_4_name VARCHAR(40),
    home_lineup_4_pos SMALLINT,
    home_lineup_5_id VARCHAR(10),
    home_lineup_5_name VARCHAR(40),
    home_lineup_5_pos SMALLINT,
    home_lineup_6_id VARCHAR(10),
    home_lineup_6_name VARCHAR(40),
    home_lineup_6_pos SMALLINT,
    home_lineup_7_id VARCHAR(10),
    home_lineup_7_name VARCHAR(40),
    home_lineup_7_pos SMALLINT,
    home_lineup_8_id VARCHAR(10),
    home_lineup_8_name VARCHAR(40),
    home_lineup_8_pos SMALLINT,
    home_lineup_9_id VARCHAR(10),
    home_lineup_9_name VARCHAR(40),
    home_lineup_9_pos SMALLINT,
    additional_info VARCHAR(80),
    acquisition_info CHAR(1),
    raw_game_log_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_game_log_unique UNIQUE (game_date, home_team, game_num)
);

COMMENT ON TABLE raw_retrosheet.game_log IS
    'Pre-summarized game log data (161 columns) from Retrosheet.';

-- Biographical people
CREATE TABLE IF NOT EXISTS raw_retrosheet.bio_people (
    bio_person_id BIGSERIAL PRIMARY KEY,
    retro_id TEXT NOT NULL,
    last_name TEXT,
    first_name TEXT,
    name_given TEXT,
    birth_year SMALLINT,
    birth_month SMALLINT,
    birth_day SMALLINT,
    birth_country TEXT,
    birth_state TEXT,
    birth_city TEXT,
    death_year SMALLINT,
    death_month SMALLINT,
    death_day SMALLINT,
    death_country TEXT,
    death_state TEXT,
    death_city TEXT,
    bats CHAR(1),
    throws CHAR(1),
    debut DATE,
    final_game DATE,
    weight INT,
    height INT,
    first_g CHAR(8),
    last_g CHAR(8),
    raw_bio_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_bio_people_unique UNIQUE (retro_id)
);

COMMENT ON TABLE raw_retrosheet.bio_people IS
    'Biographical information for all people in Retrosheet database.';

-- Ballparks
CREATE TABLE IF NOT EXISTS raw_retrosheet.ballparks (
    ballpark_id BIGSERIAL PRIMARY KEY,
    park_id VARCHAR(10) NOT NULL,
    park_name VARCHAR(80),
    park_alias VARCHAR(80),
    city VARCHAR(40),
    state VARCHAR(30),
    country VARCHAR(30),
    first_g CHAR(8),
    last_g CHAR(8),
    raw_ballpark_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_ballparks_unique UNIQUE (park_id)
);

COMMENT ON TABLE raw_retrosheet.ballparks IS
    'Ballpark information from Retrosheet.';

-- Teams
CREATE TABLE IF NOT EXISTS raw_retrosheet.teams (
    team_id BIGSERIAL PRIMARY KEY,
    team_code CHAR(3) NOT NULL,
    league CHAR(1),
    division CHAR(1),
    location VARCHAR(40),
    nickname VARCHAR(40),
    alt_names VARCHAR(80),
    first_g CHAR(8),
    last_g CHAR(8),
    raw_team_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_teams_unique UNIQUE (team_code)
);

COMMENT ON TABLE raw_retrosheet.teams IS
    'Team information from Retrosheet.';

-- Umpires
CREATE TABLE IF NOT EXISTS raw_retrosheet.umpires (
    umpire_id BIGSERIAL PRIMARY KEY,
    ump_id VARCHAR(10) NOT NULL,
    last_name VARCHAR(40),
    first_name VARCHAR(40),
    first_g CHAR(8),
    last_g CHAR(8),
    raw_umpire_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_umpires_unique UNIQUE (ump_id)
);

COMMENT ON TABLE raw_retrosheet.umpires IS
    'Umpire information from Retrosheet.';

-- Managers
CREATE TABLE IF NOT EXISTS raw_retrosheet.managers (
    manager_id BIGSERIAL PRIMARY KEY,
    game_id VARCHAR(20),
    manager_retro_id VARCHAR(10),
    team CHAR(3),
    seq SMALLINT,
    raw_manager_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.managers IS
    'Manager information per game from Retrosheet.';

-- Coaches
CREATE TABLE IF NOT EXISTS raw_retrosheet.coaches (
    coach_id BIGSERIAL PRIMARY KEY,
    coach_retro_id VARCHAR(10),
    last_name VARCHAR(40),
    first_name VARCHAR(40),
    team_id CHAR(3),
    season SMALLINT,
    position VARCHAR(20),
    first_g CHAR(8),
    last_g CHAR(8),
    raw_coach_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.coaches IS
    'Coach information from Retrosheet.';

-- Relatives
CREATE TABLE IF NOT EXISTS raw_retrosheet.relatives (
    relative_id BIGSERIAL PRIMARY KEY,
    person_id_1 VARCHAR(10),
    person_id_2 VARCHAR(10),
    relationship VARCHAR(20),
    raw_relative_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.relatives IS
    'Family relationships between people in Retrosheet database.';

-- Schedules
CREATE TABLE IF NOT EXISTS raw_retrosheet.schedules (
    schedule_id BIGSERIAL PRIMARY KEY,
    game_date DATE NOT NULL,
    game_num SMALLINT DEFAULT 0,
    day_of_week CHAR(3),
    away_team CHAR(3) NOT NULL,
    away_league CHAR(1),
    away_game_num SMALLINT,
    home_team CHAR(3) NOT NULL,
    home_league CHAR(1),
    home_game_num SMALLINT,
    day_night CHAR(1),
    postponed VARCHAR(30),
    makeup_date DATE,
    raw_schedule_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_retrosheet.schedules IS
    'Pre-season schedule data from Retrosheet.';

-- Rosters
CREATE TABLE IF NOT EXISTS raw_retrosheet.rosters (
    roster_id BIGSERIAL PRIMARY KEY,
    player_id TEXT NOT NULL,
    team_id CHAR(3) NOT NULL,
    season SMALLINT NOT NULL,
    last_name TEXT,
    first_name TEXT,
    bats CHAR(1),
    throws CHAR(1),
    position TEXT,
    raw_roster_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_retrosheet_rosters_unique UNIQUE (player_id, team_id, season)
);

COMMENT ON TABLE raw_retrosheet.rosters IS
    'Per-team, per-season roster data from Retrosheet.';

COMMIT;