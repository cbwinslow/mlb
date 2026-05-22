-- =============================================================================
-- Chadwick Register: Raw Staging Table, Seed Function, Weekly Refresh,
-- Divergence Report, and Unmatched-Player View
--
-- The Chadwick Register is the authoritative free cross-source player identity
-- file for baseball. It maps MLBAM, Retrosheet, Baseball-Reference, FanGraphs,
-- and Lahman IDs for every known player.
--
-- Source:  https://github.com/chadwickbureau/register
-- Format:  CSV, updated weekly (people.csv)
-- License: CC0 (public domain)
--
-- Objects in this file:
--   1.  raw.chadwick_register          — staging table for raw CSV imports
--   2.  stg.fn_seed_from_chadwick()    — upserts Chadwick rows into stg.player_identity
--   3.  stg.fn_refresh_chadwick()      — full weekly refresh pipeline
--   4.  stg.fn_chadwick_divergence_report() — flags disagreements vs stg.player_identity
--   5.  stg.v_chadwick_unmatched       — Chadwick rows with no stg match (net-new players)
--
-- Run order: apply after 013_identity_validation_functions.sql and
--            014_identity_reconciliation_functions.sql.
--
-- Weekly cron example (after downloading people.csv to /tmp/chadwick_people.csv):
--   \COPY raw.chadwick_register FROM '/tmp/chadwick_people.csv' CSV HEADER;
--   SELECT stg.fn_refresh_chadwick();
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. raw.chadwick_register
--
-- Staging table that receives the raw Chadwick people.csv import before
-- any normalisation. Column names match the Chadwick CSV headers exactly.
-- Truncated and reloaded on each weekly refresh.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw.chadwick_register (
    -- Chadwick internal key (stable across releases)
    key_person              TEXT,

    -- Cross-source ID columns (all TEXT; some may be empty strings in the CSV)
    key_uuid                TEXT,
    key_mlbam               TEXT,           -- cast to BIGINT when seeding
    key_retro               TEXT,
    key_bbref               TEXT,
    key_bbref_minors        TEXT,
    key_fangraphs           TEXT,           -- cast to BIGINT when seeding
    key_npb                 TEXT,
    key_sr_nfl              TEXT,
    key_sr_nba              TEXT,
    key_sr_nhl              TEXT,
    key_findagrave          TEXT,
    key_lahman              TEXT,

    -- Biographical fields
    name_last               TEXT,
    name_first              TEXT,
    name_given              TEXT,
    name_suffix             TEXT,
    name_matrilineal        TEXT,
    name_nick               TEXT,
    birth_year              TEXT,
    birth_month             TEXT,
    birth_day               TEXT,
    death_year              TEXT,
    death_month             TEXT,
    death_day               TEXT,
    pro_played_first        TEXT,
    pro_played_last         TEXT,
    mlb_played_first        TEXT,
    mlb_played_last         TEXT,
    col_played_first        TEXT,
    col_played_last         TEXT,
    pro_managed_first       TEXT,
    pro_managed_last        TEXT,
    pro_umpired_first       TEXT,
    pro_umpired_last        TEXT,

    -- Load metadata
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index on key_mlbam for the seed join
CREATE INDEX IF NOT EXISTS raw_chadwick_mlbam_idx
    ON raw.chadwick_register (key_mlbam)
    WHERE key_mlbam IS NOT NULL AND key_mlbam <> '';

-- Index on key_retro for reverse lookups
CREATE INDEX IF NOT EXISTS raw_chadwick_retro_idx
    ON raw.chadwick_register (key_retro)
    WHERE key_retro IS NOT NULL AND key_retro <> '';

COMMENT ON TABLE raw.chadwick_register IS
    'Raw Chadwick Bureau people.csv import. Truncated and reloaded weekly. '
    'Do not join fact tables to this table directly — use stg.player_identity instead. '
    'Source: https://github.com/chadwickbureau/register (CC0).';


-- ---------------------------------------------------------------------------
-- 2. stg.safe_make_date — Helper function for defensive date construction
--
-- Creates a DATE from year/month/day integers, returning NULL on invalid dates
-- (e.g., month=13, day=32) instead of raising an exception.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.safe_make_date(
    p_year  INT,
    p_month INT,
    p_day   INT
)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN make_date(p_year, p_month, p_day);
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION stg.safe_make_date(INT, INT, INT) IS
    'Defensive wrapper around make_date() that returns NULL for invalid dates instead of raising an exception.';


-- ---------------------------------------------------------------------------
-- 3. stg.fn_seed_from_chadwick
--
-- Upserts rows from raw.chadwick_register into stg.player_identity.
--
-- Merge logic:
--   - Rows with a valid key_mlbam (numeric) are the primary target.
--   - On conflict (mlbam_player_id already exists): updates cross-source IDs
--     and biographical fields ONLY when the incoming value is non-NULL and
--     the current stored value IS NULL (never overwrites known-good data).
--   - Sets identity_confidence_score = 0.85 and identity_source = 'chadwick'
--     for freshly seeded rows. Existing rows keep their score if already >= 0.85.
--   - Rows missing key_mlbam are skipped (logged to resolution_log).
--
-- Returns a summary row with counts of inserted, updated, and skipped rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_seed_from_chadwick(
    p_source_tag    TEXT    DEFAULT 'chadwick:weekly'
)
RETURNS TABLE (
    rows_inspected  BIGINT,
    rows_inserted   BIGINT,
    rows_updated    BIGINT,
    rows_skipped    BIGINT,
    run_at          TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_inspected     BIGINT := 0;
    v_inserted      BIGINT := 0;
    v_updated       BIGINT := 0;
    v_skipped       BIGINT := 0;
    v_full_name     TEXT;
    r               RECORD;
BEGIN
    FOR r IN
        SELECT
            CASE
                WHEN NULLIF(TRIM(c.key_mlbam), '') ~ '^[0-9]+$'
                THEN NULLIF(TRIM(c.key_mlbam), '')::BIGINT
                ELSE NULL
            END                                             AS mlbam_id,
            NULLIF(TRIM(c.key_retro),      '')              AS retro_id,
            NULLIF(TRIM(c.key_bbref),      '')              AS bbref_id,
            CASE
                WHEN NULLIF(TRIM(c.key_fangraphs), '') ~ '^[0-9]+$'
                THEN NULLIF(TRIM(c.key_fangraphs), '')::BIGINT
                ELSE NULL
            END                                             AS fangraphs_id,
            NULLIF(TRIM(c.key_lahman),     '')              AS lahman_id,
            TRIM(CONCAT_WS(' ',
                NULLIF(TRIM(c.name_first), ''),
                NULLIF(TRIM(c.name_last),  '')
            ))                                              AS full_name,
            CASE
                WHEN c.birth_year  ~ '^[0-9]{4}$'
                 AND c.birth_month ~ '^[0-9]{1,2}$'
                 AND c.birth_day   ~ '^[0-9]{1,2}$'
                THEN stg.safe_make_date(
                    c.birth_year::INT,
                    c.birth_month::INT,
                    c.birth_day::INT
                )
                ELSE NULL
            END                                             AS birth_date
        FROM raw.chadwick_register c
    LOOP
        v_inspected := v_inspected + 1;

        -- Skip rows with no MLBAM id — no way to link to Statcast data
        IF r.mlbam_id IS NULL THEN
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        INSERT INTO stg.player_identity (
            mlbam_player_id,
            retrosheet_player_id,
            bbref_player_id,
            fangraphs_player_id,
            lahman_player_id,
            full_name,
            birth_date,
            identity_confidence_score,
            identity_source
        )
        VALUES (
            r.mlbam_id,
            r.retro_id,
            r.bbref_id,
            r.fangraphs_id,
            r.lahman_id,
            NULLIF(r.full_name, ''),
            r.birth_date,
            0.85,
            p_source_tag
        )
        ON CONFLICT (mlbam_player_id)
        WHERE mlbam_player_id IS NOT NULL
        DO UPDATE SET
            -- Only fill in NULLs; never overwrite known-good data
            retrosheet_player_id  = COALESCE(stg.player_identity.retrosheet_player_id,  EXCLUDED.retrosheet_player_id),
            bbref_player_id       = COALESCE(stg.player_identity.bbref_player_id,       EXCLUDED.bbref_player_id),
            fangraphs_player_id   = COALESCE(stg.player_identity.fangraphs_player_id,   EXCLUDED.fangraphs_player_id),
            lahman_player_id      = COALESCE(stg.player_identity.lahman_player_id,      EXCLUDED.lahman_player_id),
            full_name             = COALESCE(stg.player_identity.full_name,             EXCLUDED.full_name),
            birth_date            = COALESCE(stg.player_identity.birth_date,            EXCLUDED.birth_date),
            -- Upgrade confidence only if current score is lower than Chadwick baseline
            identity_confidence_score = GREATEST(
                stg.player_identity.identity_confidence_score,
                EXCLUDED.identity_confidence_score
            ),
            -- Update source tag to reflect latest refresh
            identity_source = EXCLUDED.identity_source
        ;

        IF FOUND THEN
            -- Distinguish insert vs update via xmax heuristic.
            -- Note: xmax = 0 reliably indicates an insert only within the same transaction.
            -- This heuristic could be racy if another session modifies the row between
            -- INSERT and SELECT. We assume single-threaded execution (weekly batch or
            -- single enrichment worker) with no concurrent writers to stg.player_identity.
            IF (SELECT xmax = 0 FROM stg.player_identity WHERE mlbam_player_id = r.mlbam_id LIMIT 1) THEN
                v_inserted := v_inserted + 1;
            ELSE
                v_updated := v_updated + 1;
            END IF;
        END IF;
    END LOOP;

    -- Log summary to resolution_log
    INSERT INTO stg.player_identity_resolution_log (
        trigger_source, mlbam_player_id, player_name, action_taken, note
    ) VALUES (
        'fn_seed_from_chadwick',
        0,
        NULL,
        'SEED_COMPLETE',
        format(
            'inspected=%s inserted=%s updated=%s skipped=%s source=%s',
            v_inspected, v_inserted, v_updated, v_skipped, p_source_tag
        )
    );

    RETURN QUERY
    SELECT v_inspected, v_inserted, v_updated, v_skipped, NOW();
END;
$$;

COMMENT ON FUNCTION stg.fn_seed_from_chadwick(TEXT) IS
    'Upserts raw.chadwick_register into stg.player_identity. '
    'Only fills NULL columns — never overwrites known-good existing IDs. '
    'Sets confidence=0.85 for Chadwick-seeded rows. '
    'Call after loading raw.chadwick_register from the weekly people.csv. '
    'Returns summary counts. '
    'Example: SELECT * FROM stg.fn_seed_from_chadwick();';


-- ---------------------------------------------------------------------------
-- 4. stg.fn_refresh_chadwick
--
-- Full weekly refresh pipeline:
--   1. Expects caller to have truncated raw.chadwick_register and loaded
--      the new CSV via \COPY or Python psycopg2 COPY_FROM before calling.
--   2. Calls fn_seed_from_chadwick() to propagate changes to stg.player_identity.
--   3. Logs the full result to stg.player_identity_resolution_log.
--   4. Returns the seed summary.
--
-- The Python enrichment worker (scripts/enrich_player_identity.py) calls this
-- after downloading and loading the latest Chadwick people.csv.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_refresh_chadwick()
RETURNS TABLE (
    rows_inspected  BIGINT,
    rows_inserted   BIGINT,
    rows_updated    BIGINT,
    rows_skipped    BIGINT,
    run_at          TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_result RECORD;
BEGIN
    -- Seed / upsert from raw staging table (caller loaded the CSV already)
    SELECT * INTO v_result FROM stg.fn_seed_from_chadwick('chadwick:weekly');

    RETURN QUERY
    SELECT
        v_result.rows_inspected,
        v_result.rows_inserted,
        v_result.rows_updated,
        v_result.rows_skipped,
        v_result.run_at;
END;
$$;

COMMENT ON FUNCTION stg.fn_refresh_chadwick() IS
    'Weekly Chadwick refresh pipeline. '
    'Caller must truncate and load raw.chadwick_register from the latest people.csv first. '
    'Calls fn_seed_from_chadwick() and returns a summary. '
    'Typical cron: download people.csv -> TRUNCATE + COPY into raw.chadwick_register -> SELECT stg.fn_refresh_chadwick();';


-- ---------------------------------------------------------------------------
-- 4. stg.fn_chadwick_divergence_report
--
-- Compares stg.player_identity against the current raw.chadwick_register.
-- Returns rows where our stored IDs disagree with Chadwick's published IDs.
-- Each row includes a suggested_action — a ready-to-run UPDATE statement.
--
-- This is a wrapper around stg.fn_cross_validate_identities() that adds
-- Chadwick-specific suggested SQL for easy copy-paste remediation.
--
-- Example:
--   SELECT * FROM stg.fn_chadwick_divergence_report()
--   WHERE divergence_type != 'OK';
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_chadwick_divergence_report()
RETURNS TABLE (
    player_identity_id      BIGINT,
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    divergence_type         TEXT,
    our_value               TEXT,
    chadwick_value          TEXT,
    suggested_action        TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        d.divergence_type,
        d.our_value,
        d.chadwick_value,
        format(
            'CALL stg.update_player_identity(%s, retro := %L, bbref := %L, fg := %L, lahman := %L, conf := 0.95, src := ''chadwick:correction'');',
            pi.player_identity_id,
            CASE WHEN d.divergence_type = 'retrosheet_mismatch'
                 THEN d.chadwick_value ELSE pi.retrosheet_player_id END,
            CASE WHEN d.divergence_type = 'bbref_mismatch'
                 THEN d.chadwick_value ELSE pi.bbref_player_id END,
            CASE WHEN d.divergence_type = 'fangraphs_mismatch'
                 THEN d.chadwick_value ELSE pi.fangraphs_player_id END,
            CASE WHEN d.divergence_type = 'lahman_mismatch'
                 THEN d.chadwick_value ELSE pi.lahman_player_id END
        )                                       AS suggested_action
    FROM stg.fn_cross_validate_identities() d
    JOIN stg.player_identity pi
        ON pi.player_identity_id = d.player_identity_id
    WHERE d.divergence_type <> 'OK'
    ORDER BY pi.mlbam_player_id;
$$;

COMMENT ON FUNCTION stg.fn_chadwick_divergence_report() IS
    'Compares stg.player_identity against raw.chadwick_register. '
    'Returns rows with divergent IDs and a ready-to-run CALL suggested_action. '
    'Run after each weekly Chadwick refresh. '
    'Example: SELECT * FROM stg.fn_chadwick_divergence_report() WHERE divergence_type != ''OK'';';


-- ---------------------------------------------------------------------------
-- 5. stg.v_chadwick_unmatched
--
-- Shows Chadwick rows that have a key_mlbam but no matching row in
-- stg.player_identity. These are net-new players in the Chadwick file
-- that we have never seen in Statcast data. Running fn_seed_from_chadwick
-- will clear this view (all matched rows go to 0 rows).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg.v_chadwick_unmatched AS
WITH valid_chadwick AS (
    SELECT
        c.key_mlbam::BIGINT     AS mlbam_player_id,
        CONCAT_WS(' ',
            NULLIF(TRIM(c.name_first), ''),
            NULLIF(TRIM(c.name_last),  '')
        )                        AS full_name,
        c.key_retro             AS retrosheet_player_id,
        c.key_bbref             AS bbref_player_id,
        c.key_fangraphs         AS fangraphs_player_id,
        c.key_lahman            AS lahman_player_id,
        c.mlb_played_first,
        c.mlb_played_last,
        c.loaded_at
    FROM raw.chadwick_register c
    WHERE c.key_mlbam IS NOT NULL
      AND c.key_mlbam <> ''
      AND c.key_mlbam ~ '^[0-9]+$'
)
SELECT
    vc.mlbam_player_id,
    vc.full_name,
    vc.retrosheet_player_id,
    vc.bbref_player_id,
    vc.fangraphs_player_id,
    vc.lahman_player_id,
    vc.mlb_played_first,
    vc.mlb_played_last,
    vc.loaded_at
FROM valid_chadwick vc
LEFT JOIN stg.player_identity pi
    ON pi.mlbam_player_id = vc.mlbam_player_id
WHERE pi.player_identity_id IS NULL
ORDER BY vc.mlb_played_last DESC NULLS LAST;

COMMENT ON VIEW stg.v_chadwick_unmatched IS
    'Chadwick rows with a valid MLBAM id that have no match in stg.player_identity. '
    'These are players Chadwick knows about but we have never seen in Statcast. '
    'Running SELECT stg.fn_seed_from_chadwick() will insert them and clear this view.';


COMMIT;
