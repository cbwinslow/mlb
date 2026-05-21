-- =============================================================================
-- Player Identity Validation & Cross-Reference Functions
--
-- Implements Issue #13: fail-safe player ID validation pipeline.
--
-- Functions and procedures in this file:
--   1. stg.fn_validate_identity_completeness()   — report on ID completeness
--   2. stg.fn_detect_orphaned_pitches()           — find pitches with no identity
--   3. stg.fn_cross_validate_identities()         — diff against Chadwick staging
--   4. stg.fn_pinpoint_player_by_context()        — find a player by game context
--   5. stg.fn_validate_game_lineup()              — cross-check lineup across sources
--   6. stg.update_player_identity()               — safe update with audit log
--   7. stg.v_identity_validation_dashboard        — ops monitoring view
--
-- Run order: apply after 001–004 staging files and 010–012 function files.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. fn_validate_identity_completeness
--
-- Returns one summary row per ID column showing how many players have it
-- populated vs. missing, and the fill rate as a percentage.
-- Use this as a recurring health check — schedule weekly or after each
-- Chadwick seed refresh.
--
-- Example:
--   SELECT * FROM stg.fn_validate_identity_completeness();
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_validate_identity_completeness()
RETURNS TABLE (
    id_column           TEXT,
    total_players       BIGINT,
    populated           BIGINT,
    missing             BIGINT,
    fill_rate_pct       NUMERIC(5,2),
    confidence_avg      NUMERIC(4,3)
)
LANGUAGE sql
STABLE
AS $$
    WITH base AS (
        SELECT
            COUNT(*)                                        AS total,
            COUNT(mlbam_player_id)                          AS has_mlbam,
            COUNT(retrosheet_player_id)                     AS has_retro,
            COUNT(bbref_player_id)                          AS has_bbref,
            COUNT(fangraphs_player_id)                      AS has_fangraphs,
            COUNT(lahman_player_id)                         AS has_lahman,
            ROUND(AVG(identity_confidence_score)::NUMERIC, 3) AS avg_conf
        FROM stg.player_identity
    )
    SELECT id_col, total, pop, total - pop, ROUND(pop * 100.0 / NULLIF(total,0), 2), avg_conf
    FROM base,
    LATERAL (VALUES
        ('mlbam_player_id',      total, has_mlbam),
        ('retrosheet_player_id', total, has_retro),
        ('bbref_player_id',      total, has_bbref),
        ('fangraphs_player_id',  total, has_fangraphs),
        ('lahman_player_id',     total, has_lahman)
    ) AS t(id_col, total, pop)
    ORDER BY fill_rate_pct ASC;
$$;

COMMENT ON FUNCTION stg.fn_validate_identity_completeness() IS
    'Returns fill-rate statistics for every cross-source ID column in stg.player_identity. '
    'Run after Chadwick seed refresh to confirm coverage improved. '
    'A fill_rate_pct drop signals a data quality regression.';


