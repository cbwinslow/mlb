BEGIN;

CREATE TABLE IF NOT EXISTS stg.player_source_conformance (
    player_source_conformance_id BIGSERIAL PRIMARY KEY,
    player_identity_id BIGINT NOT NULL
        REFERENCES stg.player_identity(player_identity_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    mlbam_player_id BIGINT,
    retrosheet_player_id TEXT,
    lahman_player_id TEXT,
    bbref_player_id TEXT,
    fangraphs_player_id TEXT,
    source_player_name TEXT,
    source_birth_date DATE,
    conformed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_player_source_conformance_unique
        UNIQUE (player_identity_id, source_system_code, source_table_name, source_row_pk)
);

CREATE TABLE IF NOT EXISTS stg.team_source_conformance (
    team_source_conformance_id BIGSERIAL PRIMARY KEY,
    team_identity_id BIGINT NOT NULL
        REFERENCES stg.team_identity(team_identity_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    mlbam_team_id BIGINT,
    retrosheet_team_id TEXT,
    lahman_team_id TEXT,
    bbref_team_id TEXT,
    fangraphs_team_id TEXT,
    source_team_name TEXT,
    conformed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_team_source_conformance_unique
        UNIQUE (team_identity_id, source_system_code, source_table_name, source_row_pk)
);

CREATE TABLE IF NOT EXISTS stg.venue_source_conformance (
    venue_source_conformance_id BIGSERIAL PRIMARY KEY,
    venue_identity_id BIGINT NOT NULL
        REFERENCES stg.venue_identity(venue_identity_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    mlbam_venue_id BIGINT,
    retrosheet_park_id TEXT,
    source_venue_name TEXT,
    conformed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_venue_source_conformance_unique
        UNIQUE (venue_identity_id, source_system_code, source_table_name, source_row_pk)
);

COMMENT ON TABLE stg.player_source_conformance IS
    'Maps bridged player identities to concrete raw rows from each source.';

COMMENT ON TABLE stg.team_source_conformance IS
    'Maps bridged team identities to concrete raw rows from each source.';

COMMENT ON TABLE stg.venue_source_conformance IS
    'Maps bridged venue identities to concrete raw rows from each source.';

COMMIT;