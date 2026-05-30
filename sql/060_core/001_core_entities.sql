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
    statcast_team_id TEXT,                   -- MLB codes like NYY, LAD
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