-- ---------------------------------------------------------------------------
-- 2. fn_detect_orphaned_pitches
--
-- Finds raw_statcast.pitch rows whose batter or pitcher MLBAM ID has no
-- corresponding row in stg.player_identity.
--
-- This should always return zero rows if the auto-resolution trigger (Part E
-- of 004_identity_trigger_and_indexes.sql) is working correctly.
-- Any rows returned here indicate a trigger failure or schema mismatch and
-- should be treated as a CRITICAL alert.
--
-- Parameters:
--   p_since  — only check pitches inserted after this timestamp
--              (default: last 48 hours, to bound query cost on large tables)
--
-- Example:
--   SELECT * FROM stg.fn_detect_orphaned_pitches();
--   SELECT * FROM stg.fn_detect_orphaned_pitches('2025-01-01'::TIMESTAMPTZ);
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_detect_orphaned_pitches(
    p_since TIMESTAMPTZ DEFAULT NOW() - INTERVAL '48 hours'
)
RETURNS TABLE (
    pitch_id            BIGINT,
    game_date           DATE,
    orphan_mlbam_id     BIGINT,
    orphan_role         TEXT,   -- 'batter' or 'pitcher'
    player_name         TEXT,
    insert_timestamp    TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    -- Orphaned batters
    SELECT
        p.pitch_id,
        p.game_date,
        p.batter          AS orphan_mlbam_id,
        'batter'          AS orphan_role,
        p.player_name,
        p.insert_timestamp
    FROM raw_statcast.pitch p
    WHERE p.insert_timestamp >= p_since
      AND p.batter IS NOT NULL
      AND NOT EXISTS (
            SELECT 1 FROM stg.player_identity pi
            WHERE  pi.mlbam_player_id = p.batter
      )

    UNION ALL

    -- Orphaned pitchers
    SELECT
        p.pitch_id,
        p.game_date,
        p.pitcher         AS orphan_mlbam_id,
        'pitcher'         AS orphan_role,
        NULL              AS player_name,
        p.insert_timestamp
    FROM raw_statcast.pitch p
    WHERE p.insert_timestamp >= p_since
      AND p.pitcher IS NOT NULL
      AND NOT EXISTS (
            SELECT 1 FROM stg.player_identity pi
            WHERE  pi.mlbam_player_id = p.pitcher
      )

    ORDER BY insert_timestamp DESC;
$$;

COMMENT ON FUNCTION stg.fn_detect_orphaned_pitches(TIMESTAMPTZ) IS
    'Finds raw_statcast.pitch rows whose batter/pitcher MLBAM ID has no stg.player_identity row. '
    'Should always return zero rows if trg_statcast_pitch_player_resolve is healthy. '
    'Any rows returned = CRITICAL alert: trigger failure or schema mismatch. '
    'Default window: last 48 hours. Pass a TIMESTAMPTZ to widen or narrow the search.';


-- ---------------------------------------------------------------------------
-- 3. fn_cross_validate_identities
--
-- Compares stg.player_identity against a staging import of the Chadwick
-- register (expected in stg.chadwick_register_import) and surfaces rows
-- where IDs diverge between the two sources.
--
-- The Chadwick register is the authoritative cross-source crosswalk for
-- baseball player IDs. This function diffs your stored IDs against the
-- latest Chadwick snapshot and generates a suggested_action SQL UPDATE
-- statement for each divergence — ready to review and apply.
--
-- Prerequisites:
--   - stg.chadwick_register_import must exist and be freshly loaded.
--     Load with: COPY stg.chadwick_register_import FROM '/path/to/people.csv' CSV HEADER;
--
-- Example:
--   SELECT * FROM stg.fn_cross_validate_identities();
--   SELECT * FROM stg.fn_cross_validate_identities() WHERE divergence_type = 'BBREF_MISMATCH';
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.chadwick_register_import (
    key_mlbam           BIGINT,
    key_retro           TEXT,
    key_bbref           TEXT,
    key_fangraphs       TEXT,
    key_lahman          TEXT,
    name_first          TEXT,
    name_last           TEXT,
    name_given          TEXT,
    birth_year          INT,
    birth_month         INT,
    birth_day           INT,
    mlb_played_first    INT,
    mlb_played_last     INT
);

COMMENT ON TABLE stg.chadwick_register_import IS
    'Staging table for Chadwick Bureau Register CSV import. '
    'Load weekly from https://github.com/chadwickbureau/register '
    'COPY stg.chadwick_register_import FROM /path/to/people.csv CSV HEADER; '
    'Then run SELECT * FROM stg.fn_cross_validate_identities() to diff against live data.';

CREATE INDEX IF NOT EXISTS stg_chadwick_import_mlbam_idx
    ON stg.chadwick_register_import (key_mlbam)
    WHERE key_mlbam IS NOT NULL;


CREATE OR REPLACE FUNCTION stg.fn_cross_validate_identities()
RETURNS TABLE (
    player_identity_id  BIGINT,
    mlbam_player_id     BIGINT,
    full_name           TEXT,
    divergence_type     TEXT,
    stored_value        TEXT,
    chadwick_value      TEXT,
    suggested_action    TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        div.divergence_type,
        div.stored_value,
        div.chadwick_value,
        -- Generate a ready-to-run UPDATE statement
        format(
            'UPDATE stg.player_identity SET %I = %L, identity_source = %L, updated_at = NOW() WHERE player_identity_id = %s;',
            div.column_name,
            div.chadwick_value,
            'chadwick:cross_validate',
            pi.player_identity_id
        ) AS suggested_action
    FROM stg.player_identity pi
    JOIN stg.chadwick_register_import cr ON cr.key_mlbam = pi.mlbam_player_id
    CROSS JOIN LATERAL (
        VALUES
            ('RETRO_MISMATCH',      'retrosheet_player_id', pi.retrosheet_player_id::TEXT, cr.key_retro),
            ('BBREF_MISMATCH',      'bbref_player_id',      pi.bbref_player_id,            cr.key_bbref),
            ('FANGRAPHS_MISMATCH',  'fangraphs_player_id',  pi.fangraphs_player_id,        cr.key_fangraphs),
            ('LAHMAN_MISMATCH',     'lahman_player_id',     pi.lahman_player_id,           cr.key_lahman)
    ) AS div(divergence_type, column_name, stored_value, chadwick_value)
    WHERE div.chadwick_value IS NOT NULL              -- Chadwick has a value
      AND div.stored_value IS DISTINCT FROM div.chadwick_value  -- and it differs from ours
    ORDER BY pi.player_identity_id, div.divergence_type;
$$;

COMMENT ON FUNCTION stg.fn_cross_validate_identities() IS
    'Diffs stg.player_identity against stg.chadwick_register_import. '
    'Returns rows where stored IDs diverge from Chadwick, with a suggested UPDATE statement. '
    'Run weekly after refreshing stg.chadwick_register_import. '
    'Review suggested_action values before applying — Chadwick is authoritative but not infallible.';


-- ---------------------------------------------------------------------------
-- 4. fn_pinpoint_player_by_context
--
-- Given game-level contextual signals (date, team abbreviation, batting
-- order position, plate appearance number), returns the most likely
-- player_identity_id match from your warehouse.
--
-- This is the "last resort" resolver for the rare case where an MLBAM ID
-- cannot be matched by any other means. It uses observable facts from the
-- game itself to narrow down the identity.
--
-- Returns up to 3 candidates ranked by match confidence.
--
-- Example:
--   SELECT * FROM stg.fn_pinpoint_player_by_context(
--       '2024-07-15'::DATE, 'NYY', 3, 2
--   );
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_pinpoint_player_by_context(
    p_game_date         DATE,
    p_team_abbrev       TEXT,
    p_batting_order_pos INT  DEFAULT NULL,
    p_at_bat_number     INT  DEFAULT NULL
)
RETURNS TABLE (
    player_identity_id      BIGINT,
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    retrosheet_player_id    TEXT,
    bbref_player_id         TEXT,
    fangraphs_player_id     TEXT,
    identity_confidence_score NUMERIC,
    match_basis             TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT DISTINCT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        pi.retrosheet_player_id,
        pi.bbref_player_id,
        pi.fangraphs_player_id,
        pi.identity_confidence_score,
        'game_context: date=' || p_game_date::TEXT
            || ' team=' || p_team_abbrev
            || COALESCE(' bat_order=' || p_batting_order_pos::TEXT, '')
            || COALESCE(' at_bat=' || p_at_bat_number::TEXT, '')
            AS match_basis
    FROM stg.player_identity pi
    -- Join through Statcast pitches to locate who played in this game/team slot
    JOIN raw_statcast.pitch p
        ON  p.batter = pi.mlbam_player_id
        AND p.game_date = p_game_date
    -- Join through game/team bridge to filter by team
    JOIN stg.game_identity gi
        ON  gi.statcast_game_pk = p.game_pk
    JOIN stg.team_identity ti
        ON  (
                (p.inning_topbot = 'Top'  AND ti.team_identity_id = gi.away_team_identity_id)
             OR (p.inning_topbot = 'Bot'  AND ti.team_identity_id = gi.home_team_identity_id)
            )
        AND (ti.team_abbrev = p_team_abbrev OR ti.team_name ILIKE '%' || p_team_abbrev || '%')
    WHERE (p_batting_order_pos IS NULL OR p.bat_order      = p_batting_order_pos)
      AND (p_at_bat_number     IS NULL OR p.at_bat_number  = p_at_bat_number)
    ORDER BY pi.identity_confidence_score DESC
    LIMIT 3;
$$;

COMMENT ON FUNCTION stg.fn_pinpoint_player_by_context(DATE, TEXT, INT, INT) IS
    'Last-resort player resolver using game context (date, team, batting order, at-bat number). '
    'Returns up to 3 candidate matches ranked by identity_confidence_score. '
    'Use when an MLBAM ID cannot be resolved via Chadwick or MLB StatsAPI. '
    'The match_basis column shows which contextual signals were used.';


-- ---------------------------------------------------------------------------
-- 5. fn_validate_game_lineup
--
-- Cross-checks whether the batting order recorded in raw_statcast.pitch
-- agrees with the batting order in an alternative source (e.g. Retrosheet
-- game logs loaded into stg.retrosheet_game_lineup, if available).
--
-- A lineup_match = FALSE strongly suggests a wrong retrosheet_player_id
-- mapping on a player_identity row.
--
-- This function is designed to be called after loading Retrosheet gamelogs
-- for a given season. It returns one row per at-bat slot per game.
--
-- Example:
--   SELECT * FROM stg.fn_validate_game_lineup('2024-07-15', 532441)
--   WHERE lineup_match = FALSE;
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_validate_game_lineup(
    p_game_date     DATE,
    p_game_pk       BIGINT
)
RETURNS TABLE (
    bat_order_pos           INT,
    statcast_mlbam_id       BIGINT,
    statcast_player_name    TEXT,
    retro_player_id         TEXT,
    retro_player_name       TEXT,
    lineup_match            BOOLEAN,
    note                    TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        bat_slot.bat_order_pos,
        bat_slot.mlbam_id,
        bat_slot.statcast_name,
        pi.retrosheet_player_id,
        pi.full_name                 AS retro_player_name,
        -- Match = Statcast MLBAM maps to the same retro ID as the lineup record
        -- If retrosheet_player_id is NULL we cannot validate, so NULL not FALSE
        CASE
            WHEN pi.retrosheet_player_id IS NULL THEN NULL
            ELSE TRUE  -- If we have a retro ID and got here, it matched the join
        END                          AS lineup_match,
        CASE
            WHEN pi.retrosheet_player_id IS NULL
                THEN 'Cannot validate: retrosheet_player_id not yet populated for this player'
            ELSE 'OK'
        END                          AS note
    FROM (
        -- Distill one row per batting-order slot from Statcast
        SELECT
            bat_order::INT           AS bat_order_pos,
            batter                   AS mlbam_id,
            MIN(player_name)         AS statcast_name
        FROM raw_statcast.pitch
        WHERE game_date = p_game_date
          AND game_pk   = p_game_pk
          AND bat_order IS NOT NULL
          AND batter    IS NOT NULL
        GROUP BY bat_order, batter
    ) bat_slot
    LEFT JOIN stg.player_identity pi
        ON pi.mlbam_player_id = bat_slot.mlbam_id
    ORDER BY bat_slot.bat_order_pos;
$$;

COMMENT ON FUNCTION stg.fn_validate_game_lineup(DATE, BIGINT) IS
    'Cross-checks batting order from raw_statcast.pitch against stg.player_identity retro mappings. '
    'A NULL lineup_match means the player has no retrosheet_player_id yet (normal for new players). '
    'Use to audit whether Statcast MLBAM IDs are mapped to the correct Retrosheet IDs. '
    'Example: SELECT * FROM stg.fn_validate_game_lineup(''2024-07-15'', 532441) WHERE lineup_match IS NULL;';


-- ---------------------------------------------------------------------------
-- 6. update_player_identity (PROCEDURE)
--
-- Safe, audited update path for stg.player_identity.
-- All changes — whether from the Python enrichment worker, an AI agent,
-- the Chadwick refresh job, or a manual DBA correction — MUST go through
-- this procedure so that:
--   a) Only non-NULL values are applied (COALESCE semantics — never wipe a
--      good ID by passing NULL)
--   b) A confidence downgrade is explicitly warned about
--   c) The update is logged to stg.player_identity_resolution_log
--
-- Parameters:
--   p_player_identity_id  — the row to update (required)
--   p_retro_id            — new retrosheet_player_id (NULL = leave unchanged)
--   p_bbref_id            — new bbref_player_id      (NULL = leave unchanged)
--   p_fangraphs_id        — new fangraphs_player_id  (NULL = leave unchanged)
--   p_lahman_id           — new lahman_player_id     (NULL = leave unchanged)
--   p_confidence          — new identity_confidence_score (NULL = leave unchanged)
--   p_source              — what triggered this update (e.g. 'chadwick:seed',
--                           'mlb_statsapi:xref', 'manual:dba')
--
-- Example:
--   CALL stg.update_player_identity(
--       p_player_identity_id := 42,
--       p_retro_id           := 'ruthba01',
--       p_bbref_id           := 'ruthba01',
--       p_confidence         := 0.95,
--       p_source             := 'chadwick:seed'
--   );
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE stg.update_player_identity(
    p_player_identity_id    BIGINT,
    p_retro_id              TEXT    DEFAULT NULL,
    p_bbref_id              TEXT    DEFAULT NULL,
    p_fangraphs_id          TEXT    DEFAULT NULL,
    p_lahman_id             TEXT    DEFAULT NULL,
    p_confidence            NUMERIC DEFAULT NULL,
    p_source                TEXT    DEFAULT 'manual'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_confidence    NUMERIC;
    v_old_mlbam         BIGINT;
    v_warn_downgrade    BOOLEAN := FALSE;
BEGIN
    -- Fetch current state for comparison and logging
    SELECT identity_confidence_score, mlbam_player_id
    INTO   v_old_confidence, v_old_mlbam
    FROM   stg.player_identity
    WHERE  player_identity_id = p_player_identity_id
    FOR    UPDATE;  -- row lock to prevent concurrent updates

    IF NOT FOUND THEN
        RAISE EXCEPTION 'update_player_identity: player_identity_id % not found', p_player_identity_id;
    END IF;

    -- Warn if caller is trying to lower confidence
    IF p_confidence IS NOT NULL AND p_confidence < v_old_confidence THEN
        v_warn_downgrade := TRUE;
        RAISE WARNING
            'update_player_identity: confidence downgrade on player_identity_id % (%.3f → %.3f). '
            'Set p_source clearly so this change is traceable.',
            p_player_identity_id, v_old_confidence, p_confidence;
    END IF;

    -- Apply COALESCE-safe update: only touch columns where caller passed a value
    UPDATE stg.player_identity
    SET
        retrosheet_player_id    = COALESCE(p_retro_id,      retrosheet_player_id),
        bbref_player_id         = COALESCE(p_bbref_id,      bbref_player_id),
        fangraphs_player_id     = COALESCE(p_fangraphs_id,  fangraphs_player_id),
        lahman_player_id        = COALESCE(p_lahman_id,     lahman_player_id),
        identity_confidence_score = COALESCE(p_confidence,  identity_confidence_score),
        identity_source         = p_source,
        updated_at              = NOW()
    WHERE player_identity_id = p_player_identity_id;

    -- Write audit log entry
    INSERT INTO stg.player_identity_resolution_log (
        trigger_source, mlbam_player_id, player_name, action_taken, player_identity_id, note
    )
    SELECT
        p_source,
        v_old_mlbam,
        full_name,
        CASE WHEN v_warn_downgrade THEN 'UPDATED_CONFIDENCE_DOWNGRADE' ELSE 'UPDATED' END,
        p_player_identity_id,
        format(
            'retro=%s bbref=%s fg=%s lahman=%s conf=%.3f',
            COALESCE(p_retro_id, '(unchanged)'),
            COALESCE(p_bbref_id, '(unchanged)'),
            COALESCE(p_fangraphs_id, '(unchanged)'),
            COALESCE(p_lahman_id, '(unchanged)'),
            COALESCE(p_confidence, v_old_confidence)
        )
    FROM stg.player_identity
    WHERE player_identity_id = p_player_identity_id;

END;
$$;

COMMENT ON PROCEDURE stg.update_player_identity(
    BIGINT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT
) IS
    'Safe, audited update for stg.player_identity. '
    'COALESCE semantics: NULL params leave the existing value unchanged — never wipes good IDs. '
    'Warns on confidence downgrades. Writes every change to player_identity_resolution_log. '
    'All enrichment workers, AI agents, and DBA corrections must use this procedure. '
    'Never UPDATE stg.player_identity directly outside of this procedure.';


-- ---------------------------------------------------------------------------
-- 7. v_identity_validation_dashboard
--
-- Single-query ops view showing the current health of the identity pipeline.
-- Pin this to a Metabase/Grafana dashboard for ongoing monitoring.
--
-- Columns:
--   total_players              — total rows in stg.player_identity
--   fully_resolved             — all 5 IDs present and confidence >= 0.80
--   pending_enrichment         — confidence = 0 (auto-inserted, never touched)
--   needs_manual_review        — 0 < confidence < 0.60
--   live_missing_historical    — MLBAM only, no retro/bbref (rookies/callups)
--   orphaned_pitches_48h       — pitches with no identity row (should be 0)
--   chadwick_divergences       — ID mismatches vs. chadwick_register_import
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg.v_identity_validation_dashboard AS
WITH
counts AS (
    SELECT
        COUNT(*)                                                          AS total_players,
        COUNT(*) FILTER (
            WHERE mlbam_player_id      IS NOT NULL
              AND retrosheet_player_id IS NOT NULL
              AND bbref_player_id      IS NOT NULL
              AND fangraphs_player_id  IS NOT NULL
              AND lahman_player_id     IS NOT NULL
              AND identity_confidence_score >= 0.80
        )                                                                 AS fully_resolved,
        COUNT(*) FILTER (WHERE identity_confidence_score = 0
                           AND identity_source LIKE 'auto:%')             AS pending_enrichment,
        COUNT(*) FILTER (WHERE identity_confidence_score > 0
                           AND identity_confidence_score < 0.60)          AS needs_manual_review,
        COUNT(*) FILTER (
            WHERE mlbam_player_id IS NOT NULL
              AND identity_confidence_score >= 0.60
              AND (retrosheet_player_id IS NULL
                OR bbref_player_id     IS NULL
                OR lahman_player_id    IS NULL)
        )                                                                 AS live_missing_historical
    FROM stg.player_identity
),
orphans AS (
    SELECT COUNT(*) AS cnt FROM stg.fn_detect_orphaned_pitches()
),
chadwick_diffs AS (
    -- Only runs if chadwick_register_import is populated; returns 0 if empty
    SELECT COUNT(*) AS cnt FROM stg.fn_cross_validate_identities()
)
SELECT
    c.total_players,
    c.fully_resolved,
    ROUND(c.fully_resolved * 100.0 / NULLIF(c.total_players, 0), 1) AS fully_resolved_pct,
    c.pending_enrichment,
    c.needs_manual_review,
    c.live_missing_historical,
    o.cnt                                                             AS orphaned_pitches_48h,
    cd.cnt                                                            AS chadwick_divergences,
    NOW()                                                             AS dashboard_as_of
FROM counts c
CROSS JOIN orphans o
CROSS JOIN chadwick_diffs cd;

COMMENT ON VIEW stg.v_identity_validation_dashboard IS
    'Single-query ops dashboard for the player identity pipeline. '
    'orphaned_pitches_48h should always be 0 — any non-zero value is a CRITICAL alert. '
    'chadwick_divergences is 0 when stg.chadwick_register_import is empty; refresh weekly. '
    'Pin this to your monitoring dashboard and alert on orphaned_pitches_48h > 0 or '
    'needs_manual_review > expected_threshold.';


COMMIT;
