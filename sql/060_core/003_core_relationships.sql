BEGIN;

CREATE TABLE IF NOT EXISTS core.player_team_season (
    player_team_season_id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    team_id BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    season INT NOT NULL,
    first_game_id BIGINT
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    last_game_id BIGINT
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    games_played INT,
    games_started INT,
    plate_appearances INT,
    batters_faced INT,
    innings_pitched_outs INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_player_team_season_unique
        UNIQUE (player_id, team_id, season)
);

COMMENT ON TABLE core.player_team_season IS
    'Canonical player-team-season bridge for seasonal modeling and joins.';

CREATE TABLE IF NOT EXISTS core.game_official (
    game_official_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT NOT NULL
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    official_player_id BIGINT
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    official_role_code TEXT NOT NULL,
    official_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_game_official_unique
        UNIQUE (game_id, official_role_code, official_player_id)
);

COMMENT ON TABLE core.game_official IS
    'Game-level umpire and official assignments where available from source data.';

CREATE TABLE IF NOT EXISTS core.game_source_map (
    game_source_map_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT NOT NULL
        REFERENCES core.game(game_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_natural_key TEXT,
    source_recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_game_source_map_unique
        UNIQUE (game_id, source_system_code, source_table_name, source_row_pk)
);

CREATE TABLE IF NOT EXISTS core.plate_appearance_source_map (
    plate_appearance_source_map_id BIGSERIAL PRIMARY KEY,
    plate_appearance_id BIGINT NOT NULL
        REFERENCES core.plate_appearance(plate_appearance_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_natural_key TEXT,
    source_recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_plate_appearance_source_map_unique
        UNIQUE (plate_appearance_id, source_system_code, source_table_name, source_row_pk)
);

CREATE TABLE IF NOT EXISTS core.pitch_source_map (
    pitch_source_map_id BIGSERIAL PRIMARY KEY,
    pitch_id BIGINT NOT NULL
        REFERENCES core.pitch(pitch_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_natural_key TEXT,
    source_recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT core_pitch_source_map_unique
        UNIQUE (pitch_id, source_system_code, source_table_name, source_row_pk)
);

COMMENT ON TABLE core.game_source_map IS
    'Lineage map from canonical game rows back to raw and staging records.';

COMMENT ON TABLE core.plate_appearance_source_map IS
    'Lineage map from canonical plate appearance rows back to raw and staging records.';

COMMENT ON TABLE core.pitch_source_map IS
    'Lineage map from canonical pitch rows back to raw and staging records.';

COMMIT;