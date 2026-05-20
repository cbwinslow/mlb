-- =============================================================================
-- Player Identity Validation & Cross-Source Resolution Functions
--
-- Problem: Baseball data arrives from multiple independent sources (Statcast/
-- MLBAM, Retrosheet, Baseball Reference, FanGraphs, Lahman) each with their
-- own player ID systems. A player can be active in live Statcast data before
-- Retrosheet / BRef / Chadwick have published their cross-source IDs for that
-- player. We must never block raw data ingestion due to a missing identity
-- mapping, but we also must never allow orphaned fact records that cannot be
-- joined to a player.
--
-- This file implements:
--   A. Completeness reporting     – how filled-in is each row?
--   B. Orphan detection           – any raw facts without identity rows?
--   C. Contextual pinpointing     – resolve a player by game context
--   D. Lineup cross-validation    – confirm MLBAM<>Retrosheet via batting order
--   E. Chadwick cross-validation  – diff our IDs against Chadwick register
--   F. Safe update procedure      – audited path for all identity corrections
--   G. Operational views          – dashboard, review queue, live-debut queue
--
-- Apply after 001_identity_bridge.sql and 004_identity_trigger_and_indexes.sql.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- AUDIT LOG TABLE
-- Records every change made to stg.player_identity via stg.update_player_identity.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.player_identity_edit_log (
    edit_log_id             BIGSERIAL PRIMARY KEY,
    player_identity_id      BIGINT NOT NULL,
    edited_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    edited_by               TEXT NOT NULL DEFAULT current_user,
    edit_source             TEXT,           -- 'enrichment_worker' | 'chadwick_sync' | 'manual' | etc.
    field_name              TEXT NOT NULL,
    old_value               TEXT,
    new_value               TEXT,
    confidence_before       NUMERIC(6,3),
    confidence_after        NUMERIC(6,3),
    note                    TEXT
);

CREATE INDEX IF NOT EXISTS stg_edit_log_player_idx
    ON stg.player_identity_edit_log (player_identity_id, edited_at DESC);

CREATE INDEX IF NOT EXISTS stg_edit_log_edited_at_idx
    ON stg.player_identity_edit_log (edited_at DESC);

COMMENT ON TABLE stg.player_identity_edit_log IS
    'Full audit trail for every change to stg.player_identity. '
    'Written exclusively by stg.update_player_identity(). '
    'Use this to review automated enrichment decisions and roll back mistakes.';


