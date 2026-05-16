BEGIN;

CREATE TABLE IF NOT EXISTS raw_chadwick.cwevent_file (
    cwevent_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    event_file_id UUID
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT,
    tool_version TEXT,
    field_spec TEXT NOT NULL,
    command_text TEXT,
    output_file_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_chadwick.cwevent_file IS
    'Metadata for a cwevent extraction run and output artifact.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwevent (
    cwevent_row_id BIGSERIAL PRIMARY KEY,
    cwevent_file_id UUID NOT NULL
        REFERENCES raw_chadwick.cwevent_file(cwevent_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    event_id INT NOT NULL,
    inn_ct INT,
    bat_home_id INT,
    outs_ct INT,
    balls_ct INT,
    strikes_ct INT,
    bat_id TEXT,
    bat_hand_cd TEXT,
    pit_id TEXT,
    pit_hand_cd TEXT,
    res_bat_id TEXT,
    res_bat_hand_cd TEXT,
    res_pit_id TEXT,
    res_pit_hand_cd TEXT,
    first_runner_id TEXT,
    second_runner_id TEXT,
    third_runner_id TEXT,
    event_cd INT,
    event_tx TEXT,
    battedball_cd TEXT,
    hit_value INT,
    sh_fl BOOLEAN,
    sf_fl BOOLEAN,
    event_outs_ct INT,
    event_runs_ct INT,
    bat_dest_id INT,
    run1_dest_id INT,
    run2_dest_id INT,
    run3_dest_id INT,
    pa_truncated_fl BOOLEAN,
    ab_fl BOOLEAN,
    h_fl BOOLEAN,
    raw_event_row JSONB,
    CONSTRAINT raw_chadwick_cwevent_unique
        UNIQUE (cwevent_file_id, game_id, event_id)
);

COMMENT ON TABLE raw_chadwick.cwevent IS
    'Structured play/event rows from Chadwick cwevent output; field set may be extended over time.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwgame_file (
    cwgame_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    event_file_id UUID
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT,
    tool_version TEXT,
    field_spec TEXT NOT NULL,
    command_text TEXT,
    output_file_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_chadwick.cwgame_file IS
    'Metadata for a cwgame extraction run and output artifact.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwgame (
    cwgame_row_id BIGSERIAL PRIMARY KEY,
    cwgame_file_id UUID NOT NULL
        REFERENCES raw_chadwick.cwgame_file(cwgame_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
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
    CONSTRAINT raw_chadwick_cwgame_unique
        UNIQUE (cwgame_file_id, game_id)
);

COMMENT ON TABLE raw_chadwick.cwgame IS
    'Structured game summary rows from Chadwick cwgame output.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwsub_file (
    cwsub_file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id UUID
        REFERENCES meta.source_file(source_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    event_file_id UUID
        REFERENCES raw_retrosheet.event_file(event_file_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    season INT,
    tool_version TEXT,
    field_spec TEXT,
    command_text TEXT,
    output_file_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_chadwick.cwsub_file IS
    'Metadata for a cwsub extraction run and output artifact.';

CREATE TABLE IF NOT EXISTS raw_chadwick.cwsub (
    cwsub_row_id BIGSERIAL PRIMARY KEY,
    cwsub_file_id UUID NOT NULL
        REFERENCES raw_chadwick.cwsub_file(cwsub_file_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_id TEXT NOT NULL,
    event_id INT,
    inning INT,
    batting_team_side INT,
    player_id TEXT NOT NULL,
    player_name TEXT,
    team_side INT,
    batting_order INT,
    field_position INT,
    removed_player_id TEXT,
    raw_sub_row JSONB
);

COMMENT ON TABLE raw_chadwick.cwsub IS
    'Structured substitution rows from Chadwick cwsub output.';

COMMIT;