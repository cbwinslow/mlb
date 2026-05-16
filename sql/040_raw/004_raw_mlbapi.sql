BEGIN;

CREATE TABLE IF NOT EXISTS raw_mlbapi.request (
    mlbapi_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingest_run_id UUID
        REFERENCES meta.ingest_run(ingest_run_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    source_endpoint_id BIGINT NOT NULL
        REFERENCES meta.source_endpoint(source_endpoint_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    request_url TEXT NOT NULL,
    request_method TEXT NOT NULL DEFAULT 'GET',
    request_params JSONB,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_status INT,
    response_received_at TIMESTAMPTZ,
    response_hash BYTEA,
    payload_size_bytes BIGINT,
    CONSTRAINT raw_mlbapi_request_method_chk
        CHECK (request_method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE'))
);

COMMENT ON TABLE raw_mlbapi.request IS
    'One row per MLB StatsAPI HTTP request.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.payload (
    mlbapi_payload_id BIGSERIAL PRIMARY KEY,
    mlbapi_request_id UUID NOT NULL
        REFERENCES raw_mlbapi.request(mlbapi_request_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    endpoint_code TEXT NOT NULL,
    endpoint_group TEXT,
    game_pk BIGINT,
    person_id BIGINT,
    team_id BIGINT,
    season INT,
    sport_id INT,
    natural_key TEXT,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE raw_mlbapi.payload IS
    'Raw JSON payloads returned by MLB StatsAPI.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.schedule_date (
    raw_schedule_date_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    date DATE NOT NULL,
    total_items INT,
    total_events INT,
    total_games INT,
    total_games_in_progress INT,
    raw_date_json JSONB,
    CONSTRAINT raw_mlbapi_schedule_date_unique
        UNIQUE (mlbapi_payload_id, date)
);

COMMENT ON TABLE raw_mlbapi.schedule_date IS
    'Expanded date-level schedule nodes from schedule payloads.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.schedule_game (
    raw_schedule_game_id BIGSERIAL PRIMARY KEY,
    raw_schedule_date_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.schedule_date(raw_schedule_date_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_pk BIGINT NOT NULL,
    game_guid TEXT,
    link_path TEXT,
    game_type TEXT,
    season TEXT,
    game_date TIMESTAMPTZ,
    official_date DATE,
    status_abstract_game_state TEXT,
    status_abstract_game_code TEXT,
    status_detailed_state TEXT,
    status_coded_game_state TEXT,
    double_header TEXT,
    day_night TEXT,
    series_game_number INT,
    games_in_series INT,
    series_description TEXT,
    scheduled_innings INT,
    reschedule_game_date DATE,
    reschedule_date DATE,
    if_necessary TEXT,
    if_necessary_description TEXT,
    venue_id BIGINT,
    venue_name TEXT,
    away_team_id BIGINT,
    away_team_name TEXT,
    home_team_id BIGINT,
    home_team_name TEXT,
    away_score INT,
    home_score INT,
    raw_game_json JSONB,
    CONSTRAINT raw_mlbapi_schedule_game_unique
        UNIQUE (raw_schedule_date_id, game_pk)
);

COMMENT ON TABLE raw_mlbapi.schedule_game IS
    'Expanded game rows from MLB StatsAPI schedule responses.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.live_play (
    raw_live_play_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_pk BIGINT NOT NULL,
    all_plays_index INT NOT NULL,
    at_bat_index INT,
    play_id TEXT,
    inning INT,
    half_inning TEXT,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    is_complete BOOLEAN,
    is_scoring_play BOOLEAN,
    event_type TEXT,
    event_text TEXT,
    description_text TEXT,
    batter_id BIGINT,
    pitcher_id BIGINT,
    away_score INT,
    home_score INT,
    raw_play_json JSONB,
    CONSTRAINT raw_mlbapi_live_play_unique
        UNIQUE (mlbapi_payload_id, game_pk, all_plays_index)
);

COMMENT ON TABLE raw_mlbapi.live_play IS
    'Expanded allPlays rows from game live feed payloads.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.live_pitch (
    raw_live_pitch_id BIGSERIAL PRIMARY KEY,
    raw_live_play_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.live_play(raw_live_play_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    pitch_index INT NOT NULL,
    pitch_number INT,
    call_code TEXT,
    call_description TEXT,
    start_speed NUMERIC(8,3),
    end_speed NUMERIC(8,3),
    strike_zone_top NUMERIC(10,5),
    strike_zone_bottom NUMERIC(10,5),
    zone SMALLINT,
    plate_time NUMERIC(10,5),
    extension NUMERIC(10,5),
    px NUMERIC(10,5),
    pz NUMERIC(10,5),
    x0 NUMERIC(12,6),
    y0 NUMERIC(12,6),
    z0 NUMERIC(12,6),
    vx0 NUMERIC(12,6),
    vy0 NUMERIC(12,6),
    vz0 NUMERIC(12,6),
    ax NUMERIC(12,6),
    ay NUMERIC(12,6),
    az NUMERIC(12,6),
    breaks_json JSONB,
    coordinates_json JSONB,
    raw_pitch_json JSONB,
    CONSTRAINT raw_mlbapi_live_pitch_unique
        UNIQUE (raw_live_play_id, pitch_index)
);

COMMENT ON TABLE raw_mlbapi.live_pitch IS
    'Expanded pitch events from playEvents in game live feed responses.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.person (
    raw_person_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    person_id BIGINT NOT NULL,
    full_name TEXT,
    first_name TEXT,
    last_name TEXT,
    primary_number TEXT,
    birth_date DATE,
    current_age INT,
    birth_city TEXT,
    birth_state_province TEXT,
    birth_country TEXT,
    height TEXT,
    weight INT,
    active BOOLEAN,
    primary_position_code TEXT,
    primary_position_name TEXT,
    use_name TEXT,
    boxscore_name TEXT,
    nick_name TEXT,
    mlb_debut_date DATE,
    bat_side_code TEXT,
    pitch_hand_code TEXT,
    draft_year INT,
    raw_person_json JSONB,
    CONSTRAINT raw_mlbapi_person_unique
        UNIQUE (mlbapi_payload_id, person_id)
);

COMMENT ON TABLE raw_mlbapi.person IS
    'Expanded person/player records from MLB StatsAPI people payloads.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.team (
    raw_team_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    team_id BIGINT NOT NULL,
    name TEXT,
    team_code TEXT,
    file_code TEXT,
    abbreviation TEXT,
    team_name TEXT,
    location_name TEXT,
    league_id BIGINT,
    division_id BIGINT,
    venue_id BIGINT,
    spring_venue_id BIGINT,
    active BOOLEAN,
    first_year_of_play TEXT,
    season INT,
    raw_team_json JSONB,
    CONSTRAINT raw_mlbapi_team_unique
        UNIQUE (mlbapi_payload_id, team_id)
);

COMMENT ON TABLE raw_mlbapi.team IS
    'Expanded team records from MLB StatsAPI team payloads.';

CREATE TABLE IF NOT EXISTS raw_mlbapi.meta_value (
    raw_meta_value_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    meta_type TEXT NOT NULL,
    value_code TEXT,
    value_label TEXT,
    sort_order INT,
    raw_meta_json JSONB
);

COMMENT ON TABLE raw_mlbapi.meta_value IS
    'Expanded values from MLB StatsAPI meta endpoint families such as gameTypes, eventTypes, and gameStatus.';

COMMIT;