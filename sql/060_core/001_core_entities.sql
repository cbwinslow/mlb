BEGIN;

CREATE TABLE IF NOT EXISTS core.player (
    player_id BIGSERIAL PRIMARY KEY,
    player_identity_id BIGINT NOT NULL
        REFERENCES stg.player_identity(player_identity_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    mlbam_player_id BIGINT,
    retrosheet_player_id TEXT,
    lahman_player_id TEXT,
    bbref_player_id TEXT,
    fangraphs_player_id TEXT,
    full_name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    bats TEXT,
    throws TEXT,
    birth_date DATE,
    mlb_debut_date DATE,
    active_flag BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_player_identity_unique
        UNIQUE (player_identity_id)
);

COMMENT ON TABLE core.player IS
    'Canonical player dimension built from staged identity bridges.';

CREATE TABLE IF NOT EXISTS core.team (
    team_id BIGSERIAL PRIMARY KEY,
    team_identity_id BIGINT NOT NULL
        REFERENCES stg.team_identity(team_identity_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    mlbam_team_id BIGINT,
    retrosheet_team_id TEXT,
    lahman_team_id TEXT,
    bbref_team_id TEXT,
    fangraphs_team_id TEXT,
    franchise_id TEXT,
    team_name TEXT NOT NULL,
    city_name TEXT,
    nickname TEXT,
    league_code TEXT,
    first_year INT,
    last_year INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_team_identity_unique
        UNIQUE (team_identity_id)
);

COMMENT ON TABLE core.team IS
    'Canonical team dimension built from staged identity bridges.';

CREATE TABLE IF NOT EXISTS core.venue (
    venue_id BIGSERIAL PRIMARY KEY,
    venue_identity_id BIGINT NOT NULL
        REFERENCES stg.venue_identity(venue_identity_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    mlbam_venue_id BIGINT,
    retrosheet_park_id TEXT,
    venue_name TEXT NOT NULL,
    city_name TEXT,
    state_name TEXT,
    country_name TEXT,
    tz_name TEXT,
    active_start_date DATE,
    active_end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_venue_identity_unique
        UNIQUE (venue_identity_id)
);

COMMENT ON TABLE core.venue IS
    'Canonical venue/park dimension built from staged identity bridges.';

CREATE TABLE IF NOT EXISTS core.game (
    game_id BIGSERIAL PRIMARY KEY,
    game_identity_id BIGINT NOT NULL
        REFERENCES stg.game_identity(game_identity_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    mlbam_game_pk BIGINT,
    retrosheet_game_id TEXT,
    game_date DATE NOT NULL,
    season INT NOT NULL,
    game_type_code TEXT,
    doubleheader_sequence SMALLINT,
    scheduled_start_time TIMESTAMPTZ,
    actual_start_time TIMESTAMPTZ,
    actual_end_time TIMESTAMPTZ,
    home_team_id BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    away_team_id BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    venue_id BIGINT
        REFERENCES core.venue(venue_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    home_score INT,
    away_score INT,
    innings_scheduled SMALLINT,
    innings_completed SMALLINT,
    day_night_code TEXT,
    weather_text TEXT,
    wind_text TEXT,
    temperature_f INT,
    attendance INT,
    duration_minutes INT,
    game_status_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_game_identity_unique
        UNIQUE (game_identity_id)
);

COMMENT ON TABLE core.game IS
    'Canonical game fact header bridging Retrosheet, MLB StatsAPI, and other source systems.';
    
COMMIT;