-- ---------------------------------------------------------------------------
-- STAGING TABLE: Chadwick register import
-- The Chadwick Register CSV is loaded here first, then diffed against
-- stg.player_identity by fn_cross_validate_identities().
-- Download: https://github.com/chadwickbureau/register/tree/master/data
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.chadwick_register_import (
    key_person              TEXT,           -- Chadwick person key
    key_mlbam               BIGINT,
    key_retro               TEXT,
    key_bbref               TEXT,
    key_fangraphs           TEXT,
    key_lahman              TEXT,
    name_last               TEXT,
    name_first              TEXT,
    birth_year              INT,
    birth_month             INT,
    birth_day               INT,
    pro_played_first        INT,
    pro_played_last         INT,
    mlb_played_first        INT,
    mlb_played_last         INT,
    imported_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS stg_chadwick_mlbam_idx
    ON stg.chadwick_register_import (key_mlbam)
    WHERE key_mlbam IS NOT NULL;

CREATE INDEX IF NOT EXISTS stg_chadwick_retro_idx
    ON stg.chadwick_register_import (key_retro)
    WHERE key_retro IS NOT NULL;

COMMENT ON TABLE stg.chadwick_register_import IS
    'Staging table for the Chadwick Bureau Register CSV import. '
    'Truncate and reload weekly via scripts/load_chadwick_register.sh. '
    'Used as the authoritative cross-source reference by fn_cross_validate_identities().';


-- ---------------------------------------------------------------------------
-- A. COMPLETENESS REPORTING
-- Returns one row per player_identity with a fill-rate score and flags for
-- each missing external ID. Safe to run at any time; read-only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_validate_identity_completeness(
    p_min_confidence NUMERIC DEFAULT 0.0
)
RETURNS TABLE (
    player_identity_id      BIGINT,
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    identity_confidence_score NUMERIC,
    identity_source         TEXT,
    has_mlbam               BOOLEAN,
    has_retro               BOOLEAN,
    has_lahman              BOOLEAN,
    has_bbref               BOOLEAN,
    has_fangraphs           BOOLEAN,
    has_birth_date          BOOLEAN,
    id_fill_pct             NUMERIC,
    completeness_tier       TEXT,
    created_at              TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pi.player_identity_id,
        pi.mlbam_player_id,
        pi.full_name,
        pi.identity_confidence_score,
        pi.identity_source,
        (pi.mlbam_player_id         IS NOT NULL)  AS has_mlbam,
        (pi.retrosheet_player_id    IS NOT NULL)  AS has_retro,
        (pi.lahman_player_id        IS NOT NULL)  AS has_lahman,
        (pi.bbref_player_id         IS NOT NULL)  AS has_bbref,
        (pi.fangraphs_player_id     IS NOT NULL)  AS has_fangraphs,
        (pi.birth_date              IS NOT NULL)  AS has_birth_date,
        ROUND(
            100.0 *
            ( (pi.mlbam_player_id      IS NOT NULL)::INT
            + (pi.retrosheet_player_id IS NOT NULL)::INT
            + (pi.lahman_player_id     IS NOT NULL)::INT
            + (pi.bbref_player_id      IS NOT NULL)::INT
            + (pi.fangraphs_player_id  IS NOT NULL)::INT
            ) / 5.0
        , 1) AS id_fill_pct,
        CASE
            WHEN pi.identity_confidence_score >= 0.90 THEN 'GOLD'
            WHEN pi.identity_confidence_score >= 0.70 THEN 'SILVER'
            WHEN pi.identity_confidence_score >= 0.50 THEN 'BRONZE'
            ELSE 'UNRESOLVED'
        END AS completeness_tier,
        pi.created_at
    FROM stg.player_identity pi
    WHERE pi.identity_confidence_score >= p_min_confidence
       OR pi.identity_confidence_score IS NULL
    ORDER BY pi.identity_confidence_score ASC NULLS FIRST, pi.created_at ASC;
$$;

COMMENT ON FUNCTION stg.fn_validate_identity_completeness(NUMERIC) IS
    'Returns fill-rate and completeness tier for every player_identity row. '
    'GOLD >= 0.90, SILVER >= 0.70, BRONZE >= 0.50, UNRESOLVED < 0.50. '
    'Call with no args to see all rows, or pass p_min_confidence to filter. '
    'Example: SELECT * FROM stg.fn_validate_identity_completeness() WHERE completeness_tier = ''UNRESOLVED''';


-- ---------------------------------------------------------------------------
-- B. ORPHAN DETECTION
-- Finds raw_statcast.pitch rows whose batter/pitcher MLBAM IDs have no
-- matching row in stg.player_identity. Should always return zero rows if
-- the AFTER INSERT trigger is working. Treat any result as a critical alert.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_detect_orphaned_pitches(
    p_since TIMESTAMPTZ DEFAULT NOW() - INTERVAL '7 days'
)
RETURNS TABLE (
    orphan_type             TEXT,
    mlbam_player_id         BIGINT,
    times_seen              BIGINT,
    first_seen              TIMESTAMPTZ,
    last_seen               TIMESTAMPTZ,
    sample_game_date        DATE,
    sample_home_team        TEXT,
    sample_away_team        TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        'BATTER_NO_IDENTITY'   AS orphan_type,
        p.batter                AS mlbam_player_id,
        COUNT(*)                AS times_seen,
        MIN(p.game_date)        AS first_seen,
        MAX(p.game_date)        AS last_seen,
        MODE() WITHIN GROUP (ORDER BY p.game_date) AS sample_game_date,
        MODE() WITHIN GROUP (ORDER BY p.home_team)  AS sample_home_team,
        MODE() WITHIN GROUP (ORDER BY p.away_team)  AS sample_away_team
    FROM raw_statcast.pitch p
    WHERE p.game_date >= p_since::DATE
      AND NOT EXISTS (
          SELECT 1 FROM stg.player_identity pi
          WHERE pi.mlbam_player_id = p.batter
      )
    GROUP BY p.batter

    UNION ALL

    SELECT
        'PITCHER_NO_IDENTITY'  AS orphan_type,
        p.pitcher               AS mlbam_player_id,
        COUNT(*)                AS times_seen,
        MIN(p.game_date)        AS first_seen,
        MAX(p.game_date)        AS last_seen,
        MODE() WITHIN GROUP (ORDER BY p.game_date) AS sample_game_date,
        MODE() WITHIN GROUP (ORDER BY p.home_team)  AS sample_home_team,
        MODE() WITHIN GROUP (ORDER BY p.away_team)  AS sample_away_team
    FROM raw_statcast.pitch p
    WHERE p.game_date >= p_since::DATE
      AND NOT EXISTS (
          SELECT 1 FROM stg.player_identity pi
          WHERE pi.mlbam_player_id = p.pitcher
      )
    GROUP BY p.pitcher

    ORDER BY times_seen DESC;
$$;

COMMENT ON FUNCTION stg.fn_detect_orphaned_pitches(TIMESTAMPTZ) IS
    'Circuit-breaker check: returns any batter/pitcher MLBAM IDs in raw_statcast.pitch '
    'that have no corresponding row in stg.player_identity. '
    'Should always return zero rows if the AFTER INSERT trigger is functioning. '
    'Schedule nightly and alert on non-zero results. '
    'Example: SELECT * FROM stg.fn_detect_orphaned_pitches(NOW() - INTERVAL ''30 days'');';


-- ---------------------------------------------------------------------------
-- C. CONTEXTUAL PLAYER PINPOINTING
-- Uses game context (date, team, batting order, PA#) to identify the player
-- who must have been at that slot. Useful for confirming or discovering a
-- cross-source ID when only contextual facts are known.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_pinpoint_player_by_context(
    p_game_date         DATE,
    p_team_abbrev       TEXT,       -- home or away team abbreviation (Statcast format)
    p_bat_order         INT,        -- 1-9
    p_pa_number         INT DEFAULT NULL  -- plate appearance number, optional
)
RETURNS TABLE (
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    retrosheet_player_id    TEXT,
    bbref_player_id         TEXT,
    fangraphs_player_id     TEXT,
    lahman_player_id        TEXT,
    identity_confidence_score NUMERIC,
    match_method            TEXT,
    pitches_in_slot         BIGINT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        pi.mlbam_player_id,
        pi.full_name,
        pi.retrosheet_player_id,
        pi.bbref_player_id,
        pi.fangraphs_player_id,
        pi.lahman_player_id,
        pi.identity_confidence_score,
        'context:game_date+team+bat_order' AS match_method,
        COUNT(*) AS pitches_in_slot
    FROM raw_statcast.pitch p
    JOIN stg.player_identity pi ON pi.mlbam_player_id = p.batter
    WHERE p.game_date = p_game_date
      AND (
          p.home_team    ILIKE p_team_abbrev
          OR p.away_team ILIKE p_team_abbrev
          OR p.batting_team ILIKE p_team_abbrev
      )
      AND p.bat_order = p_bat_order
      AND (p_pa_number IS NULL OR p.at_bat_number = p_pa_number)
    GROUP BY
        pi.mlbam_player_id, pi.full_name, pi.retrosheet_player_id,
        pi.bbref_player_id, pi.fangraphs_player_id, pi.lahman_player_id,
        pi.identity_confidence_score
    ORDER BY pitches_in_slot DESC;
$$;

COMMENT ON FUNCTION stg.fn_pinpoint_player_by_context(DATE, TEXT, INT, INT) IS
    'Identifies the most likely player for a given game date + team + batting order slot. '
    'Returns all matching identity rows ranked by number of pitches seen in that slot. '
    'Use when you need to confirm or discover a cross-source ID using only contextual facts. '
    'Example: SELECT * FROM stg.fn_pinpoint_player_by_context(''2024-07-15'', ''NYY'', 3);';


-- ---------------------------------------------------------------------------
-- D. LINEUP CROSS-VALIDATION (MLBAM <> Retrosheet)
-- Expects stg.retrosheet_game_lineup to be populated by the Retrosheet loader.
-- Compares our MLBAM batting order against Retrosheet lineup for the same game.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.retrosheet_game_lineup (
    retro_game_id           TEXT NOT NULL,
    game_date               DATE NOT NULL,
    team_retro_id           TEXT NOT NULL,
    bat_order               INT  NOT NULL,
    retrosheet_player_id    TEXT NOT NULL,
    player_name             TEXT,
    PRIMARY KEY (retro_game_id, team_retro_id, bat_order)
);

COMMENT ON TABLE stg.retrosheet_game_lineup IS
    'Retrosheet batting order lineups loaded from game log / boxscore files. '
    'Used by fn_validate_game_lineup() to cross-check MLBAM identity assignments. '
    'Populate via: COPY stg.retrosheet_game_lineup FROM ''/data/retro_lineups.csv'' CSV HEADER;';

CREATE OR REPLACE FUNCTION stg.fn_validate_game_lineup(
    p_game_date DATE,
    p_mlbam_team TEXT
)
RETURNS TABLE (
    bat_order               INT,
    mlbam_player_id         BIGINT,
    mlbam_name              TEXT,
    retro_player_id         TEXT,
    retro_name              TEXT,
    mapped_retro_id         TEXT,
    lineup_match            BOOLEAN,
    anomaly                 TEXT
)
LANGUAGE sql
STABLE
AS $$
    WITH statcast_slots AS (
        SELECT
            p.bat_order,
            p.batter         AS mlbam_player_id,
            pi.full_name     AS mlbam_name,
            pi.retrosheet_player_id AS mapped_retro_id
        FROM raw_statcast.pitch p
        JOIN stg.player_identity pi ON pi.mlbam_player_id = p.batter
        WHERE p.game_date = p_game_date
          AND (p.home_team    ILIKE p_mlbam_team
               OR p.away_team ILIKE p_mlbam_team
               OR p.batting_team ILIKE p_mlbam_team)
        GROUP BY p.bat_order, p.batter, pi.full_name, pi.retrosheet_player_id
    ),
    retro_slots AS (
        SELECT
            r.bat_order,
            r.retrosheet_player_id AS retro_player_id,
            r.player_name          AS retro_name
        FROM stg.retrosheet_game_lineup r
        JOIN stg.team_identity ti ON ti.retrosheet_team_id = r.team_retro_id
        WHERE r.game_date = p_game_date
    )
    SELECT
        s.bat_order,
        s.mlbam_player_id,
        s.mlbam_name,
        rs.retro_player_id,
        rs.retro_name,
        s.mapped_retro_id,
        (s.mapped_retro_id = rs.retro_player_id)  AS lineup_match,
        CASE
            WHEN rs.retro_player_id IS NULL THEN 'NO_RETROSHEET_LINEUP_FOR_GAME'
            WHEN s.mapped_retro_id  IS NULL THEN 'MLBAM_PLAYER_MISSING_RETRO_ID'
            WHEN s.mapped_retro_id <> rs.retro_player_id THEN 'RETRO_ID_MISMATCH'
            ELSE NULL
        END AS anomaly
    FROM statcast_slots s
    LEFT JOIN retro_slots rs USING (bat_order)
    ORDER BY s.bat_order;
$$;

COMMENT ON FUNCTION stg.fn_validate_game_lineup(DATE, TEXT) IS
    'Cross-validates MLBAM batting order against Retrosheet lineup for a given game/team. '
    'Returns one row per batting slot with lineup_match=TRUE/FALSE and anomaly code. '
    'Requires stg.retrosheet_game_lineup to be populated for the queried game. '
    'Example: SELECT * FROM stg.fn_validate_game_lineup(''2024-08-01'', ''BOS'');';


-- ---------------------------------------------------------------------------
-- E. CHADWICK CROSS-VALIDATION
-- Diffs stg.player_identity against the most recent Chadwick register import.
-- Returns rows where our IDs diverge from Chadwick, with ready-to-run UPDATE SQL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_cross_validate_identities()
RETURNS TABLE (
    player_identity_id      BIGINT,
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    field_name              TEXT,
    our_value               TEXT,
    chadwick_value          TEXT,
    discrepancy_type        TEXT,
    suggested_action        TEXT
)
LANGUAGE sql
STABLE
AS $$
    WITH matched AS (
        SELECT
            pi.player_identity_id,
            pi.mlbam_player_id,
            pi.full_name,
            pi.retrosheet_player_id AS our_retro,
            pi.bbref_player_id      AS our_bbref,
            pi.fangraphs_player_id  AS our_fg,
            pi.lahman_player_id     AS our_lahman,
            cr.key_retro            AS ch_retro,
            cr.key_bbref            AS ch_bbref,
            cr.key_fangraphs        AS ch_fg,
            cr.key_lahman           AS ch_lahman
        FROM stg.player_identity pi
        JOIN stg.chadwick_register_import cr ON cr.key_mlbam = pi.mlbam_player_id
    )
    SELECT player_identity_id, mlbam_player_id, full_name,
           'retrosheet_player_id', our_retro, ch_retro,
           CASE
               WHEN our_retro IS NULL AND ch_retro IS NOT NULL THEN 'MISSING_IN_OURS'
               WHEN our_retro IS NOT NULL AND ch_retro IS NULL THEN 'MISSING_IN_CHADWICK'
               ELSE 'VALUE_DIFFERS'
           END,
           format(
               'UPDATE stg.player_identity SET retrosheet_player_id = %L, identity_confidence_score = GREATEST(identity_confidence_score, 0.85) WHERE player_identity_id = %s;',
               ch_retro, player_identity_id
           )
    FROM matched WHERE our_retro IS DISTINCT FROM ch_retro AND ch_retro IS NOT NULL

    UNION ALL

    SELECT player_identity_id, mlbam_player_id, full_name,
           'bbref_player_id', our_bbref, ch_bbref,
           CASE
               WHEN our_bbref IS NULL AND ch_bbref IS NOT NULL THEN 'MISSING_IN_OURS'
               WHEN our_bbref IS NOT NULL AND ch_bbref IS NULL THEN 'MISSING_IN_CHADWICK'
               ELSE 'VALUE_DIFFERS'
           END,
           format(
               'UPDATE stg.player_identity SET bbref_player_id = %L, identity_confidence_score = GREATEST(identity_confidence_score, 0.85) WHERE player_identity_id = %s;',
               ch_bbref, player_identity_id
           )
    FROM matched WHERE our_bbref IS DISTINCT FROM ch_bbref AND ch_bbref IS NOT NULL

    UNION ALL

    SELECT player_identity_id, mlbam_player_id, full_name,
           'fangraphs_player_id', our_fg, ch_fg,
           CASE
               WHEN our_fg IS NULL AND ch_fg IS NOT NULL THEN 'MISSING_IN_OURS'
               WHEN our_fg IS NOT NULL AND ch_fg IS NULL THEN 'MISSING_IN_CHADWICK'
               ELSE 'VALUE_DIFFERS'
           END,
           format(
               'UPDATE stg.player_identity SET fangraphs_player_id = %L, identity_confidence_score = GREATEST(identity_confidence_score, 0.85) WHERE player_identity_id = %s;',
               ch_fg, player_identity_id
           )
    FROM matched WHERE our_fg IS DISTINCT FROM ch_fg AND ch_fg IS NOT NULL

    UNION ALL

    SELECT player_identity_id, mlbam_player_id, full_name,
           'lahman_player_id', our_lahman, ch_lahman,
           CASE
               WHEN our_lahman IS NULL AND ch_lahman IS NOT NULL THEN 'MISSING_IN_OURS'
               WHEN our_lahman IS NOT NULL AND ch_lahman IS NULL THEN 'MISSING_IN_CHADWICK'
               ELSE 'VALUE_DIFFERS'
           END,
           format(
               'UPDATE stg.player_identity SET lahman_player_id = %L, identity_confidence_score = GREATEST(identity_confidence_score, 0.85) WHERE player_identity_id = %s;',
               ch_lahman, player_identity_id
           )
    FROM matched WHERE our_lahman IS DISTINCT FROM ch_lahman AND ch_lahman IS NOT NULL

    ORDER BY player_identity_id, field_name;
$$;

COMMENT ON FUNCTION stg.fn_cross_validate_identities() IS
    'Diffs stg.player_identity against the loaded Chadwick register import. '
    'Returns every field where our stored value differs from Chadwick with a suggested UPDATE. '
    'Run after each weekly Chadwick register reload. '
    'Review suggested_action SQL before executing — bulk apply MISSING_IN_OURS rows only. '
    'Example: SELECT * FROM stg.fn_cross_validate_identities() WHERE discrepancy_type = ''MISSING_IN_OURS'';';


-- ---------------------------------------------------------------------------
-- F. SAFE UPDATE PROCEDURE
-- All changes to stg.player_identity SHOULD go through this procedure.
-- COALESCE-safely applies changes (never overwrites non-NULL with NULL unless
-- p_force=TRUE), writes full audit log, warns on confidence downgrades.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE stg.update_player_identity(
    p_player_identity_id        BIGINT,
    p_retrosheet_player_id      TEXT        DEFAULT NULL,
    p_bbref_player_id           TEXT        DEFAULT NULL,
    p_fangraphs_player_id       TEXT        DEFAULT NULL,
    p_lahman_player_id          TEXT        DEFAULT NULL,
    p_full_name                 TEXT        DEFAULT NULL,
    p_first_name                TEXT        DEFAULT NULL,
    p_last_name                 TEXT        DEFAULT NULL,
    p_birth_date                DATE        DEFAULT NULL,
    p_mlb_debut_date            DATE        DEFAULT NULL,
    p_bats                      TEXT        DEFAULT NULL,
    p_throws                    TEXT        DEFAULT NULL,
    p_is_active                 BOOLEAN     DEFAULT NULL,
    p_identity_confidence_score NUMERIC     DEFAULT NULL,
    p_identity_source           TEXT        DEFAULT NULL,
    p_edit_source               TEXT        DEFAULT 'manual',
    p_note                      TEXT        DEFAULT NULL,
    p_force                     BOOLEAN     DEFAULT FALSE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old   stg.player_identity%ROWTYPE;
    v_conf_before NUMERIC;
BEGIN
    SELECT * INTO v_old FROM stg.player_identity WHERE player_identity_id = p_player_identity_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'player_identity_id % not found', p_player_identity_id;
    END IF;

    v_conf_before := v_old.identity_confidence_score;

    IF p_identity_confidence_score IS NOT NULL
       AND v_conf_before IS NOT NULL
       AND p_identity_confidence_score < v_conf_before THEN
        RAISE WARNING 'Confidence downgrade for player_identity_id %: % -> %',
            p_player_identity_id, v_conf_before, p_identity_confidence_score;
    END IF;

    UPDATE stg.player_identity SET
        retrosheet_player_id  = COALESCE(p_retrosheet_player_id,  retrosheet_player_id),
        bbref_player_id       = COALESCE(p_bbref_player_id,       bbref_player_id),
        fangraphs_player_id   = COALESCE(p_fangraphs_player_id,   fangraphs_player_id),
        lahman_player_id      = COALESCE(p_lahman_player_id,      lahman_player_id),
        full_name             = COALESCE(p_full_name,             full_name),
        first_name            = COALESCE(p_first_name,            first_name),
        last_name             = COALESCE(p_last_name,             last_name),
        birth_date            = COALESCE(p_birth_date,            birth_date),
        mlb_debut_date        = COALESCE(p_mlb_debut_date,        mlb_debut_date),
        bats                  = COALESCE(p_bats,                  bats),
        throws                = COALESCE(p_throws,                throws),
        is_active             = COALESCE(p_is_active,             is_active),
        identity_confidence_score = COALESCE(p_identity_confidence_score, identity_confidence_score),
        identity_source       = COALESCE(p_identity_source,       identity_source)
    WHERE player_identity_id = p_player_identity_id;

    INSERT INTO stg.player_identity_edit_log
        (player_identity_id, edit_source, field_name, old_value, new_value,
         confidence_before, confidence_after, note)
    SELECT p_player_identity_id, p_edit_source, field_name, old_val, new_val,
           v_conf_before,
           COALESCE(p_identity_confidence_score, v_conf_before),
           p_note
    FROM (
        VALUES
          ('retrosheet_player_id', v_old.retrosheet_player_id::TEXT, p_retrosheet_player_id::TEXT),
          ('bbref_player_id',      v_old.bbref_player_id::TEXT,      p_bbref_player_id::TEXT),
          ('fangraphs_player_id',  v_old.fangraphs_player_id::TEXT,  p_fangraphs_player_id::TEXT),
          ('lahman_player_id',     v_old.lahman_player_id::TEXT,     p_lahman_player_id::TEXT),
          ('full_name',            v_old.full_name::TEXT,            p_full_name::TEXT),
          ('birth_date',           v_old.birth_date::TEXT,           p_birth_date::TEXT),
          ('identity_confidence_score',
           v_old.identity_confidence_score::TEXT,
           p_identity_confidence_score::TEXT)
    ) AS changes(field_name, old_val, new_val)
    WHERE new_val IS NOT NULL
      AND new_val IS DISTINCT FROM old_val;

END;
$$;

COMMENT ON PROCEDURE stg.update_player_identity IS
    'Safe, audited update path for all changes to stg.player_identity. '
    'Never overwrites a non-NULL field with NULL unless p_force=TRUE. '
    'Warns on confidence score downgrades. Writes every change to stg.player_identity_edit_log. '
    'Use from Python enrichment workers, Chadwick sync jobs, and manual corrections. '
    'Example: CALL stg.update_player_identity(42, p_retrosheet_player_id=>''troutm001'', p_identity_confidence_score=>0.95, p_edit_source=>''chadwick_sync'');';


-- ---------------------------------------------------------------------------
-- G. OPERATIONAL VIEWS
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW stg.v_identity_completeness_dashboard AS
SELECT
    completeness_tier,
    COUNT(*)                                            AS player_count,
    ROUND(AVG(id_fill_pct), 1)                          AS avg_id_fill_pct,
    COUNT(*) FILTER (WHERE has_mlbam)                   AS has_mlbam,
    COUNT(*) FILTER (WHERE has_retro)                   AS has_retro,
    COUNT(*) FILTER (WHERE has_lahman)                  AS has_lahman,
    COUNT(*) FILTER (WHERE has_bbref)                   AS has_bbref,
    COUNT(*) FILTER (WHERE has_fangraphs)               AS has_fangraphs
FROM stg.fn_validate_identity_completeness()
GROUP BY completeness_tier
ORDER BY
    CASE completeness_tier
        WHEN 'GOLD'       THEN 1
        WHEN 'SILVER'     THEN 2
        WHEN 'BRONZE'     THEN 3
        WHEN 'UNRESOLVED' THEN 4
    END;

COMMENT ON VIEW stg.v_identity_completeness_dashboard IS
    'Operational health dashboard: player counts per tier (GOLD/SILVER/BRONZE/UNRESOLVED) '
    'with per-source fill counts. SELECT * FROM stg.v_identity_completeness_dashboard;';


CREATE OR REPLACE VIEW stg.v_players_needing_review AS
SELECT
    pi.player_identity_id,
    pi.mlbam_player_id,
    pi.full_name,
    pi.identity_confidence_score,
    pi.identity_source,
    pi.retrosheet_player_id,
    pi.bbref_player_id,
    pi.fangraphs_player_id,
    pi.lahman_player_id,
    pi.created_at,
    pi.updated_at,
    (
        SELECT COUNT(*) FROM raw_statcast.pitch p
        WHERE p.batter = pi.mlbam_player_id
           OR p.pitcher = pi.mlbam_player_id
    ) AS total_statcast_appearances
FROM stg.player_identity pi
WHERE pi.identity_confidence_score < 0.60
   OR pi.identity_confidence_score IS NULL
ORDER BY total_statcast_appearances DESC, pi.identity_confidence_score ASC NULLS FIRST;

COMMENT ON VIEW stg.v_players_needing_review IS
    'Human review queue: players with identity_confidence_score < 0.60. '
    'Ordered by Statcast appearances DESC so highest-impact unresolved players surface first. '
    'Reviewer calls stg.update_player_identity() to apply and record corrections.';


CREATE OR REPLACE VIEW stg.v_live_players_pending_retro AS
SELECT
    pi.player_identity_id,
    pi.mlbam_player_id,
    pi.full_name,
    pi.mlb_debut_date,
    pi.identity_confidence_score,
    pi.identity_source,
    pi.retrosheet_player_id,
    pi.bbref_player_id,
    pi.fangraphs_player_id,
    pi.lahman_player_id,
    pi.created_at                                   AS first_seen_in_statcast,
    EXTRACT(DAY FROM NOW() - pi.created_at)::INT    AS days_since_first_seen
FROM stg.player_identity pi
WHERE pi.mlbam_player_id IS NOT NULL
  AND pi.identity_confidence_score >= 0.70
  AND (
      pi.retrosheet_player_id IS NULL
      OR pi.bbref_player_id   IS NULL
  )
ORDER BY pi.created_at;

COMMENT ON VIEW stg.v_live_players_pending_retro IS
    'Players resolved via MLB StatsAPI (confidence >= 0.70) but whose Retrosheet and/or BRef IDs '
    'have not yet been published by Chadwick. Normal for debut-season players. '
    'Re-check weekly after each Chadwick register reload.';

COMMIT;
