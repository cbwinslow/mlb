BEGIN;

CREATE TABLE IF NOT EXISTS stg.player_identity (
    player_identity_id BIGSERIAL PRIMARY KEY,
    mlbam_player_id BIGINT,
    retrosheet_player_id TEXT,
    lahman_player_id TEXT,
    bbref_player_id TEXT,
    fangraphs_player_id TEXT,
    first_name TEXT,
    last_name TEXT,
    full_name TEXT,
    bats TEXT,
    throws TEXT,
    birth_date DATE,
    mlb_debut_date DATE,
    is_active BOOLEAN,
    identity_confidence_score NUMERIC(6,3),
    identity_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_player_identity_confidence_chk
        CHECK (
            identity_confidence_score IS NULL
            OR (identity_confidence_score >= 0 AND identity_confidence_score <= 1)
        )
);

COMMENT ON TABLE stg.player_identity IS
    'Cross-source player identity bridge across MLBAM, Retrosheet, Lahman, Baseball Reference, and FanGraphs identifiers.';

CREATE TABLE IF NOT EXISTS stg.team_identity (
    team_identity_id BIGSERIAL PRIMARY KEY,
    mlbam_team_id BIGINT,
    retrosheet_team_id TEXT,
    lahman_team_id TEXT,
    bbref_team_id TEXT,
    fangraphs_team_id TEXT,
    franchise_id TEXT,
    team_name TEXT,
    city_name TEXT,
    nickname TEXT,
    league_code TEXT,
    first_year INT,
    last_year INT,
    statcast_team_id TEXT,                  -- MLB codes like NYY, LAD (vs retrosheet NYA, LAN)
    identity_confidence_score NUMERIC(6,3),
    identity_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_team_identity_confidence_chk
        CHECK (
            identity_confidence_score IS NULL
            OR (identity_confidence_score >= 0 AND identity_confidence_score <= 1)
        )
);

COMMENT ON TABLE stg.team_identity IS
    'Cross-source team identity bridge across MLBAM, Retrosheet, Lahman, Baseball Reference, and FanGraphs identifiers.';

CREATE TABLE IF NOT EXISTS stg.venue_identity (
    venue_identity_id BIGSERIAL PRIMARY KEY,
    mlbam_venue_id BIGINT,
    retrosheet_park_id TEXT,
    venue_name TEXT,
    city_name TEXT,
    state_name TEXT,
    country_name TEXT,
    tz_name TEXT,
    active_start_date DATE,
    active_end_date DATE,
    identity_confidence_score NUMERIC(6,3),
    identity_source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT stg_venue_identity_confidence_chk
        CHECK (
            identity_confidence_score IS NULL
            OR (identity_confidence_score >= 0 AND identity_confidence_score <= 1)
        )
);

COMMENT ON TABLE stg.venue_identity IS
    'Cross-source venue/park identity bridge, primarily MLBAM venue IDs and Retrosheet park IDs.';

CREATE TABLE IF NOT EXISTS stg.player_identity_candidate (
    player_identity_candidate_id BIGSERIAL PRIMARY KEY,
    source_system_code TEXT NOT NULL,
    source_natural_key TEXT NOT NULL,
    mlbam_player_id BIGINT,
    retrosheet_player_id TEXT,
    lahman_player_id TEXT,
    bbref_player_id TEXT,
    fangraphs_player_id TEXT,
    candidate_name TEXT,
    candidate_birth_date DATE,
    candidate_score NUMERIC(8,5),
    candidate_reason TEXT,
    reviewed_flag BOOLEAN NOT NULL DEFAULT FALSE,
    accepted_flag BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE stg.player_identity_candidate IS
    'Candidate player matches generated during source-bridging, especially when exact IDs are not available upstream.';

COMMIT;