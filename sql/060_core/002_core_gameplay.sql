BEGIN;

-- 1. Canonical Game Matrix Table
CREATE TABLE IF NOT EXISTS core.games (
    game_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id        BIGINT NOT NULL
        REFERENCES core.venue(venue_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    home_team_id    BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    away_team_id    BIGINT NOT NULL
        REFERENCES core.team(team_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    game_date       DATE NOT NULL,
    season          INT NOT NULL,
    home_score      SMALLINT DEFAULT 0,
    away_score      SMALLINT DEFAULT 0,
    official_status VARCHAR(20) NOT NULL, -- 'preview', 'live', 'final'
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE core.games IS 'Canonical game entity linking venue and teams.';

-- 2. Decoupled Plate Appearance Event Layer (Dense Event Grain)
CREATE TABLE IF NOT EXISTS core.plate_appearances (
    plate_appearance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id             UUID NOT NULL
        REFERENCES core.games(game_id)
        ON DELETE RESTRICT,
    batter_id           BIGINT NOT NULL
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT, -- Resolved canonical player link
    pitcher_id          BIGINT NOT NULL
        REFERENCES core.player(player_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT, -- Resolved canonical player link
    inning              SMALLINT NOT NULL,
    half_inning         CHAR(1) NOT NULL CHECK (half_inning IN ('T', 'B')),
    outs_before         SMALLINT NOT NULL CHECK (outs_before BETWEEN 0 AND 2),
    pa_sequence_order   SMALLINT NOT NULL, -- Strict incremental game order sorting
    event_result_code   VARCHAR(30) NOT NULL, -- e.g., 'strikeout', 'walk', 'single'
    data_source_lineage VARCHAR(30) NOT NULL, -- 'retrosheet', 'mlb_api'
    workspace_id        UUID NULL,             -- Supports enterprise RLS multi-tenancy
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE core.plate_appearances IS 'Plate appearance facts, one row per PA, decoupled from pitch telemetry.';

-- 3. Pitch Level/Telemetry Array (Granular Physical Sub-Layer)
CREATE TABLE IF NOT EXISTS core.pitches (
    pitch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plate_appearance_id UUID NOT NULL
        REFERENCES core.plate_appearances(plate_appearance_id)
        ON DELETE CASCADE,
    pitch_sequence_num  SMALLINT NOT NULL, -- 1st pitch, 2nd pitch of the plate appearance
    balls_before        SMALLINT NOT NULL CHECK (balls_before BETWEEN 0 AND 3),
    strikes_before      SMALLINT NOT NULL CHECK (strikes_before BETWEEN 0 AND 2),
    pitch_type          CHAR(2),           -- 'FF', 'SL', 'CH', 'CU'
    pitch_call          CHAR(1),           -- 'S' (swinging strike), 'C' (called strike), 'B' (ball), 'X' (in play)
    -- Statcast physical tracking block (nullable to guarantee multi-era compatibility)
    release_velocity    NUMERIC(4,1),
    spin_rate           SMALLINT,
    induced_vertical_break NUMERIC(4,2),
    horizontal_break    NUMERIC(4,2),
    plate_x             NUMERIC(4,2),
    plate_z             NUMERIC(4,2),
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uniq_pitch_per_pa UNIQUE (plate_appearance_id, pitch_sequence_num)
);

COMMENT ON TABLE core.pitches IS 'Pitch telemetry linked to a plate appearance; sparse for historical eras.';

COMMIT;
