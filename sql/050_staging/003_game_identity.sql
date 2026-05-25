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

COMMIT;