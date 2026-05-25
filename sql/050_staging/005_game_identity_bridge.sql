BEGIN;

CREATE TABLE IF NOT EXISTS staging.game_identity_bridge (
    canonical_game_id UUID NOT NULL DEFAULT gen_random_uuid(),
    source_system     VARCHAR(30) NOT NULL, -- 'retrosheet', 'mlb_api', 'statcast'
    source_game_key   VARCHAR(50) NOT NULL, -- e.g., 'BOS202604010' or '747124'
    season            INT NOT NULL,
    game_date         DATE NOT NULL,
    home_team_code    CHAR(3) NOT NULL,
    away_team_code    CHAR(3) NOT NULL,
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT pk_game_identity_bridge PRIMARY KEY (source_system, source_game_key)
);

CREATE INDEX IF NOT EXISTS idx_stg_game_bridge_canonical 
ON staging.game_identity_bridge(canonical_game_id);

COMMIT;
