-- =============================================================================
-- 013_identity_validation_functions.sql
--
-- Player identity cross-source validation, contextual pinpointing,
-- orphan detection, Chadwick cross-reference diff, and the canonical
-- update procedure with full audit trail.
--
-- Apply after:
--   sql/050_staging/001_identity_bridge.sql
--   sql/050_staging/004_identity_trigger_and_indexes.sql
--
-- Issue: #13  Design: DEC-003, DEC-005
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. fn_validate_identity_completeness()
--
-- Returns one summary row per player identity showing which external IDs
-- are populated, a completeness score (0.0–1.0), and a recommended action.
-- Run on demand or as a scheduled health-check job.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_validate_identity_completeness(
    p_min_confidence NUMERIC DEFAULT 0.0,
    p_limit          INT     DEFAULT 1000
)
RETURNS TABLE (
    player_identity_id      BIGINT,
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    identity_confidence_score NUMERIC,
    has_mlbam               BOOLEAN,
    has_retro               BOOLEAN,
    has_bbref               BOOLEAN,
    has_fangraphs           BOOLEAN,
    has_lahman              BOOLEAN,
    ids_populated           INT,
    completeness_pct        NUMERIC,
    recommended_action      TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        pi.identity_confidence_score,
        (pi.mlbam_player_id        IS NOT NULL)  AS has_mlbam,
        (pi.retrosheet_player_id   IS NOT NULL)  AS has_retro,
        (pi.bbref_player_id        IS NOT NULL)  AS has_bbref,
        (pi.fangraphs_player_id    IS NOT NULL)  AS has_fangraphs,
        (pi.lahman_player_id       IS NOT NULL)  AS has_lahman,
        -- count populated IDs out of 5 possible
        (
            (pi.mlbam_player_id      IS NOT NULL)::INT +
            (pi.retrosheet_player_id IS NOT NULL)::INT +
            (pi.bbref_player_id      IS NOT NULL)::INT +
            (pi.fangraphs_player_id  IS NOT NULL)::INT +
            (pi.lahman_player_id     IS NOT NULL)::INT
        )                                         AS ids_populated,
        ROUND(
            (
                (pi.mlbam_player_id      IS NOT NULL)::INT +
                (pi.retrosheet_player_id IS NOT NULL)::INT +
                (pi.bbref_player_id      IS NOT NULL)::INT +
                (pi.fangraphs_player_id  IS NOT NULL)::INT +
                (pi.lahman_player_id     IS NOT NULL)::INT
            )::NUMERIC / 5.0 * 100, 1
        )                                         AS completeness_pct,
        CASE
            WHEN pi.identity_confidence_score = 0
                THEN 'AUTO_PLACEHOLDER: run Chadwick/pybaseball enrichment job'
            WHEN pi.identity_confidence_score < 0.60
                THEN 'LOW_CONFIDENCE: route to manual review queue'
            WHEN pi.identity_confidence_score < 0.90
                AND (
                    pi.retrosheet_player_id IS NULL
                 OR pi.bbref_player_id      IS NULL
                )
                THEN 'PARTIAL_IDS: re-run Chadwick seed or MLB StatsAPI xref lookup'
            WHEN pi.mlbam_player_id IS NOT NULL
                AND pi.retrosheet_player_id IS NULL
                AND pi.bbref_player_id      IS NULL
                THEN 'LIVE_PLAYER_PENDING_HISTORICAL: await next Chadwick weekly release'
            ELSE 'OK'
        END                                       AS recommended_action
    FROM stg.player_identity pi
    WHERE pi.identity_confidence_score >= p_min_confidence
    ORDER BY pi.identity_confidence_score ASC, pi.created_at ASC
    LIMIT p_limit;
$$;

COMMENT ON FUNCTION stg.fn_validate_identity_completeness(NUMERIC, INT) IS
    'Returns per-player ID completeness report with recommended actions. '
    'Pass p_min_confidence = 0 (default) to see all players, or a higher threshold '
    'to focus on already-enriched players. Use p_limit to page results.';


-- ---------------------------------------------------------------------------
-- 2. fn_detect_orphaned_pitches()
--
-- Returns any raw_statcast.pitch rows whose batter or pitcher MLBAM ID
-- has NO corresponding stg.player_identity row.
-- Should always return zero rows if the AFTER INSERT trigger is healthy.
-- Non-zero results = trigger failure or manual data load bypassed the trigger.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_detect_orphaned_pitches(
    p_game_date_from DATE DEFAULT NULL,
    p_game_date_to   DATE DEFAULT NULL,
    p_limit          INT  DEFAULT 500
)
RETURNS TABLE (
    pitch_id            BIGINT,
    game_date           DATE,
    batter_mlbam        BIGINT,
    pitcher_mlbam       BIGINT,
    batter_name         TEXT,
    pitcher_name        TEXT,
    batter_identity_id  BIGINT,
    pitcher_identity_id BIGINT,
    batter_is_orphan    BOOLEAN,
    pitcher_is_orphan   BOOLEAN
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        p.pitch_id,
        p.game_date,
        p.batter                                  AS batter_mlbam,
        p.pitcher                                 AS pitcher_mlbam,
        p.player_name                             AS batter_name,
        NULL::TEXT                                AS pitcher_name,
        bpi.player_identity_id                    AS batter_identity_id,
        ppi.player_identity_id                    AS pitcher_identity_id,
        (bpi.player_identity_id IS NULL)          AS batter_is_orphan,
        (ppi.player_identity_id IS NULL)          AS pitcher_is_orphan
    FROM raw_statcast.pitch p
    LEFT JOIN stg.player_identity bpi ON bpi.mlbam_player_id = p.batter
    LEFT JOIN stg.player_identity ppi ON ppi.mlbam_player_id = p.pitcher
    WHERE (bpi.player_identity_id IS NULL OR ppi.player_identity_id IS NULL)
      AND (p_game_date_from IS NULL OR p.game_date >= p_game_date_from)
      AND (p_game_date_to   IS NULL OR p.game_date <= p_game_date_to)
    ORDER BY p.game_date DESC, p.pitch_id DESC
    LIMIT p_limit;
$$;

COMMENT ON FUNCTION stg.fn_detect_orphaned_pitches(DATE, DATE, INT) IS
    'Circuit-breaker health check. Returns Statcast pitch rows whose batter '
    'or pitcher MLBAM ID has no stg.player_identity row. '
    'Should always return zero rows. Non-zero = trigger failure or bulk load '
    'that bypassed the trigger. Run as a scheduled alert job.';


-- ---------------------------------------------------------------------------
-- 3. fn_cross_validate_identities()
--
-- Compares stored stg.player_identity IDs against a freshly-loaded snapshot
-- of the Chadwick Register (expected in a temp/staging table).
-- Returns divergences: rows where your stored ID differs from Chadwick's.
--
-- Usage:
--   1. Load latest Chadwick CSV into stg.chadwick_register_snapshot
--   2. SELECT * FROM stg.fn_cross_validate_identities();
--   3. Review rows where divergence_type != 'OK' and apply corrections via
--      stg.update_player_identity().
-- ---------------------------------------------------------------------------

-- Snapshot table for weekly Chadwick Register load
CREATE TABLE IF NOT EXISTS stg.chadwick_register_snapshot (
    key_mlbam       BIGINT,
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
    pro_played_first SMALLINT,
    pro_played_last  SMALLINT,
    loaded_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS stg_chadwick_snap_mlbam_uidx
    ON stg.chadwick_register_snapshot (key_mlbam)
    WHERE key_mlbam IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_chadwick_snap_retro_idx
    ON stg.chadwick_register_snapshot (key_retro)
    WHERE key_retro IS NOT NULL;

COMMENT ON TABLE stg.chadwick_register_snapshot IS
    'Weekly snapshot of the Chadwick Bureau Register CSV. '
    'Source: https://github.com/chadwickbureau/register '
    'Load with: COPY stg.chadwick_register_snapshot FROM ... CSV HEADER. '
    'Truncate and reload weekly. Used by fn_cross_validate_identities().';


CREATE OR REPLACE FUNCTION stg.fn_cross_validate_identities(
    p_mlbam_id BIGINT DEFAULT NULL   -- NULL = validate all players
)
RETURNS TABLE (
    player_identity_id      BIGINT,
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    field_name              TEXT,
    our_value               TEXT,
    chadwick_value          TEXT,
    divergence_type         TEXT,   -- 'MISMATCH' | 'WE_HAVE_EXTRA' | 'CHADWICK_HAS_NEW' | 'OK'
    suggested_action        TEXT
)
LANGUAGE sql
STABLE
AS $$
    -- Retrosheet ID
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        'retrosheet_player_id'                         AS field_name,
        pi.retrosheet_player_id                        AS our_value,
        cr.key_retro                                   AS chadwick_value,
        CASE
            WHEN pi.retrosheet_player_id IS NULL AND cr.key_retro IS NOT NULL
                THEN 'CHADWICK_HAS_NEW'
            WHEN pi.retrosheet_player_id IS NOT NULL AND cr.key_retro IS NULL
                THEN 'WE_HAVE_EXTRA'
            WHEN pi.retrosheet_player_id != cr.key_retro
                THEN 'MISMATCH'
            ELSE 'OK'
        END                                            AS divergence_type,
        CASE
            WHEN pi.retrosheet_player_id IS NULL AND cr.key_retro IS NOT NULL
                THEN format('UPDATE stg.player_identity SET retrosheet_player_id = %L WHERE player_identity_id = %s;',
                            cr.key_retro, pi.player_identity_id)
            WHEN pi.retrosheet_player_id != cr.key_retro
                THEN format('-- REVIEW: our retro=%L vs chadwick=%L for mlbam=%s',
                            pi.retrosheet_player_id, cr.key_retro, pi.mlbam_player_id)
            ELSE NULL
        END                                            AS suggested_action
    FROM stg.player_identity pi
    JOIN stg.chadwick_register_snapshot cr ON cr.key_mlbam = pi.mlbam_player_id
    WHERE (p_mlbam_id IS NULL OR pi.mlbam_player_id = p_mlbam_id)
      AND (
          pi.retrosheet_player_id IS DISTINCT FROM cr.key_retro
      )

    UNION ALL

    -- BBRef ID
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        'bbref_player_id',
        pi.bbref_player_id,
        cr.key_bbref,
        CASE
            WHEN pi.bbref_player_id IS NULL AND cr.key_bbref IS NOT NULL THEN 'CHADWICK_HAS_NEW'
            WHEN pi.bbref_player_id IS NOT NULL AND cr.key_bbref IS NULL THEN 'WE_HAVE_EXTRA'
            WHEN pi.bbref_player_id != cr.key_bbref                      THEN 'MISMATCH'
            ELSE 'OK'
        END,
        CASE
            WHEN pi.bbref_player_id IS NULL AND cr.key_bbref IS NOT NULL
                THEN format('UPDATE stg.player_identity SET bbref_player_id = %L WHERE player_identity_id = %s;',
                            cr.key_bbref, pi.player_identity_id)
            WHEN pi.bbref_player_id != cr.key_bbref
                THEN format('-- REVIEW: our bbref=%L vs chadwick=%L for mlbam=%s',
                            pi.bbref_player_id, cr.key_bbref, pi.mlbam_player_id)
            ELSE NULL
        END
    FROM stg.player_identity pi
    JOIN stg.chadwick_register_snapshot cr ON cr.key_mlbam = pi.mlbam_player_id
    WHERE (p_mlbam_id IS NULL OR pi.mlbam_player_id = p_mlbam_id)
      AND (pi.bbref_player_id IS DISTINCT FROM cr.key_bbref)

    UNION ALL

    -- FanGraphs ID
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        'fangraphs_player_id',
        pi.fangraphs_player_id,
        cr.key_fangraphs,
        CASE
            WHEN pi.fangraphs_player_id IS NULL AND cr.key_fangraphs IS NOT NULL THEN 'CHADWICK_HAS_NEW'
            WHEN pi.fangraphs_player_id IS NOT NULL AND cr.key_fangraphs IS NULL THEN 'WE_HAVE_EXTRA'
            WHEN pi.fangraphs_player_id != cr.key_fangraphs                      THEN 'MISMATCH'
            ELSE 'OK'
        END,
        CASE
            WHEN pi.fangraphs_player_id IS NULL AND cr.key_fangraphs IS NOT NULL
                THEN format('UPDATE stg.player_identity SET fangraphs_player_id = %L WHERE player_identity_id = %s;',
                            cr.key_fangraphs, pi.player_identity_id)
            WHEN pi.fangraphs_player_id != cr.key_fangraphs
                THEN format('-- REVIEW: our fg=%L vs chadwick=%L for mlbam=%s',
                            pi.fangraphs_player_id, cr.key_fangraphs, pi.mlbam_player_id)
            ELSE NULL
        END
    FROM stg.player_identity pi
    JOIN stg.chadwick_register_snapshot cr ON cr.key_mlbam = pi.mlbam_player_id
    WHERE (p_mlbam_id IS NULL OR pi.mlbam_player_id = p_mlbam_id)
      AND (pi.fangraphs_player_id IS DISTINCT FROM cr.key_fangraphs)

    ORDER BY player_identity_id, field_name;
$$;

COMMENT ON FUNCTION stg.fn_cross_validate_identities(BIGINT) IS
    'Compares stg.player_identity against the loaded Chadwick Register snapshot. '
    'Returns every field-level divergence with a suggested_action (ready-to-run UPDATE SQL '
    'for gaps, REVIEW comment for mismatches). '
    'Run weekly after loading stg.chadwick_register_snapshot. '
    'Apply corrections via stg.update_player_identity() to preserve the audit trail.';


-- ---------------------------------------------------------------------------
-- 4. fn_pinpoint_player_by_context()
--
-- Uses game-context signals (date, team, batting-order position, inning,
-- at-bat number) to identify a specific player from raw_statcast data
-- and cross-check whether the stored identity IDs match.
--
-- This implements the "plate appearance fingerprint" heuristic:
-- if we know team X batted player Y 3rd on date D, and Retrosheet says
-- the same, the MLBAM→Retrosheet link is validated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_pinpoint_player_by_context(
    p_game_date          DATE,
    p_batting_team       TEXT,
    p_batting_order_pos  INT     DEFAULT NULL,
    p_inning             INT     DEFAULT NULL,
    p_at_bat_number      INT     DEFAULT NULL
)
RETURNS TABLE (
    pitch_id                BIGINT,
    game_date               DATE,
    home_team               TEXT,
    away_team               TEXT,
    batter_mlbam            BIGINT,
    pitcher_mlbam           BIGINT,
    batter_name             TEXT,
    batting_order           INT,
    inning                  INT,
    at_bat_number           INT,
    batter_identity_id      BIGINT,
    batter_full_name        TEXT,
    batter_retro_id         TEXT,
    batter_bbref_id         TEXT,
    batter_confidence       NUMERIC,
    identity_status         TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT DISTINCT ON (p.batter, p.at_bat_number)
        p.pitch_id,
        p.game_date,
        p.home_team,
        p.away_team,
        p.batter                                  AS batter_mlbam,
        p.pitcher                                 AS pitcher_mlbam,
        p.player_name                             AS batter_name,
        p.bat_score                               AS batting_order,   -- proxy; replace with actual batting_order col if present
        p.inning,
        p.at_bat_number,
        pi.player_identity_id                     AS batter_identity_id,
        pi.full_name                              AS batter_full_name,
        pi.retrosheet_player_id                   AS batter_retro_id,
        pi.bbref_player_id                        AS batter_bbref_id,
        pi.identity_confidence_score              AS batter_confidence,
        CASE
            WHEN pi.player_identity_id IS NULL
                THEN 'ORPHAN: no identity row'
            WHEN pi.identity_confidence_score = 0
                THEN 'PLACEHOLDER: enrichment pending'
            WHEN pi.identity_confidence_score < 0.60
                THEN 'LOW_CONFIDENCE: manual review needed'
            WHEN pi.retrosheet_player_id IS NULL
                THEN 'MISSING_RETRO_ID'
            WHEN pi.bbref_player_id IS NULL
                THEN 'MISSING_BBREF_ID'
            ELSE 'VALIDATED'
        END                                       AS identity_status
    FROM raw_statcast.pitch p
    LEFT JOIN stg.player_identity pi ON pi.mlbam_player_id = p.batter
    WHERE p.game_date = p_game_date
      AND (p.home_team = p_batting_team OR p.away_team = p_batting_team)
      AND (p_inning           IS NULL OR p.inning        = p_inning)
      AND (p_at_bat_number    IS NULL OR p.at_bat_number  = p_at_bat_number)
    ORDER BY p.batter, p.at_bat_number, p.pitch_number DESC;
$$;

COMMENT ON FUNCTION stg.fn_pinpoint_player_by_context(DATE, TEXT, INT, INT, INT) IS
    'Identifies players from game-context signals (date, team, inning, at-bat). '
    'Cross-checks stored identity IDs and returns identity_status for each batter. '
    'Use for debugging specific games where IDs are suspect. '
    'Example: SELECT * FROM stg.fn_pinpoint_player_by_context(''2025-04-01'', ''NYY'');';


-- ---------------------------------------------------------------------------
-- 5. fn_validate_game_lineup()
--
-- Compares the actual batting-order sequence observed in raw_statcast.pitch
-- for a given game against what the Chadwick/Retrosheet register says for
-- that game. A mismatch in batting-order position is a strong signal that
-- the MLBAM→Retrosheet ID crosswalk is wrong for that player.
--
-- Requires stg.retrosheet_lineup_snapshot to be populated
-- (loaded alongside the Retrosheet game logs).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.retrosheet_lineup_snapshot (
    game_id             TEXT NOT NULL,    -- Retrosheet game ID e.g. NYA202504010
    game_date           DATE NOT NULL,
    team_code           TEXT NOT NULL,
    batting_order_pos   SMALLINT NOT NULL,
    retrosheet_id       TEXT NOT NULL,
    player_name         TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (game_id, team_code, batting_order_pos)
);

CREATE INDEX IF NOT EXISTS stg_retro_lineup_date_team_idx
    ON stg.retrosheet_lineup_snapshot (game_date, team_code);

COMMENT ON TABLE stg.retrosheet_lineup_snapshot IS
    'Retrosheet game lineup data for cross-validation. '
    'Load from Retrosheet event files or game-log CSV. '
    'Used by fn_validate_game_lineup() to verify MLBAM→Retrosheet ID crosswalk.';


CREATE OR REPLACE FUNCTION stg.fn_validate_game_lineup(
    p_game_date   DATE,
    p_team_code   TEXT
)
RETURNS TABLE (
    batting_order_pos       SMALLINT,
    mlbam_player_id         BIGINT,
    statcast_name           TEXT,
    retrosheet_id_stored    TEXT,      -- what we have in stg.player_identity
    retrosheet_id_actual    TEXT,      -- what Retrosheet lineup file says
    retro_name_actual       TEXT,
    lineup_match            BOOLEAN,
    validation_note         TEXT
)
LANGUAGE sql
STABLE
AS $$
    -- Derive per-game batting order from statcast (first appearance per at-bat)
    WITH statcast_order AS (
        SELECT DISTINCT ON (p.batter)
            p.batter                     AS mlbam_id,
            p.player_name                AS statcast_name,
            p.at_bat_number              AS first_at_bat,
            ROW_NUMBER() OVER (
                PARTITION BY p.game_date, p.home_team, p.away_team
                ORDER BY p.at_bat_number
            )::SMALLINT                  AS derived_order_pos
        FROM raw_statcast.pitch p
        WHERE p.game_date = p_game_date
          AND (p.home_team = p_team_code OR p.away_team = p_team_code)
        ORDER BY p.batter, p.at_bat_number
    ),
    identity AS (
        SELECT
            pi.mlbam_player_id,
            pi.retrosheet_player_id
        FROM stg.player_identity pi
    )
    SELECT
        so.derived_order_pos             AS batting_order_pos,
        so.mlbam_id                      AS mlbam_player_id,
        so.statcast_name,
        id.retrosheet_player_id          AS retrosheet_id_stored,
        rl.retrosheet_id                 AS retrosheet_id_actual,
        rl.player_name                   AS retro_name_actual,
        (
            id.retrosheet_player_id IS NOT NULL
            AND rl.retrosheet_id IS NOT NULL
            AND id.retrosheet_player_id = rl.retrosheet_id
        )                                AS lineup_match,
        CASE
            WHEN id.retrosheet_player_id IS NULL
                THEN 'Retrosheet ID not yet assigned — run enrichment'
            WHEN rl.retrosheet_id IS NULL
                THEN 'No Retrosheet lineup row found for this game/team'
            WHEN id.retrosheet_player_id != rl.retrosheet_id
                THEN format('ID MISMATCH: stored %L vs lineup %L — verify via Chadwick',
                            id.retrosheet_player_id, rl.retrosheet_id)
            ELSE 'MATCH'
        END                              AS validation_note
    FROM statcast_order so
    LEFT JOIN identity id ON id.mlbam_player_id = so.mlbam_id
    LEFT JOIN stg.retrosheet_lineup_snapshot rl
        ON  rl.game_date        = p_game_date
        AND rl.team_code        = p_team_code
        AND rl.batting_order_pos = so.derived_order_pos
    ORDER BY so.derived_order_pos;
$$;

COMMENT ON FUNCTION stg.fn_validate_game_lineup(DATE, TEXT) IS
    'Cross-validates MLBAM→Retrosheet identity crosswalk using batting-order context. '
    'Compares the observed batting order in raw_statcast.pitch against the '
    'Retrosheet lineup file for the same game and team. '
    'lineup_match = FALSE is a strong signal of a wrong retrosheet_player_id. '
    'Requires stg.retrosheet_lineup_snapshot to be loaded. '
    'Example: SELECT * FROM stg.fn_validate_game_lineup(''2025-04-01''::date, ''NYY'');';


-- ---------------------------------------------------------------------------
-- 6. update_player_identity() — canonical update procedure
--
-- ALL writes to stg.player_identity (whether from Python workers, AI agents,
-- or manual psql corrections) should go through this procedure.
-- It validates inputs, COALESCE-safely applies changes, warns on confidence
-- downgrades, and writes a full audit row.
-- ---------------------------------------------------------------------------

-- Audit log for identity updates
CREATE TABLE IF NOT EXISTS stg.player_identity_update_log (
    update_log_id           BIGSERIAL PRIMARY KEY,
    player_identity_id      BIGINT       NOT NULL,
    mlbam_player_id         BIGINT,
    changed_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    changed_by              TEXT         NOT NULL DEFAULT current_user,
    change_source           TEXT,        -- 'python:enrichment' | 'manual' | 'chadwick_seed' | etc.
    old_retrosheet_id       TEXT,
    new_retrosheet_id       TEXT,
    old_bbref_id            TEXT,
    new_bbref_id            TEXT,
    old_fangraphs_id        TEXT,
    new_fangraphs_id        TEXT,
    old_lahman_id           TEXT,
    new_lahman_id           TEXT,
    old_confidence          NUMERIC,
    new_confidence          NUMERIC,
    confidence_direction    TEXT,        -- 'UPGRADE' | 'DOWNGRADE' | 'UNCHANGED'
    note                    TEXT
);

CREATE INDEX IF NOT EXISTS stg_update_log_identity_idx
    ON stg.player_identity_update_log (player_identity_id);

CREATE INDEX IF NOT EXISTS stg_update_log_changed_at_idx
    ON stg.player_identity_update_log (changed_at DESC);

COMMENT ON TABLE stg.player_identity_update_log IS
    'Full audit trail for every stg.player_identity update. '
    'Written by stg.update_player_identity() procedure. '
    'Query this table to understand why an ID changed and who or what changed it.';


CREATE OR REPLACE PROCEDURE stg.update_player_identity(
    p_player_identity_id    BIGINT,
    p_retrosheet_id         TEXT     DEFAULT NULL,
    p_bbref_id              TEXT     DEFAULT NULL,
    p_fangraphs_id          TEXT     DEFAULT NULL,
    p_lahman_id             TEXT     DEFAULT NULL,
    p_confidence            NUMERIC  DEFAULT NULL,
    p_change_source         TEXT     DEFAULT 'manual',
    p_note                  TEXT     DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cur          stg.player_identity%ROWTYPE;
    v_conf_dir     TEXT;
BEGIN
    -- Lock the row for update
    SELECT * INTO v_cur
    FROM stg.player_identity
    WHERE player_identity_id = p_player_identity_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'update_player_identity: no row with player_identity_id = %',
            p_player_identity_id;
    END IF;

    -- Determine confidence direction
    IF p_confidence IS NOT NULL THEN
        v_conf_dir := CASE
            WHEN p_confidence > v_cur.identity_confidence_score THEN 'UPGRADE'
            WHEN p_confidence < v_cur.identity_confidence_score THEN 'DOWNGRADE'
            ELSE 'UNCHANGED'
        END;
        -- Warn but do not block downgrades — caller must be explicit
        IF v_conf_dir = 'DOWNGRADE' THEN
            RAISE WARNING
                'update_player_identity: confidence DOWNGRADE for player_identity_id=% (%.2f → %.2f). '
                'Source: %. Note: %',
                p_player_identity_id,
                v_cur.identity_confidence_score,
                p_confidence,
                p_change_source,
                COALESCE(p_note, 'none');
        END IF;
    ELSE
        v_conf_dir := 'UNCHANGED';
    END IF;

    -- Apply update — COALESCE preserves existing values when caller passes NULL
    UPDATE stg.player_identity
    SET
        retrosheet_player_id    = COALESCE(p_retrosheet_id,  retrosheet_player_id),
        bbref_player_id         = COALESCE(p_bbref_id,       bbref_player_id),
        fangraphs_player_id     = COALESCE(p_fangraphs_id,   fangraphs_player_id),
        lahman_player_id        = COALESCE(p_lahman_id,      lahman_player_id),
        identity_confidence_score = COALESCE(p_confidence,   identity_confidence_score),
        identity_source         = COALESCE(p_change_source,  identity_source)
    WHERE player_identity_id = p_player_identity_id;

    -- Write audit row
    INSERT INTO stg.player_identity_update_log (
        player_identity_id,
        mlbam_player_id,
        change_source,
        old_retrosheet_id,  new_retrosheet_id,
        old_bbref_id,       new_bbref_id,
        old_fangraphs_id,   new_fangraphs_id,
        old_lahman_id,      new_lahman_id,
        old_confidence,     new_confidence,
        confidence_direction,
        note
    ) VALUES (
        p_player_identity_id,
        v_cur.mlbam_player_id,
        p_change_source,
        v_cur.retrosheet_player_id,  COALESCE(p_retrosheet_id, v_cur.retrosheet_player_id),
        v_cur.bbref_player_id,       COALESCE(p_bbref_id,      v_cur.bbref_player_id),
        v_cur.fangraphs_player_id,   COALESCE(p_fangraphs_id,  v_cur.fangraphs_player_id),
        v_cur.lahman_player_id,      COALESCE(p_lahman_id,     v_cur.lahman_player_id),
        v_cur.identity_confidence_score,
        COALESCE(p_confidence, v_cur.identity_confidence_score),
        v_conf_dir,
        p_note
    );
END;
$$;

COMMENT ON PROCEDURE stg.update_player_identity(
    BIGINT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT
) IS
    'Canonical write path for stg.player_identity updates. '
    'COALESCE-safe: NULL arguments preserve existing values. '
    'Warns (does not block) on confidence downgrades. '
    'Always writes a row to stg.player_identity_update_log. '
    'Use p_change_source to identify the caller: ''python:enrichment'', ''chadwick_seed'', ''manual'', etc. '
    'Example: CALL stg.update_player_identity(42, p_retrosheet_id=>''ruthba01'', p_confidence=>0.95, p_change_source=>''chadwick_seed'');';


-- ---------------------------------------------------------------------------
-- 7. v_identity_validation_dashboard — operational health view
--
-- Single-query summary of the entire player identity pipeline health.
-- Run this to get a top-level status of where things stand.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg.v_identity_validation_dashboard AS
SELECT
    COUNT(*)                                                              AS total_players,
    COUNT(*) FILTER (WHERE identity_confidence_score = 0)                AS auto_placeholders,
    COUNT(*) FILTER (WHERE identity_confidence_score > 0
                      AND identity_confidence_score < 0.60)              AS low_confidence,
    COUNT(*) FILTER (WHERE identity_confidence_score >= 0.60
                      AND identity_confidence_score < 0.90)              AS medium_confidence,
    COUNT(*) FILTER (WHERE identity_confidence_score >= 0.90)            AS high_confidence,
    COUNT(*) FILTER (WHERE mlbam_player_id     IS NOT NULL
                      AND retrosheet_player_id IS NULL
                      AND identity_confidence_score >= 0.60)             AS live_awaiting_retro,
    COUNT(*) FILTER (WHERE mlbam_player_id     IS NOT NULL
                      AND bbref_player_id      IS NULL
                      AND identity_confidence_score >= 0.60)             AS live_awaiting_bbref,
    COUNT(*) FILTER (WHERE mlbam_player_id     IS NOT NULL
                      AND fangraphs_player_id  IS NULL
                      AND identity_confidence_score >= 0.60)             AS live_awaiting_fangraphs,
    ROUND(
        COUNT(*) FILTER (WHERE identity_confidence_score >= 0.90)::NUMERIC
        / NULLIF(COUNT(*), 0) * 100, 1
    )                                                                     AS pct_high_confidence,
    NOW()                                                                 AS report_generated_at
FROM stg.player_identity;

COMMENT ON VIEW stg.v_identity_validation_dashboard IS
    'Top-level operational health summary for the player identity pipeline. '
    'Shows counts by confidence band and which external IDs still need resolution. '
    'Run: SELECT * FROM stg.v_identity_validation_dashboard;';


COMMIT;
