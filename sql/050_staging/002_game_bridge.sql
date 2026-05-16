BEGIN;

CREATE TABLE IF NOT EXISTS stg.game_identity (
    game_identity_id BIGSERIAL PRIMARY KEY,
    mlbam_game_pk BIGINT,
    retrosheet_game_id TEXT,
    game_date DATE,
    season INT,
    game_type_code TEXT,
    doubleheader_sequence SMALLINT,
    home_team_identity_id BIGINT
        REFERENCES stg.team_identity(team_identity_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    away_team_identity_id BIGINT
        REFERENCES stg.team_identity(team_identity_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    venue_identity_id BIGINT
        REFERENCES stg.venue_identity(venue_identity_id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,
    scheduled_start_time TIMESTAMPTZ,
    identity_confidence_score NUMERIC(6,3),
    identity_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_game_identity_confidence_chk
        CHECK (
            identity_confidence_score IS NULL
            OR (identity_confidence_score >= 0 AND identity_confidence_score <= 1)
        )
);

COMMENT ON TABLE stg.game_identity IS
    'Cross-source game bridge between MLBAM gamePk and Retrosheet game_id, plus bridged team and venue identities.';

CREATE TABLE IF NOT EXISTS stg.game_source_link (
    game_source_link_id BIGSERIAL PRIMARY KEY,
    game_identity_id BIGINT NOT NULL
        REFERENCES stg.game_identity(game_identity_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,
    source_system_code TEXT NOT NULL,
    source_table_name TEXT NOT NULL,
    source_row_pk TEXT NOT NULL,
    source_natural_key TEXT,
    linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_game_source_link_unique
        UNIQUE (game_identity_id, source_system_code, source_table_name, source_row_pk)
);

COMMENT ON TABLE stg.game_source_link IS
    'Traceability table linking bridged games back to specific raw-source rows.';

CREATE TABLE IF NOT EXISTS stg.game_identity_candidate (
    game_identity_candidate_id BIGSERIAL PRIMARY KEY,
    mlbam_game_pk BIGINT,
    retrosheet_game_id TEXT,
    candidate_game_date DATE,
    candidate_home_team_id TEXT,
    candidate_away_team_id TEXT,
    candidate_score NUMERIC(8,5),
    candidate_reason TEXT,
    reviewed_flag BOOLEAN NOT NULL DEFAULT FALSE,
    accepted_flag BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE stg.game_identity_candidate IS
    'Candidate game matches between MLB StatsAPI and Retrosheet when deterministic linking is not yet locked.';

COMMIT;