-- =============================================================================
-- 005_chadwick_register_import.sql
--
-- Chadwick Register import table for player identity enrichment lookups.
-- This table is populated from the Chadwick Bureau people.csv and used by
-- the Python enrichment worker for fast O(1) MLBAM ID lookups.
--
-- Source: https://github.com/chadwickbureau/register
-- Column order matches scripts/enrich_player_identity.py COPY statement.
-- Apply after: sql/050_staging/001_identity_bridge.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Chadwick Register import table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.chadwick_register_import (
    key_mlbam       BIGINT PRIMARY KEY,
    key_retro       TEXT,
    key_bbref       TEXT,
    key_fangraphs   TEXT,
    key_lahman      TEXT,
    name_first      TEXT,
    name_last       TEXT,
    name_given      TEXT,
    birth_year      SMALLINT,
    birth_month     SMALLINT,
    birth_day       SMALLINT,
    mlb_played_first SMALLINT,
    mlb_played_last  SMALLINT,
    loaded_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE stg.chadwick_register_import IS
    'Chadwick Bureau Register people.csv loaded for player identity enrichment. '
    'Populated via: COPY stg.chadwick_register_import FROM ... CSV HEADER. '
    'Used by baseball.ingestion.enrich_player_identity for fast MLBAM ID lookups. '
    'The enrichment worker loads this into an in-process cache for O(1) resolution.';

-- Indexes for name-based lookups (used when MLBAM ID is unknown)
CREATE INDEX IF NOT EXISTS stg_chadwick_import_name_idx
    ON stg.chadwick_register_import (name_last, name_first);

CREATE INDEX IF NOT EXISTS stg_chadwick_import_retro_idx
    ON stg.chadwick_register_import (key_retro)
    WHERE key_retro IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_chadwick_import_bbref_idx
    ON stg.chadwick_register_import (key_bbref)
    WHERE key_bbref IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_chadwick_import_fangraphs_idx
    ON stg.chadwick_register_import (key_fangraphs)
    WHERE key_fangraphs IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_chadwick_import_lahman_idx
    ON stg.chadwick_register_import (key_lahman)
    WHERE key_lahman IS NOT NULL;

COMMIT;