BEGIN;

-- ===========================================================================
-- MLB API Extraction Staging Tables
-- DEC-010: Extract from JSONB blobs to typed normalized tables
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Staging table for extracted MLB API game metadata
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.mlbapi_game (
    stg_mlbapi_game_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    game_pk BIGINT NOT NULL,
    game_guid TEXT,
    game_type TEXT,
    season INT,
    game_date DATE,
    official_date DATE,
    status_abstract_state TEXT,
    status_detailed_state TEXT,
    scheduled_innings INT,
    double_header TEXT,
    day_night TEXT,
    venue_id BIGINT,
    home_team_id BIGINT,
    away_team_id BIGINT,
    home_score INT,
    away_score INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_mlbapi_game_unique
        UNIQUE (mlbapi_payload_id, game_pk)
);

COMMENT ON TABLE stg.mlbapi_game IS
    'Staging table extracting game-level data from raw_mlbapi.payload JSONB. '
    'Used for game identity bridging and canonical game table population.';

-- ---------------------------------------------------------------------------
-- Staging table for extracted MLB API person (player) metadata
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.mlbapi_person (
    stg_mlbapi_person_id BIGSERIAL PRIMARY KEY,
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
    height TEXT,
    weight INT,
    active BOOLEAN,
    primary_position_code TEXT,
    primary_position_name TEXT,
    bat_side_code TEXT,
    pitch_hand_code TEXT,
    mlb_debut_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_mlbapi_person_unique
        UNIQUE (mlbapi_payload_id, person_id)
);

COMMENT ON TABLE stg.mlbapi_person IS
    'Staging table extracting person/player data from raw_mlbapi.payload JSONB. '
    'Used for player identity bridging and canonical player table population.';

-- ---------------------------------------------------------------------------
-- Staging table for extracted MLB API team metadata
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.mlbapi_team (
    stg_mlbapi_team_id BIGSERIAL PRIMARY KEY,
    mlbapi_payload_id BIGINT NOT NULL
        REFERENCES raw_mlbapi.payload(mlbapi_payload_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    team_id BIGINT NOT NULL,
    name TEXT,
    team_code TEXT,
    abbreviation TEXT,
    team_name TEXT,
    location_name TEXT,
    league_id BIGINT,
    division_id BIGINT,
    venue_id BIGINT,
    active BOOLEAN,
    first_year_of_play TEXT,
    season INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_mlbapi_team_unique
        UNIQUE (mlbapi_payload_id, team_id)
);

COMMENT ON TABLE stg.mlbapi_team IS
    'Staging table extracting team data from raw_mlbapi.payload JSONB. '
    'Used for team identity bridging and canonical team table population.';

-- ---------------------------------------------------------------------------
-- Indexes for efficient lookup
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS stg_mlbapi_game_gamepk_idx
    ON stg.mlbapi_game (game_pk);

CREATE INDEX IF NOT EXISTS stg_mlbapi_game_date_idx
    ON stg.mlbapi_game (game_date, season);

CREATE INDEX IF NOT EXISTS stg_mlbapi_person_id_idx
    ON stg.mlbapi_person (person_id);

CREATE INDEX IF NOT EXISTS stg_mlbapi_team_id_idx
    ON stg.mlbapi_team (team_id);

-- ---------------------------------------------------------------------------
-- Trigger for updated_at maintenance
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_stg_mlbapi_game_updated_at ON stg.mlbapi_game;
CREATE TRIGGER trg_stg_mlbapi_game_updated_at
    BEFORE UPDATE ON stg.mlbapi_game
    FOR EACH ROW
    EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_mlbapi_person_updated_at ON stg.mlbapi_person;
CREATE TRIGGER trg_stg_mlbapi_person_updated_at
    BEFORE UPDATE ON stg.mlbapi_person
    FOR EACH ROW
    EXECUTE FUNCTION util.stg_touch_updated_at();

DROP TRIGGER IF EXISTS trg_stg_mlbapi_team_updated_at ON stg.mlbapi_team;
CREATE TRIGGER trg_stg_mlbapi_team_updated_at
    BEFORE UPDATE ON stg.mlbapi_team
    FOR EACH ROW
    EXECUTE FUNCTION util.stg_touch_updated_at();

COMMIT;