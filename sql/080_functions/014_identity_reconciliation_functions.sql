-- =============================================================================
-- Player Identity Reconciliation Functions
--
-- Addendum to 013_identity_validation_functions.sql.
-- Implements the "fix it or notify" layer for Issue #13:
--   candidates above the confidence threshold are auto-promoted;
--   candidates below it are flagged for human review.
--
-- Functions and objects in this file:
--   8.  stg.fn_reconcile_candidates()              — promote or flag candidates
--   9.  stg.v_candidates_pending_human_review       — human review queue with accept/reject SQL
--  10.  stg.fn_contextual_fingerprint_check()       — batting-slot consistency validator
--  11.  stg.fn_full_identity_health_report()        — JSON health report for cron/alerting
--
-- Run order: apply after 013_identity_validation_functions.sql.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 8. fn_reconcile_candidates
--
-- Processes rows in stg.player_identity_candidate and either:
--   a) AUTO-PROMOTES  — candidate_score >= p_auto_threshold AND not yet reviewed
--                       -> calls stg.update_player_identity() with the IDs
--   b) FLAGS FOR REVIEW — candidate_score < p_auto_threshold
--                       -> marks reviewed_flag = FALSE, accepted_flag = NULL
--                       -> inserts a row into stg.player_identity_resolution_log
--                          with action_taken = 'CANDIDATE_NEEDS_REVIEW'
--
-- This is the "fix it or notify" bridge between the Python enrichment worker
-- and the human review queue. The Python worker inserts candidates; this
-- procedure decides what to do with them.
--
-- Parameters:
--   p_auto_threshold  — score >= this -> auto-promote (default 0.85)
--   p_limit           — max candidates to process in one call (default 500)
--
-- Example:
--   SELECT * FROM stg.fn_reconcile_candidates();            -- default thresholds
--   SELECT * FROM stg.fn_reconcile_candidates(0.90, 200);   -- stricter auto
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_reconcile_candidates(
    p_auto_threshold    NUMERIC  DEFAULT 0.85,
    p_limit             INT      DEFAULT 500
)
RETURNS TABLE (
    candidate_id        BIGINT,
    mlbam_player_id     BIGINT,
    candidate_name      TEXT,
    candidate_score     NUMERIC,
    action              TEXT,   -- 'AUTO_PROMOTED' | 'FLAGGED_FOR_REVIEW' | 'ALREADY_REVIEWED'
    note                TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    r           stg.player_identity_candidate%ROWTYPE;
    v_action    TEXT;
    v_note      TEXT;
    v_pid       BIGINT;
BEGIN
    FOR r IN
        SELECT *
        FROM   stg.player_identity_candidate
        WHERE  reviewed_flag = FALSE
        ORDER  BY candidate_score DESC NULLS LAST
        LIMIT  p_limit
        FOR    UPDATE SKIP LOCKED          -- safe for concurrent workers
    LOOP
        -- Locate the target player_identity row by MLBAM id
        SELECT player_identity_id
        INTO   v_pid
        FROM   stg.player_identity
        WHERE  mlbam_player_id = r.mlbam_player_id
        LIMIT  1;

        IF v_pid IS NULL THEN
            -- Edge case: the candidate has an MLBAM id we have never seen.
            -- Insert a placeholder so the identity row exists, then capture its id.
            INSERT INTO stg.player_identity (
                mlbam_player_id, full_name,
                identity_confidence_score, identity_source
            )
            VALUES (
                r.mlbam_player_id, r.candidate_name,
                0.0, 'candidate:placeholder'
            )
            ON CONFLICT (mlbam_player_id)
            WHERE mlbam_player_id IS NOT NULL
            DO NOTHING
            RETURNING player_identity_id INTO v_pid;

            -- If ON CONFLICT fired, fetch the existing row id
            IF v_pid IS NULL THEN
                SELECT player_identity_id INTO v_pid
                FROM   stg.player_identity
                WHERE  mlbam_player_id = r.mlbam_player_id
                LIMIT  1;
            END IF;
        END IF;

        IF r.candidate_score >= p_auto_threshold THEN
            -- AUTO-PROMOTE: call the safe update procedure
            CALL stg.update_player_identity(
                p_player_identity_id := v_pid,
                p_retrosheet_id     := r.retrosheet_player_id,
                p_bbref_id          := r.bbref_player_id,
                p_fangraphs_id      := r.fangraphs_player_id,
                p_lahman_id         := r.lahman_player_id,
                p_confidence        := r.candidate_score,
                p_change_source     := 'candidate:auto_promote:' || r.source_system_code
            );

            v_action := 'AUTO_PROMOTED';
            v_note   := format(
                'score=%.4f source=%s retro=%s bbref=%s fg=%s lahman=%s',
                r.candidate_score, r.source_system_code,
                COALESCE(r.retrosheet_player_id, 'NULL'),
                COALESCE(r.bbref_player_id,      'NULL'),
                COALESCE(r.fangraphs_player_id,  'NULL'),
                COALESCE(r.lahman_player_id,      'NULL')
            );

            -- Mark candidate as reviewed and accepted
            UPDATE stg.player_identity_candidate
            SET    reviewed_flag = TRUE,
                   accepted_flag = TRUE
            WHERE  player_identity_candidate_id = r.player_identity_candidate_id;

        ELSE
            -- FLAG FOR REVIEW: do NOT update identity, just notify
            v_action := 'FLAGGED_FOR_REVIEW';
            v_note   := format(
                'score=%.4f below auto_threshold=%.2f. '
                'Check stg.player_identity_candidate id=%s. '
                'Resolve via CALL stg.update_player_identity(%s, ...) or '
                'UPDATE stg.player_identity_candidate SET accepted_flag=TRUE '
                'WHERE player_identity_candidate_id=%s;',
                r.candidate_score, p_auto_threshold,
                r.player_identity_candidate_id,
                v_pid,
                r.player_identity_candidate_id
            );

            -- Write to resolution log as a human-readable notification
            INSERT INTO stg.player_identity_resolution_log (
                trigger_source, mlbam_player_id, player_name,
                action_taken, player_identity_id, note
            ) VALUES (
                'fn_reconcile_candidates',
                r.mlbam_player_id,
                r.candidate_name,
                'CANDIDATE_NEEDS_REVIEW',
                v_pid,
                v_note
            );

            -- Mark candidate as reviewed (but NOT accepted).
            -- A human must set accepted_flag = TRUE or FALSE.
            UPDATE stg.player_identity_candidate
            SET    reviewed_flag = TRUE,
                   accepted_flag = NULL       -- NULL = pending human decision
            WHERE  player_identity_candidate_id = r.player_identity_candidate_id;
        END IF;

        -- Yield result row
        RETURN QUERY
        SELECT
            r.player_identity_candidate_id,
            r.mlbam_player_id,
            r.candidate_name,
            r.candidate_score,
            v_action,
            v_note;

    END LOOP;
END;
$$;

COMMENT ON FUNCTION stg.fn_reconcile_candidates(NUMERIC, INT) IS
    'Processes stg.player_identity_candidate rows. '
    'Scores >= p_auto_threshold (default 0.85) are auto-promoted via stg.update_player_identity(). '
    'Lower scores are flagged in stg.player_identity_resolution_log for human review. '
    'Run after each Python enrichment worker batch. '
    'Example: SELECT * FROM stg.fn_reconcile_candidates();';


-- ---------------------------------------------------------------------------
-- 9. v_candidates_pending_human_review
--
-- Shows all candidates that were flagged by fn_reconcile_candidates but
-- not yet accepted or rejected by a human. Each row includes a ready-to-run
-- CALL statement (accept_sql) and a reject UPDATE (reject_sql) so a reviewer
-- can paste directly into psql.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg.v_candidates_pending_human_review AS
SELECT
    c.player_identity_candidate_id,
    c.mlbam_player_id,
    c.candidate_name,
    c.source_system_code,
    c.candidate_score,
    c.candidate_reason,
    c.retrosheet_player_id,
    c.bbref_player_id,
    c.fangraphs_player_id,
    c.lahman_player_id,
    c.candidate_birth_date,
    c.created_at,
    pi.player_identity_id,
    pi.full_name                    AS current_full_name,
    pi.identity_confidence_score    AS current_confidence,
    -- Ready-to-run CALL to accept this candidate
    format(
        'CALL stg.update_player_identity(%s, %L, %L, %L, %L, %s, ''manual:human_review'');',
        pi.player_identity_id,
        c.retrosheet_player_id,
        c.bbref_player_id,
        c.fangraphs_player_id,
        c.lahman_player_id,
        c.candidate_score
    ) AS accept_sql,
    -- Ready-to-run UPDATE to reject this candidate
    format(
        'UPDATE stg.player_identity_candidate SET accepted_flag = FALSE WHERE player_identity_candidate_id = %s;',
        c.player_identity_candidate_id
    ) AS reject_sql
FROM stg.player_identity_candidate c
JOIN stg.player_identity pi ON pi.mlbam_player_id = c.mlbam_player_id
WHERE c.reviewed_flag = TRUE
  AND c.accepted_flag IS NULL        -- pending human decision
ORDER BY c.candidate_score DESC, c.created_at;

COMMENT ON VIEW stg.v_candidates_pending_human_review IS
    'Candidates flagged by fn_reconcile_candidates that require human review. '
    'Each row includes accept_sql and reject_sql ready to paste into psql. '
    'After accepting, run SELECT * FROM stg.fn_validate_identity_completeness() to confirm fill rates improved.';


-- ---------------------------------------------------------------------------
-- 10. fn_contextual_fingerprint_check
--
-- Uses observable game facts (batting order slot consistency across all
-- pitches in a game) to validate whether MLBAM -> identity mappings are
-- internally consistent.
--
-- Logic: for each batter in the game, compute what fraction of their pitches
-- occurred in their most-common batting-order slot. A ratio < 0.70 means the
-- same MLBAM id appeared in multiple slots, which is physically impossible
-- and indicates a wrong identity mapping.
--
-- Parameters:
--   p_game_date   — game date
--   p_game_pk     — Statcast game_pk
--
-- Example:
--   SELECT * FROM stg.fn_contextual_fingerprint_check('2024-07-15', 532441)
--   WHERE flag LIKE 'WARN%';
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_contextual_fingerprint_check(
    p_game_date     DATE,
    p_game_pk       BIGINT
)
RETURNS TABLE (
    mlbam_player_id         BIGINT,
    full_name               TEXT,
    retrosheet_player_id    TEXT,
    bbref_player_id         TEXT,
    bat_order_pos           NUMERIC,
    total_pitches_in_game   BIGINT,
    pitches_same_slot       BIGINT,
    fingerprint_confidence  NUMERIC(5,4),
    flag                    TEXT
)
LANGUAGE sql
STABLE
AS $$
    WITH game_pitches AS (
        SELECT
            p.batter,
            p.bat_order,
            COUNT(*) AS pitch_count
        FROM raw_statcast.pitch p
        WHERE p.game_date = p_game_date
          AND p.game_pk   = p_game_pk
          AND p.batter    IS NOT NULL
        GROUP BY p.batter, p.bat_order
    ),
    batter_totals AS (
        SELECT
            batter,
            SUM(pitch_count)                                       AS total_pitches,
            MODE() WITHIN GROUP (ORDER BY bat_order)               AS modal_bat_order
        FROM game_pitches
        GROUP BY batter
    ),
    slot_agreement AS (
        SELECT
            bt.batter,
            bt.total_pitches,
            bt.modal_bat_order,
            COALESCE(
                SUM(gp.pitch_count) FILTER (WHERE gp.bat_order = bt.modal_bat_order),
                0
            ) AS pitches_in_modal_slot
        FROM batter_totals bt
        JOIN game_pitches gp ON gp.batter = bt.batter
        GROUP BY bt.batter, bt.total_pitches, bt.modal_bat_order
    )
    SELECT
        sa.batter                       AS mlbam_player_id,
        pi.full_name,
        pi.retrosheet_player_id,
        pi.bbref_player_id,
        sa.modal_bat_order              AS bat_order_pos,
        sa.total_pitches                AS total_pitches_in_game,
        sa.pitches_in_modal_slot        AS pitches_same_slot,
        ROUND(
            sa.pitches_in_modal_slot::NUMERIC
            / NULLIF(sa.total_pitches, 0),
            4
        )                               AS fingerprint_confidence,
        CASE
            WHEN (sa.pitches_in_modal_slot::NUMERIC
                  / NULLIF(sa.total_pitches, 0)) < 0.70
            THEN 'WARN: player appeared in multiple batting slots - possible wrong identity mapping'
            WHEN pi.retrosheet_player_id IS NULL
            THEN 'INFO: no retrosheet_player_id yet - cannot cross-validate with Retrosheet'
            ELSE 'OK'
        END                             AS flag
    FROM slot_agreement sa
    LEFT JOIN stg.player_identity pi
        ON pi.mlbam_player_id = sa.batter
    ORDER BY fingerprint_confidence ASC;
$$;

COMMENT ON FUNCTION stg.fn_contextual_fingerprint_check(DATE, BIGINT) IS
    'Validates player identity mappings using batting-order slot consistency across a game. '
    'A player appearing in multiple batting slots is physically impossible - '
    'fingerprint_confidence < 0.70 = WARN flag, investigate stg.player_identity for that MLBAM id. '
    'INFO flag = normal for rookies/callups with no retrosheet_player_id yet. '
    'Example: SELECT * FROM stg.fn_contextual_fingerprint_check(''2024-07-15'', 532441) WHERE flag LIKE ''WARN%'';';


-- ---------------------------------------------------------------------------
-- 11. fn_full_identity_health_report
--
-- Aggregates all validation signals into a single JSONB report suitable for
-- logging, alerting pipelines, or Python consumption.
-- Logs every run to stg.player_identity_resolution_log for trend tracking.
--
-- critical_alert = TRUE when orphaned_pitches_48h > 0 (trigger failure).
-- Treat this as a PagerDuty-level alert.
--
-- Example:
--   SELECT stg.fn_full_identity_health_report();
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_full_identity_health_report()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_completeness  JSONB;
    v_orphans       BIGINT;
    v_manual_review BIGINT;
    v_candidates    BIGINT;
    v_chadwick_diff BIGINT;
    v_report        JSONB;
BEGIN
    SELECT jsonb_object_agg(id_column, jsonb_build_object(
        'fill_rate_pct', fill_rate_pct,
        'missing',        missing,
        'populated',      populated
    ))
    INTO v_completeness
    FROM stg.fn_validate_identity_completeness();

    SELECT COUNT(*) INTO v_orphans
    FROM stg.fn_detect_orphaned_pitches();

    SELECT COUNT(*) INTO v_manual_review
    FROM stg.player_identity
    WHERE identity_confidence_score > 0
      AND identity_confidence_score < 0.60;

    SELECT COUNT(*) INTO v_candidates
    FROM stg.player_identity_candidate
    WHERE reviewed_flag = TRUE AND accepted_flag IS NULL;

    SELECT COUNT(*) INTO v_chadwick_diff
    FROM stg.fn_cross_validate_identities();

    v_report := jsonb_build_object(
        'report_generated_at',      NOW(),
        'orphaned_pitches_48h',     v_orphans,
        'critical_alert',           v_orphans > 0,
        'needs_manual_review',      v_manual_review,
        'candidates_pending_human', v_candidates,
        'chadwick_divergences',     v_chadwick_diff,
        'id_completeness',          v_completeness
    );

    -- Log the health report to resolution log for trend tracking
    INSERT INTO stg.player_identity_resolution_log (
        trigger_source, mlbam_player_id, player_name, action_taken,
        player_identity_id, note
    ) VALUES (
        'fn_full_identity_health_report',
        NULL, NULL,
        'HEALTH_REPORT',
        NULL,
        v_report::TEXT
    );

    RETURN v_report;
END;
$$;

COMMENT ON FUNCTION stg.fn_full_identity_health_report() IS
    'Aggregates all identity validation signals into a single JSONB health report. '
    'Call from your cron job after each enrichment run. '
    'critical_alert = true when orphaned_pitches_48h > 0 (trigger failure - CRITICAL alert). '
    'Logs every report run to stg.player_identity_resolution_log for trend tracking. '
    'Example: SELECT stg.fn_full_identity_health_report();';


COMMIT;
