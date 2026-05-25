BEGIN;

CREATE TABLE IF NOT EXISTS stg.game_identity (
    game_identity_id BIGSERIAL PRIMARY KEY,
    mlbam_game_pk BIGINT,
    retrosheet_game_id TEXT,
    home_team_id BIGINT REFERENCES stg.team_identity(team_identity_id),
    away_team_id BIGINT REFERENCES stg.team_identity(team_identity_id),
    venue_id BIGINT REFERENCES stg.venue_identity(venue_identity_id),
    doubleheader_sequence SMALLINT,
    scheduled_start_time TIMESTAMPTZ,
    game_date DATE NOT NULL,
    season INT NOT NULL,
    identity_confidence_score NUMERIC(6,3),
    identity_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE stg.game_identity IS
    'Staging table for cross-source game identity, containing raw keys from source systems and links to resolved team/venue identities.';

-- Note: Trigger for updated_at is created in sql/080_functions/005_staging_functions.sql
-- This ensures the function util.stg_touch_updated_at() exists when the trigger is defined

COMMENT ON COLUMN stg.game_identity.mlbam_game_pk IS
    'MLB Stats API numeric game identifier (gamePk). Null for pre-API historical games.';

COMMENT ON COLUMN stg.game_identity.retrosheet_game_id IS
    'Retrosheet game ID format: HHH + YYYYMMDD + N (e.g. BOS2024051201). Null for live/future games.';

COMMENT ON COLUMN stg.game_identity.identity_confidence_score IS
    'Cross-source identity match confidence: 1.000=exact, 0.950=name+dob, 0.700=name only, 0.000=no match.';

COMMIT;