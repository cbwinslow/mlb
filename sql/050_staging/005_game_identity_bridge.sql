BEGIN;

CREATE TABLE IF NOT EXISTS stg.game_identity_bridge (
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

COMMENT ON TABLE stg.game_identity_bridge IS
    'Canonical game identity bridge mapping source-system game keys to a stable UUID. '
    'On conflict (same source_system + source_game_key), the existing canonical_game_id '
    'is preserved so cross-source joins remain stable. '
    'To merge two source rows for the same real-world game, UPDATE the canonical_game_id '
    'of the secondary row to match the primary source row UUID.';

COMMENT ON COLUMN stg.game_identity_bridge.canonical_game_id IS
    'Stable cross-source game UUID. Defaults to gen_random_uuid() on first insert; '
    'never overwritten on upsert (EXCLUDED.canonical_game_id is ignored via DO NOTHING '
    'or explicit COALESCE) so the first-seen value is authoritative.';

CREATE INDEX IF NOT EXISTS idx_stg_game_bridge_canonical
    ON stg.game_identity_bridge (canonical_game_id);

CREATE INDEX IF NOT EXISTS idx_stg_game_bridge_date
    ON stg.game_identity_bridge (game_date, season);

COMMIT;
