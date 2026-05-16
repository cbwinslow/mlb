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

COMMIT;